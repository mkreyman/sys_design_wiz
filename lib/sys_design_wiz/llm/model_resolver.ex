defmodule SysDesignWiz.LLM.ModelResolver do
  @moduledoc """
  Evergreen Anthropic model selection for the app's single global API key.

  Pinning a dated model id (e.g. `claude-sonnet-4-20250514`) breaks every call
  the moment Anthropic retires it (the API returns `404 not_found_error`).
  Anthropic offers no `-latest` alias on our account, so this resolver keeps the
  model evergreen: it fetches `GET /v1/models` and caches, per tier, the NEWEST
  model id (by the API's `created_at`).

  This app uses a single global `ANTHROPIC_API_KEY`, so there is exactly one key
  in play. The cache is still keyed by a SHA-256 fingerprint of the key (the key
  itself is never stored) to keep the same API shape as the per-org reportex
  resolver and to stay correct if the key is ever rotated. Reads are served from
  ETS with a current verified-good fallback per tier, so the hot path never
  blocks on a live fetch and this module never crashes a request.

  - `latest_model/2` — non-blocking; cached value or fallback (+ async refresh).
  - `refresh_and_latest/2` — blocking force-fetch; used by the client's 404
    self-heal so a just-retired model is never returned from a stale cache.
  """
  use GenServer

  require Logger

  @table :sys_design_wiz_model_resolver_cache
  @models_url "https://api.anthropic.com/v1/models?limit=100"
  @anthropic_version "2023-06-01"
  @ttl_ms :timer.hours(24)
  @http_timeout 10_000

  @tiers ~w(sonnet opus haiku)

  # Current, verified-good fallback per tier (used only on a cold cache or a
  # failed fetch). Keep these pointed at models that currently exist.
  @fallbacks %{
    "sonnet" => "claude-sonnet-4-6",
    "opus" => "claude-opus-4-8",
    "haiku" => "claude-haiku-4-5-20251001"
  }

  # -- Public API --

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Newest model id of a tier for `api_key`. Non-blocking: returns the cached
  value (refreshing in the background if stale) or a pinned fallback (triggering
  an async refresh). `tier` may be an atom/string tier or a model id to derive
  the tier from.
  """
  @spec latest_model(String.t(), atom() | String.t()) :: String.t()
  def latest_model(api_key, tier) when is_binary(api_key) do
    t = tier_key(tier)

    case lookup({fingerprint(api_key), t}) do
      {:ok, {model, ts}} ->
        if stale?(ts), do: refresh_async(api_key)
        model

      :error ->
        refresh_async(api_key)
        fallback(t)
    end
  end

  @doc """
  Forces a fresh `/v1/models` fetch for `api_key` and returns the newest model of
  the tier. On fetch failure, falls back to any cached value, then the pinned
  fallback. Blocking — intended for the 404 self-heal path only.
  """
  @spec refresh_and_latest(String.t(), atom() | String.t()) :: String.t()
  def refresh_and_latest(api_key, tier) when is_binary(api_key) do
    t = tier_key(tier)

    case do_fetch_and_cache(api_key) do
      {:ok, by_tier} ->
        Map.get(by_tier, t) || cached_or_fallback(api_key, t)

      {:error, _} ->
        cached_or_fallback(api_key, t)
    end
  end

  @doc "Fire-and-forget refresh of the cache for `api_key`."
  @spec refresh_async(String.t()) :: :ok
  def refresh_async(api_key) when is_binary(api_key) do
    if pid = Process.whereis(__MODULE__), do: GenServer.cast(pid, {:refresh, api_key})
    :ok
  end

  @doc "Derives the tier (sonnet, opus or haiku) from a model id."
  @spec tier_of(String.t()) :: String.t()
  def tier_of(model) when is_binary(model) do
    Enum.find(@tiers, "sonnet", &String.contains?(model, &1))
  end

  # -- GenServer --

  @impl GenServer
  def init(opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{enabled: Keyword.get(opts, :enabled, enabled?())}}
  end

  @impl GenServer
  def handle_cast({:refresh, api_key}, %{enabled: true} = state) do
    do_fetch_and_cache(api_key)
    {:noreply, state}
  end

  def handle_cast({:refresh, _api_key}, state), do: {:noreply, state}

  # -- Internals --

  defp cached_or_fallback(api_key, tier) do
    case lookup({fingerprint(api_key), tier}) do
      {:ok, {model, _ts}} -> model
      :error -> fallback(tier)
    end
  end

  defp do_fetch_and_cache(api_key) do
    if enabled?() do
      case fetch_models(api_key) do
        {:ok, data} -> cache_models(api_key, data)
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :disabled}
    end
  end

  defp cache_models(api_key, data) do
    fp = fingerprint(api_key)
    now = now_ms()

    by_tier =
      for tier <- @tiers, id = select_newest_model(data, tier), id != nil, into: %{} do
        insert({fp, tier}, {id, now})
        {tier, id}
      end

    {:ok, by_tier}
  end

  @doc """
  Picks the newest model id of a tier from a `/v1/models` `data` list (filter by
  tier substring, sort by `created_at` desc). Returns `nil` if none. Public for
  testing.
  """
  @spec select_newest_model([map()], String.t()) :: String.t() | nil
  def select_newest_model(models, tier) do
    models
    |> Enum.filter(&String.contains?(&1["id"] || "", tier))
    |> Enum.sort_by(&(&1["created_at"] || ""), :desc)
    |> case do
      [%{"id" => id} | _] -> id
      _ -> nil
    end
  end

  defp fetch_models(api_key) do
    case Req.get(@models_url,
           headers: [{"x-api-key", api_key}, {"anthropic-version", @anthropic_version}],
           retry: false,
           receive_timeout: @http_timeout
         ) do
      {:ok, %{status: 200, body: %{"data" => data}}} when is_list(data) ->
        {:ok, data}

      {:ok, %{status: status}} ->
        Logger.warning("[LLM.ModelResolver] /v1/models returned #{status}")
        {:error, {:http, status}}

      {:error, reason} ->
        Logger.warning("[LLM.ModelResolver] /v1/models fetch failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp tier_key(tier) when tier in @tiers, do: tier
  defp tier_key(tier) when is_atom(tier), do: tier_key(Atom.to_string(tier))
  defp tier_key(model) when is_binary(model), do: tier_of(model)

  defp fallback(tier), do: Map.get(@fallbacks, tier, @fallbacks["sonnet"])

  defp fingerprint(api_key) do
    :crypto.hash(:sha256, api_key) |> Base.encode16()
  end

  defp stale?(ts), do: now_ms() - ts > @ttl_ms

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> {:ok, value}
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp insert(key, value) do
    :ets.insert(@table, {key, value})
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp enabled? do
    Application.get_env(:sys_design_wiz, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
