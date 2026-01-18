defmodule SysDesignWiz.LLM.ClaudeCodeClient do
  @moduledoc """
  Claude Code SDK client implementation.

  Wraps the Claude Code SDK to provide a simple chat interface while leveraging
  Claude's native streaming and session management capabilities.

  ## Features

  - Automatic context retention via sessions
  - Native Elixir streaming support
  - Production-ready with fault-tolerant supervision
  - Built-in retry logic

  ## Configuration

  The Claude Code SDK requires either:
  - A Claude subscription (authenticate via `claude` CLI then `/login`)
  - An API key via `ANTHROPIC_API_KEY` environment variable

  ## Usage

      # Simple one-off query
      {:ok, response} = ClaudeCodeClient.chat([%{role: "user", content: "Hello"}])

      # With options
      {:ok, response} = ClaudeCodeClient.chat(messages, system_prompt: "Be concise")
  """

  @behaviour SysDesignWiz.LLM.ClientBehaviour

  require Logger

  @impl true
  def chat(messages, options \\ []) do
    prompt = messages_to_prompt(messages)
    system_prompt = Keyword.get(options, :system_prompt)

    opts =
      if system_prompt do
        [system_prompt: system_prompt]
      else
        []
      end

    case ClaudeCode.query(prompt, opts) do
      {:ok, result} ->
        {:ok, result.result}

      {:error, %{is_error: true, result: msg}} ->
        Logger.error("Claude Code error: #{msg}")
        {:error, {:claude_error, msg}}

      {:error, reason} ->
        Logger.error("Claude Code request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def chat_with_tools(messages, tools, options \\ []) do
    # Claude Code SDK handles tools via MCP integration
    # For now, we'll include tool definitions in the prompt
    prompt = messages_to_prompt(messages)
    tools_description = format_tools_for_prompt(tools)
    system_prompt = Keyword.get(options, :system_prompt, "")

    full_system = """
    #{system_prompt}

    You have access to the following tools:
    #{tools_description}

    When you need to use a tool, respond with a JSON object in this exact format:
    {"tool_call": {"name": "tool_name", "arguments": {...}}}

    When you have a final answer, respond normally without the tool_call wrapper.
    """

    case ClaudeCode.query(prompt, system_prompt: full_system) do
      {:ok, result} ->
        parse_tool_response(result.result)

      {:error, %{is_error: true, result: msg}} ->
        Logger.error("Claude Code error: #{msg}")
        {:error, {:claude_error, msg}}

      {:error, reason} ->
        Logger.error("Claude Code request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Convert message list to a single prompt string
  # Claude Code SDK expects a prompt, not a message array
  defp messages_to_prompt(messages) do
    messages
    |> Enum.reject(fn m -> m.role == "system" end)
    |> Enum.map(fn
      %{role: "user", content: content} ->
        "User: #{content}"

      %{role: "assistant", content: content} ->
        "Assistant: #{content}"

      %{role: "tool", content: content, tool_call_id: id} ->
        "Tool Result (#{id}): #{content}"

      %{role: role, content: content} ->
        "#{String.capitalize(role)}: #{content}"
    end)
    |> Enum.join("\n\n")
  end

  defp format_tools_for_prompt(tools) do
    tools
    |> Enum.map(fn tool ->
      # Handle both OpenAI-style and raw tool definitions
      name = get_in(tool, ["function", "name"]) || tool[:name] || tool["name"]

      desc =
        get_in(tool, ["function", "description"]) || tool[:description] || tool["description"]

      params =
        get_in(tool, ["function", "parameters"]) ||
          tool[:input_schema] ||
          tool["input_schema"] ||
          %{}

      """
      - #{name}: #{desc}
        Parameters: #{Jason.encode!(params)}
      """
    end)
    |> Enum.join("\n")
  end

  defp parse_tool_response(response) when is_binary(response) do
    case Jason.decode(response) do
      {:ok, %{"tool_call" => %{"name" => name, "arguments" => args}}} ->
        {:ok, build_tool_call_response(name, args)}

      {:ok, %{"tool_calls" => tool_calls}} when is_list(tool_calls) ->
        # Handles pre-formatted OpenAI-compatible responses (future-proofing)
        {:ok, %{"content" => nil, "tool_calls" => tool_calls}}

      _ ->
        {:ok, %{"content" => response, "tool_calls" => nil}}
    end
  end

  defp build_tool_call_response(name, args) do
    %{
      "content" => nil,
      "tool_calls" => [
        %{
          "id" => generate_tool_call_id(),
          "type" => "function",
          "function" => %{
            "name" => name,
            "arguments" => Jason.encode!(args)
          }
        }
      ]
    }
  end

  defp generate_tool_call_id do
    "call_" <> (:crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower))
  end
end
