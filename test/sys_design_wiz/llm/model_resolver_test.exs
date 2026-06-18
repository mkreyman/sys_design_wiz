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
      assert ModelResolver.latest_model("sk-test", "sonnet") == "claude-sonnet-4-6"
      assert ModelResolver.latest_model("sk-test", "opus") == "claude-opus-4-8"
      assert ModelResolver.latest_model("sk-test", :haiku) == "claude-haiku-4-5-20251001"
    end

    test "derives the tier when given a model id" do
      assert ModelResolver.latest_model("sk-test", "claude-opus-4-1-20250805") ==
               "claude-opus-4-8"
    end
  end

  describe "refresh_and_latest/2 (fetch disabled in test → fallback)" do
    test "falls back to the current pinned model of the tier" do
      assert ModelResolver.refresh_and_latest("sk-test", "claude-sonnet-4-20250514") ==
               "claude-sonnet-4-6"
    end
  end
end
