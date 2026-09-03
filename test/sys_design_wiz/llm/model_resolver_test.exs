defmodule SysDesignWiz.LLM.ModelResolverTest do
  @moduledoc """
  The resolver runs with `enabled: false` in test (config/test.exs), so it never
  hits the network and serves its pinned per-tier fallbacks. These cover the pure
  selection logic and the cache-cold read behaviour.
  """
  use ExUnit.Case, async: true

  alias SysDesignWiz.LLM.ModelResolver

  @models [
    %{
      "id" => "claude-sonnet-4-6",
      "display_name" => "Sonnet 4.6",
      "created_at" => "2026-02-17T00:00:00Z"
    },
    %{
      "id" => "claude-sonnet-4-5-20250929",
      "display_name" => "Sonnet 4.5",
      "created_at" => "2025-09-29T00:00:00Z"
    },
    %{
      "id" => "claude-opus-4-8",
      "display_name" => "Opus 4.8",
      "created_at" => "2026-05-28T00:00:00Z"
    },
    %{
      "id" => "claude-opus-4-7",
      "display_name" => "Opus 4.7",
      "created_at" => "2026-04-14T00:00:00Z"
    },
    %{
      "id" => "claude-haiku-4-5-20251001",
      "display_name" => "Haiku 4.5",
      "created_at" => "2025-10-15T00:00:00Z"
    }
  ]

  describe "select_newest_model/2" do
    test "picks the newest of each tier by created_at" do
      assert ModelResolver.select_newest_model(@models, "sonnet") == "claude-sonnet-4-6"
      assert ModelResolver.select_newest_model(@models, "opus") == "claude-opus-4-8"
      assert ModelResolver.select_newest_model(@models, "haiku") == "claude-haiku-4-5-20251001"
    end

    test "returns nil for an empty list" do
      assert ModelResolver.select_newest_model([], "sonnet") == nil
    end
  end

  describe "tier_of/1" do
    test "derives the tier from a model id, defaulting to sonnet" do
      assert ModelResolver.tier_of("claude-sonnet-4-20250514") == "sonnet"
      assert ModelResolver.tier_of("claude-opus-4-8") == "opus"
      assert ModelResolver.tier_of("claude-haiku-4-5") == "haiku"
      assert ModelResolver.tier_of("something-else") == "sonnet"
    end
  end

  describe "latest_model/2 (cache cold → pinned fallback, no network)" do
    test "returns the per-tier fallback" do
      assert ModelResolver.latest_model("sk-test", "sonnet") == "claude-sonnet-5"
      assert ModelResolver.latest_model("sk-test", "opus") == "claude-opus-5"
      assert ModelResolver.latest_model("sk-test", :haiku) == "claude-haiku-4-5-20251001"
    end

    test "derives the tier when given a model id" do
      assert ModelResolver.latest_model("sk-test", "claude-opus-4-1-20250805") ==
               "claude-opus-5"
    end
  end

  describe "refresh_and_latest/2 (fetch disabled in test → fallback)" do
    test "falls back to the current pinned model of the tier" do
      assert ModelResolver.refresh_and_latest("sk-test", "claude-sonnet-4-20250514") ==
               "claude-sonnet-5"
    end

    # The regression. The test above passes on a COLD cache whether or not the
    # bug is present, which is how the bug shipped: refresh_and_latest/2 fell
    # back to the CACHED id when the re-fetch failed, and the only caller —
    # AnthropicClient's 404 handler — decides whether to retry by comparing the
    # returned id against the one that just 404'd. Handed that same id back, it
    # concluded there was nothing newer and re-raised, so the self-heal did
    # nothing in the one situation it exists for: a retirement that lands while
    # /v1/models is unreachable.
    test "never returns the cached id, which is the one that just 404'd" do
      key = "sk-warm-#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               ModelResolver.cache_models(key, [
                 %{"id" => "claude-sonnet-4-20250514", "created_at" => "2025-05-14T00:00:00Z"}
               ])

      assert ModelResolver.latest_model(key, "sonnet") == "claude-sonnet-4-20250514"

      refute ModelResolver.refresh_and_latest(key, "sonnet") == "claude-sonnet-4-20250514"
      assert ModelResolver.refresh_and_latest(key, "sonnet") == "claude-sonnet-5"
    end

    test "purges every tier for that key, not just the one asked for" do
      key = "sk-warm-#{System.unique_integer([:positive])}"

      assert {:ok, _} =
               ModelResolver.cache_models(key, [
                 %{"id" => "claude-sonnet-4-20250514", "created_at" => "2025-05-14T00:00:00Z"},
                 %{"id" => "claude-opus-4-20250514", "created_at" => "2025-05-14T00:00:00Z"}
               ])

      ModelResolver.refresh_and_latest(key, "sonnet")

      assert ModelResolver.latest_model(key, "opus") == "claude-opus-5"
    end
  end

  describe "pinned fallbacks" do
    test "none of them is an id Anthropic has already retired" do
      retired = [
        "claude-sonnet-4-20250514",
        "claude-opus-4-20250514",
        "claude-3-5-haiku-20241022",
        "claude-3-5-sonnet-20241022"
      ]

      for tier <- ["sonnet", "opus", "haiku"] do
        refute ModelResolver.latest_model("sk-cold-#{tier}", tier) in retired
      end
    end
  end
end
