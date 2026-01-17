defmodule SysDesignWiz.Tools.ExecutorTest do
  use ExUnit.Case, async: true

  alias SysDesignWiz.Tools.Executor
  alias SysDesignWiz.Tools.SampleTool

  describe "definitions/1" do
    test "returns definitions for all tools" do
      tools = [SampleTool]
      definitions = Executor.definitions(tools)

      assert length(definitions) == 1
      assert [%{type: "function", function: %{name: "get_current_time"}}] = definitions
    end
  end

  describe "has_tool_calls?/1" do
    test "returns true when tool_calls present" do
      message = %{"tool_calls" => [%{"id" => "1", "function" => %{}}]}
      assert Executor.has_tool_calls?(message)
    end

    test "returns false when no tool_calls" do
      assert not Executor.has_tool_calls?(%{"content" => "Hello"})
      assert not Executor.has_tool_calls?(%{"tool_calls" => []})
    end
  end

  describe "execute_tool_calls/2" do
    test "executes tool and returns result message" do
      tool_calls = [
        %{
          "id" => "call_123",
          "function" => %{
            "name" => "get_current_time",
            "arguments" => ~s({"format": "datetime"})
          }
        }
      ]

      [result] = Executor.execute_tool_calls(tool_calls, [SampleTool])

      assert result.role == "tool"
      assert result.tool_call_id == "call_123"
      assert String.contains?(result.content, "Current time")
    end

    test "handles unknown tool gracefully" do
      tool_calls = [
        %{
          "id" => "call_456",
          "function" => %{
            "name" => "unknown_tool",
            "arguments" => "{}"
          }
        }
      ]

      [result] = Executor.execute_tool_calls(tool_calls, [SampleTool])

      assert result.role == "tool"
      assert String.contains?(result.content, "Unknown tool")
    end

    test "handles invalid JSON arguments" do
      tool_calls = [
        %{
          "id" => "call_789",
          "function" => %{
            "name" => "get_current_time",
            "arguments" => "not valid json"
          }
        }
      ]

      [result] = Executor.execute_tool_calls(tool_calls, [SampleTool])

      assert result.role == "tool"
      assert String.contains?(result.content, "Invalid arguments")
    end
  end
end
