defmodule SysDesignWiz.LLM.ClaudeCodeClientTest do
  use ExUnit.Case, async: true

  alias SysDesignWiz.LLM.ClaudeCodeClient

  describe "chat/2" do
    test "sends messages and returns response" do
      # Stub the ClaudeCode module for testing
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [ClaudeCode.Test.text("Hello! I'm Claude.")]
      end)

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, "Hello! I'm Claude."} = ClaudeCodeClient.chat(messages)
    end

    test "converts message history to prompt" do
      ClaudeCode.Test.stub(ClaudeCode, fn query, _opts ->
        # Verify the prompt contains the conversation
        assert String.contains?(query, "User: First message")
        assert String.contains?(query, "Assistant: First response")
        assert String.contains?(query, "User: Second message")
        [ClaudeCode.Test.text("Got it!")]
      end)

      messages = [
        %{role: "user", content: "First message"},
        %{role: "assistant", content: "First response"},
        %{role: "user", content: "Second message"}
      ]

      assert {:ok, "Got it!"} = ClaudeCodeClient.chat(messages)
    end

    test "handles system prompts via options" do
      # System prompt is passed to session start, not visible in stub opts
      # Just verify the call succeeds with a system prompt option
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [ClaudeCode.Test.text("OK")]
      end)

      messages = [%{role: "user", content: "Hello"}]
      assert {:ok, "OK"} = ClaudeCodeClient.chat(messages, system_prompt: "Be concise")
    end

    test "returns error on failure" do
      # Stub must return a list of events - use result with is_error: true
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        [ClaudeCode.Test.result("Request failed", is_error: true)]
      end)

      messages = [%{role: "user", content: "Hello"}]
      assert {:error, {:claude_error, "Request failed"}} = ClaudeCodeClient.chat(messages)
    end
  end

  describe "chat_with_tools/3" do
    test "returns text response when no tool call needed" do
      # Tool descriptions are included in system_prompt (passed to session start)
      # We just verify the response is handled correctly
      ClaudeCode.Test.stub(ClaudeCode, fn query, _opts ->
        # Verify the query contains the user message
        assert String.contains?(query, "What's the weather?")
        [ClaudeCode.Test.text("The weather is sunny!")]
      end)

      messages = [%{role: "user", content: "What's the weather?"}]

      tools = [
        %{
          "type" => "function",
          "function" => %{
            "name" => "get_weather",
            "description" => "Get the weather for a location",
            "parameters" => %{"type" => "object", "properties" => %{}}
          }
        }
      ]

      assert {:ok, %{"content" => "The weather is sunny!", "tool_calls" => nil}} =
               ClaudeCodeClient.chat_with_tools(messages, tools)
    end

    test "parses tool call response" do
      ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
        # Simulate Claude returning a tool call
        tool_response =
          Jason.encode!(%{
            "tool_call" => %{
              "name" => "get_weather",
              "arguments" => %{"location" => "San Francisco"}
            }
          })

        [ClaudeCode.Test.text(tool_response)]
      end)

      messages = [%{role: "user", content: "What's the weather in SF?"}]

      tools = [
        %{
          name: "get_weather",
          description: "Get weather",
          input_schema: %{}
        }
      ]

      assert {:ok, response} = ClaudeCodeClient.chat_with_tools(messages, tools)
      assert response["tool_calls"] != nil
      assert [tool_call] = response["tool_calls"]
      assert tool_call["function"]["name"] == "get_weather"
    end
  end
end
