defmodule SysDesignWiz.Agent.ConversationAgentTest do
  use ExUnit.Case, async: false

  import Mox

  alias Ecto.Adapters.SQL.Sandbox
  alias SysDesignWiz.Agent.ConversationAgent
  alias SysDesignWiz.LLM.MockClient
  alias SysDesignWiz.Repo

  setup do
    :ok = Sandbox.checkout(Repo)
    # Allow spawned processes to use the connection
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  setup :verify_on_exit!

  # Generate a unique session ID for each test
  defp unique_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  # Helper to start agent and allow mock access
  defp start_agent(opts \\ []) do
    opts = Keyword.put_new(opts, :session_id, unique_session_id())
    {:ok, agent} = ConversationAgent.start_link(opts)
    Mox.allow(MockClient, self(), agent)
    {:ok, agent}
  end

  describe "start_link/1" do
    test "starts a conversation agent" do
      assert {:ok, pid} = ConversationAgent.start_link(session_id: unique_session_id())
      assert Process.alive?(pid)
    end

    test "accepts custom system prompt" do
      expect(MockClient, :chat, fn messages, _opts ->
        assert Enum.any?(messages, fn m ->
                 m.role == "system" && String.contains?(m.content, "custom")
               end)

        {:ok, "response"}
      end)

      {:ok, agent} = start_agent(system_prompt: "You are a custom assistant.")
      ConversationAgent.chat(agent, "test")
    end
  end

  describe "chat/2" do
    test "sends message and returns response" do
      expect(MockClient, :chat, fn messages, _opts ->
        assert Enum.any?(messages, fn m -> m.role == "user" && m.content == "Hello" end)
        {:ok, "Hi there!"}
      end)

      {:ok, agent} = start_agent()
      assert {:ok, "Hi there!"} = ConversationAgent.chat(agent, "Hello")
    end

    test "maintains conversation history" do
      expect(MockClient, :chat, fn _messages, _opts -> {:ok, "First response"} end)

      expect(MockClient, :chat, fn messages, _opts ->
        # Should include previous exchange
        assert length(messages) >= 3
        {:ok, "Second response"}
      end)

      {:ok, agent} = start_agent()
      ConversationAgent.chat(agent, "First message")
      ConversationAgent.chat(agent, "Second message")
    end

    test "returns error on LLM failure" do
      expect(MockClient, :chat, fn _messages, _opts -> {:error, :timeout} end)

      {:ok, agent} = start_agent()
      assert {:error, :timeout} = ConversationAgent.chat(agent, "Hello")
    end
  end

  describe "get_history/1" do
    test "returns empty history for new agent" do
      {:ok, agent} = ConversationAgent.start_link(session_id: unique_session_id())
      history = ConversationAgent.get_history(agent)

      # Should only have system message
      assert length(history) == 1
      assert hd(history).role == "system"
    end

    test "returns messages after conversation" do
      expect(MockClient, :chat, fn _messages, _opts -> {:ok, "Response"} end)

      {:ok, agent} = start_agent()
      ConversationAgent.chat(agent, "Hello")

      history = ConversationAgent.get_history(agent)
      assert length(history) == 3
    end
  end

  describe "clear_history/1" do
    test "resets to only system prompt" do
      expect(MockClient, :chat, fn _messages, _opts -> {:ok, "Response"} end)

      {:ok, agent} = start_agent()
      ConversationAgent.chat(agent, "Hello")
      ConversationAgent.clear_history(agent)

      history = ConversationAgent.get_history(agent)
      assert length(history) == 1
      assert hd(history).role == "system"
    end
  end

  describe "chat_with_tools/2" do
    test "returns text response when no tools are called" do
      expect(MockClient, :chat_with_tools, fn _messages, _tools, _opts ->
        {:ok, %{"content" => "Here's your answer", "tool_calls" => nil}}
      end)

      {:ok, agent} = start_agent(tools: [])
      assert {:ok, "Here's your answer"} = ConversationAgent.chat_with_tools(agent, "Question")
    end

    test "returns text response with empty tool_calls list" do
      expect(MockClient, :chat_with_tools, fn _messages, _tools, _opts ->
        {:ok, %{"content" => "Direct answer", "tool_calls" => []}}
      end)

      {:ok, agent} = start_agent(tools: [])
      assert {:ok, "Direct answer"} = ConversationAgent.chat_with_tools(agent, "Question")
    end

    test "returns error on LLM failure" do
      expect(MockClient, :chat_with_tools, fn _messages, _tools, _opts ->
        {:error, :api_error}
      end)

      {:ok, agent} = start_agent(tools: [])
      assert {:error, :api_error} = ConversationAgent.chat_with_tools(agent, "Question")
    end

    test "strips surrounding quotes from response" do
      expect(MockClient, :chat_with_tools, fn _messages, _tools, _opts ->
        {:ok, %{"content" => "\"Quoted response\"", "tool_calls" => nil}}
      end)

      {:ok, agent} = start_agent(tools: [])
      assert {:ok, "Quoted response"} = ConversationAgent.chat_with_tools(agent, "Question")
    end

    test "handles nil content gracefully" do
      expect(MockClient, :chat_with_tools, fn _messages, _tools, _opts ->
        {:ok, %{"content" => nil}}
      end)

      {:ok, agent} = start_agent(tools: [])
      assert {:ok, ""} = ConversationAgent.chat_with_tools(agent, "Question")
    end
  end

  describe "context trimming" do
    test "trims messages when history gets long" do
      # Set up expectations for many messages
      for _ <- 1..25 do
        expect(MockClient, :chat, fn _messages, _opts -> {:ok, "Response"} end)
      end

      {:ok, agent} = start_agent()

      # Send many messages
      for i <- 1..25 do
        ConversationAgent.chat(agent, "Message #{i}")
      end

      # History should be trimmed (not include all 51 messages: 1 system + 50 user/assistant)
      history = ConversationAgent.get_history(agent)
      # Should have trimmed to around 20 messages
      assert length(history) <= 25
    end
  end

  describe "role constants" do
    test "uses correct role strings in history" do
      expect(MockClient, :chat, fn _messages, _opts -> {:ok, "Response"} end)

      {:ok, agent} = start_agent()
      ConversationAgent.chat(agent, "Hello")

      history = ConversationAgent.get_history(agent)
      roles = Enum.map(history, & &1.role)

      assert "system" in roles
      assert "user" in roles
      assert "assistant" in roles
    end
  end
end
