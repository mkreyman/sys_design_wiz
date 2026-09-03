defmodule SysDesignWiz.LLM.ModelResolver do
  @moduledoc """
  Evergreen Anthropic model selection.

  Pinning a dated model id breaks every call the moment Anthropic retires it:
  the API answers `404 not_found_error`, and nothing in this app can tell that
  from any other 404. This module had a live case — `@default_model` here was
  `claude-sonnet-4-20250514`, retired on 2026-06-15, so every chat this app
  made would have failed with no message naming the model. There is no
  `-latest` alias to fall back on (`claude-*-latest` also 404s), so pinning is
  a RECURRING outage on Anthropic's schedule rather than a one-off.

  So the caller names a TIER — `:sonnet`, `:opus` or `:haiku` — and this
  resolver returns the newest id of that tier, taken from `GET /v1/models` and
  chosen by the API's `created_at`.

  Reads are served from ETS with a pinned, currently-valid fallback per tier, so
  the hot path never blocks on a live fetch and this module never crashes a
  request. The cache is keyed by a SHA-256 fingerprint of the API key (the key
  itself is never stored) so a rotated key never serves the previous key's
  answer.

  - `latest_model/2` — non-blocking; cached value or fallback (+ async refresh).
  - `refresh_and_latest/2` — blocking force-fetch, for the client's 404
    self-heal, so a just-retired model is never handed back from a stale cache.

  Fetching is gated behind:

      config :sys_design_wiz, SysDesignWiz.LLM.ModelResolver, enabled: true

  which `config/test.exs` sets to `false`, so the suite never hits the network
  and always serves the pinned fallbacks.
  """
  use GenServer

  require Logger

  @table :sys_design_wiz_model_resolver_cache
  @models_url "https://api.anthropic.com/v1/models?limit=100"
  @anthropic_version "2023-06-01"
  @ttl_ms :timer.hours(24)
  @http_timeout 10_000

  @tiers ~w(sonnet opus haiku)

  # Currently-valid fallback per tier, used only on a cold cache or a failed
  # fetch. Verified against /v1/models on 2026-09-03.
  @fallbacks %{
    "sonnet" => "claude-sonnet-5",
    "opus" => "claude-opus-5",
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
  Forces a fresh `/v1/models` fetch for `api_key` and returns the newest model
  of the tier. On fetch failure, falls back to the pinned id — deliberately NOT
  to the cached one, since the caller is here precisely because the cached id
  just 404'd. Blocking; intended for the 404 self-heal path only.
  """
  @spec refresh_and_latest(String.t(), atom() | String.t()) :: String.t()
  def refresh_and_latest(api_key, tier) when is_binary(api_key) do
    t = tier_key(tier)
    forget(api_key)

    case do_fetch_and_cache(api_key) do
      {:ok, by_tier} -> Map.get(by_tier, t) || fallback(t)
      {:error, _} -> fallback(t)
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

  @doc "The pinned fallback map, exposed for tests and diagnostics."
  @spec fallbacks() :: %{String.t() => String.t()}
  def fallbacks, do: @fallbacks

  # -- GenServer --

  @impl GenServer
  def init(opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{enabled: Keyword.get(opts, :enabled, enabled?())}}
  end

  @impl GenServer
  def handle_cast({:refresh, api_key}, %{enabled: true} = state) do
    # latest_model/2 casts on EVERY call while the cache is stale, so a cold
    # cache under load piles identical casts into this mailbox. Re-check
    # staleness here so the first one refreshes and the rest collapse to no-ops
    # instead of each blocking 10s on /v1/models in turn.
    if cache_stale?(api_key), do: do_fetch_and_cache(api_key)
    {:noreply, state}
  end

  def handle_cast({:refresh, _api_key}, state), do: {:noreply, state}

  # -- Internals --

  defp cache_stale?(api_key) do
    fp = fingerprint(api_key)

    Enum.any?(@tiers, fn tier ->
      case lookup({fp, tier}) do
        {:ok, {_model, ts}} -> stale?(ts)
        :error -> true
      end
    end)
  end

  defp forget(api_key) do
    fp = fingerprint(api_key)
    Enum.each(@tiers, &delete({fp, &1}))
  end

  defp do_fetch_and_cache(api_key) do
    if enabled?() do
      refresh_and_cache(api_key, &Req.get/2)
    else
      {:error, :disabled}
    end
  end

  @doc """
  Fetches `/v1/models` via `http_get` and caches the newest id per tier. Unlike
  the private path, this is NOT gated by the `:enabled` config — supplying a
  getter is an explicit request to fetch, so tests can exercise the whole
  fetch/select/cache pipeline with a stub while production stays disabled in
  test. Public for testing.
  """
  @spec refresh_and_cache(String.t(), (String.t(), keyword() -> term())) ::
          {:ok, %{String.t() => String.t()}} | {:error, term()}
  def refresh_and_cache(api_key, http_get) when is_binary(api_key) and is_function(http_get, 2) do
    case fetch_models(api_key, http_get) do
      {:ok, data} -> cache_models(api_key, data)
      {:error, reason} -> {:error, reason}
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

  defp fetch_models(api_key, http_get) do
    case http_get.(@models_url,
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

  defp fingerprint(api_key), do: :crypto.hash(:sha256, api_key) |> Base.encode16()

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

  defp delete(key) do
    :ets.delete(@table, key)
    :ok
  rescue
    ArgumentError -> :ok
  end

  defp enabled? do
    Application.get_env(:sys_design_wiz, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end
end
