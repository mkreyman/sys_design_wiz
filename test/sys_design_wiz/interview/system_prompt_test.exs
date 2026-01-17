defmodule SysDesignWiz.Interview.SystemPromptTest do
  use ExUnit.Case, async: true

  alias SysDesignWiz.Interview.SystemPrompt

  describe "build/1" do
    test "returns base prompt without tech preferences" do
      prompt = SystemPrompt.build()

      assert prompt =~ "systems design interview"
      assert prompt =~ "candidate"
      assert prompt =~ "clarifying questions"
      assert prompt =~ "mermaid"
    end

    test "returns prompt with empty tech preferences" do
      prompt = SystemPrompt.build(tech_preferences: %{})

      assert prompt =~ "systems design interview"
      refute prompt =~ "Technology preferences"
    end

    test "includes database preference when specified" do
      prompt = SystemPrompt.build(tech_preferences: %{database: "PostgreSQL"})

      assert prompt =~ "Technology Preferences"
      assert prompt =~ "- Database: PostgreSQL"
    end

    test "includes messaging preference when specified" do
      prompt = SystemPrompt.build(tech_preferences: %{messaging: "Kafka"})

      assert prompt =~ "Technology Preferences"
      assert prompt =~ "- Messaging: Kafka"
    end

    test "includes cache preference when specified" do
      prompt = SystemPrompt.build(tech_preferences: %{cache: "Redis"})

      assert prompt =~ "Technology Preferences"
      assert prompt =~ "- Cache: Redis"
    end

    test "includes api_style preference when specified" do
      prompt = SystemPrompt.build(tech_preferences: %{api_style: "GraphQL"})

      assert prompt =~ "Technology Preferences"
      assert prompt =~ "- Api Style: GraphQL"
    end

    test "includes multiple preferences" do
      prompt =
        SystemPrompt.build(
          tech_preferences: %{
            database: "MySQL",
            cache: "Memcached",
            messaging: "RabbitMQ"
          }
        )

      assert prompt =~ "- Database: MySQL"
      assert prompt =~ "- Cache: Memcached"
      assert prompt =~ "- Messaging: RabbitMQ"
    end

    test "ignores nil preferences" do
      prompt = SystemPrompt.build(tech_preferences: %{database: nil, cache: "Redis"})

      assert prompt =~ "- Cache: Redis"
      refute prompt =~ "- Database:"
    end

    test "ignores empty string preferences" do
      prompt = SystemPrompt.build(tech_preferences: %{database: "", cache: "Redis"})

      assert prompt =~ "- Cache: Redis"
      refute prompt =~ "- Database:"
    end

    test "prompt mentions Mermaid diagrams" do
      prompt = SystemPrompt.build()

      assert prompt =~ "Mermaid"
      assert prompt =~ "flowchart"
    end

    test "prompt describes candidate behavior" do
      prompt = SystemPrompt.build()

      # Should describe asking questions
      assert prompt =~ "question"
      # Should describe casual tone
      assert prompt =~ ~r/casual|conversational|natural/i
    end
  end
end
