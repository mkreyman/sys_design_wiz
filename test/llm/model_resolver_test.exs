defmodule SysDesignWiz.LLM.ModelResolverTest do
  @moduledoc """
  The resolver exists so a retired model id cannot silently break every chat.
  These assert the parts that would fail silently if they were wrong: picking
  the newest id rather than the first one, never serving one key's answer to
  another, and — the one that actually bit — never handing back the id that
  just 404'd.

  Fetching is disabled in test (`config/test.exs`), so nothing here reaches the
  network; the fetch path is exercised through the `refresh_and_cache/2`
  injection seam with a stubbed getter.
  """
  use ExUnit.Case, async: false

  alias SysDesignWiz.LLM.ModelResolver

  # Shuffled relative to created_at, so a test that passed by list order rather
  # than by date would fail here.
  @models [
    %{"id" => "claude-opus-4-5-20251101", "created_at" => "2025-11-24T00:00:00Z"},
    %{"id" => "claude-sonnet-5", "created_at" => "2026-06-29T00:00:00Z"},
    %{"id" => "claude-opus-5", "created_at" => "2026-07-24T00:00:00Z"},
    %{"id" => "claude-haiku-4-5-20251001", "created_at" => "2025-10-15T00:00:00Z"},
    %{"id" => "claude-sonnet-4-20250514", "created_at" => "2025-05-14T00:00:00Z"},
    %{"id" => "claude-opus-4-8", "created_at" => "2026-05-28T00:00:00Z"}
  ]

  defp ok_getter(models \\ @models) do
    fn _url, _opts -> {:ok, %{status: 200, body: %{"data" => models}}} end
  end

  defp key, do: "key-#{System.unique_integer([:positive])}"

  describe "select_newest_model/2" do
    test "picks by created_at, not by position in the list" do
      assert ModelResolver.select_newest_model(@models, "opus") == "claude-opus-5"
      assert ModelResolver.select_newest_model(@models, "sonnet") == "claude-sonnet-5"
      assert ModelResolver.select_newest_model(@models, "haiku") == "claude-haiku-4-5-20251001"
    end

    test "returns nil for a tier the account cannot reach" do
      assert ModelResolver.select_newest_model(@models, "nonexistent") == nil
    end

    test "an entry missing created_at sorts last instead of crashing" do
      models = [%{"id" => "claude-opus-4-8"}, %{"id" => "claude-opus-5", "created_at" => "2026"}]
      assert ModelResolver.select_newest_model(models, "opus") == "claude-opus-5"
    end
  end

  describe "tier_of/1" do
    test "derives the tier from an id, dated or not" do
      assert ModelResolver.tier_of("claude-haiku-4-5-20251001") == "haiku"
      assert ModelResolver.tier_of("claude-opus-5") == "opus"
      assert ModelResolver.tier_of("claude-sonnet-4-20250514") == "sonnet"
    end

    test "an unrecognised family falls to sonnet rather than nil" do
      assert ModelResolver.tier_of("claude-fable-5-1") == "sonnet"
    end
  end

  describe "pinned fallbacks" do
    test "every fallback belongs to the tier it is filed under" do
      for {tier, model} <- ModelResolver.fallbacks() do
        assert ModelResolver.tier_of(model) == tier
      end
    end

    test "no fallback is one of the ids Anthropic has already retired" do
      retired = [
        "claude-sonnet-4-20250514",
        "claude-3-5-haiku-20241022",
        "claude-opus-4-20250514"
      ]

      for {_tier, model} <- ModelResolver.fallbacks() do
        refute model in retired
      end
    end
  end

  describe "latest_model/2 with fetching disabled" do
    test "serves the pinned fallback rather than failing" do
      k = key()

      for {tier, expected} <- ModelResolver.fallbacks() do
        assert ModelResolver.latest_model(k, tier) == expected
        assert ModelResolver.latest_model(k, String.to_atom(tier)) == expected
      end
    end

    test "accepts a model id in place of a tier" do
      assert ModelResolver.latest_model(key(), "claude-opus-4-8") ==
               ModelResolver.fallbacks()["opus"]
    end
  end

  describe "refresh_and_cache/2" do
    test "caches the newest id per tier and serves it to later reads" do
      k = key()
      assert {:ok, by_tier} = ModelResolver.refresh_and_cache(k, ok_getter())
      assert by_tier["opus"] == "claude-opus-5"
      assert ModelResolver.latest_model(k, :opus) == "claude-opus-5"
      assert ModelResolver.latest_model(k, :sonnet) == "claude-sonnet-5"
    end

    test "another key does not see it — the cache is keyed by key fingerprint" do
      k = key()
      other = key()
      assert {:ok, _} = ModelResolver.refresh_and_cache(k, ok_getter())
      assert ModelResolver.latest_model(other, :opus) == ModelResolver.fallbacks()["opus"]
    end

    test "a non-200 leaves the cache alone and reports the status" do
      k = key()
      getter = fn _url, _opts -> {:ok, %{status: 401, body: %{}}} end
      assert {:error, {:http, 401}} = ModelResolver.refresh_and_cache(k, getter)
      assert ModelResolver.latest_model(k, :opus) == ModelResolver.fallbacks()["opus"]
    end

    test "a transport failure degrades to the fallback rather than raising" do
      k = key()
      getter = fn _url, _opts -> {:error, :nxdomain} end
      assert {:error, :nxdomain} = ModelResolver.refresh_and_cache(k, getter)
      assert ModelResolver.latest_model(k, :sonnet) == ModelResolver.fallbacks()["sonnet"]
    end
  end

  describe "refresh_and_latest/2 — the 404 self-heal" do
    test "never returns the cached id, which is the one that just 404'd" do
      k = key()

      # Cache a model, then pretend it has just been retired. With fetching
      # disabled the refresh cannot succeed, and the whole point is that the
      # caller still must not get the dead id back — otherwise the client
      # compares fresh == model, sees no change, and the self-heal is a no-op.
      assert {:ok, _} = ModelResolver.refresh_and_cache(k, ok_getter())
      assert ModelResolver.latest_model(k, :opus) == "claude-opus-5"

      assert ModelResolver.refresh_and_latest(k, :opus) == ModelResolver.fallbacks()["opus"]
    end

    test "takes the newly published id when the fetch succeeds" do
      k = key()
      assert {:ok, _} = ModelResolver.refresh_and_cache(k, ok_getter())

      newer = [%{"id" => "claude-opus-6", "created_at" => "2027-01-01T00:00:00Z"} | @models]
      assert {:ok, by_tier} = ModelResolver.refresh_and_cache(k, ok_getter(newer))
      assert by_tier["opus"] == "claude-opus-6"
      assert ModelResolver.latest_model(k, :opus) == "claude-opus-6"
    end
  end
end
