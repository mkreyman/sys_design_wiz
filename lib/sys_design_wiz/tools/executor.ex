defmodule SysDesignWiz.Tools.Executor do
  @moduledoc """
  Executes tool calls from LLM responses.

  Handles the tool calling loop:
  1. LLM returns tool_calls in response
  2. Executor runs each tool
  3. Results are formatted as tool messages for the next LLM call
  """

  require Logger

  @doc """
  Execute tool calls from an LLM response message.

  Returns a list of tool result messages ready to append to conversation.
  """
  def execute_tool_calls(tool_calls, tools) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tool_call ->
      execute_single(tool_call, tools)
    end)
  end

  defp execute_single(
         %{"id" => id, "function" => %{"name" => name, "arguments" => args_json}},
         tools
       ) do
    tool_module = find_tool(name, tools)

    result =
      with {:ok, tool} <- tool_module,
           {:ok, args} <- Jason.decode(args_json),
           {:ok, output} <- tool.execute(args) do
        output
      else
        {:error, :tool_not_found} ->
          "Error: Unknown tool '#{name}'"

        {:error, %Jason.DecodeError{}} ->
          "Error: Invalid arguments for tool '#{name}'"

        {:error, reason} ->
          Logger.error("Tool #{name} failed: #{inspect(reason)}")
          "Error: Tool execution failed"
      end

    %{
      role: "tool",
      tool_call_id: id,
      content: result
    }
  end

  defp find_tool(name, tools) do
    case Enum.find(tools, fn tool -> tool.name() == name end) do
      nil -> {:error, :tool_not_found}
      tool -> {:ok, tool}
    end
  end

  @doc """
  Get tool definitions for all provided tool modules in OpenAI format.
  """
  def definitions(tools) when is_list(tools) do
    alias SysDesignWiz.Tools.ToolBehaviour
    Enum.map(tools, &ToolBehaviour.to_openai_tool/1)
  end

  @doc """
  Check if an LLM response contains tool calls.
  """
  def has_tool_calls?(%{"tool_calls" => [_ | _]}), do: true
  def has_tool_calls?(_), do: false

  @doc """
  Extract tool calls from an LLM response.
  """
  def get_tool_calls(%{"tool_calls" => calls}), do: calls
  def get_tool_calls(_), do: []
end
