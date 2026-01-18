defmodule SysDesignWiz.LLM.AnthropicClient do
  @moduledoc """
  Direct HTTP client for Anthropic's Claude API.

  Uses Req to make direct API calls to Anthropic, bypassing the CLI.
  This is the recommended approach for web applications.

  ## Configuration

  Set the API key in your environment:

      export ANTHROPIC_API_KEY="sk-ant-..."

  Or configure in your application:

      config :sys_design_wiz, :anthropic_api_key, "sk-ant-..."

  ## Usage

      {:ok, response} = AnthropicClient.chat([%{role: "user", content: "Hello"}])
  """

  @behaviour SysDesignWiz.LLM.ClientBehaviour

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @default_model "claude-sonnet-4-20250514"
  @default_max_tokens 4096

  @impl true
  def chat(messages, options \\ []) do
    with {:ok, api_key} <- validate_api_key() do
      Logger.info("AnthropicClient.chat called", api_key_present: true)
      do_chat(api_key, messages, options)
    end
  end

  @impl true
  def chat_with_tools(messages, tools, options \\ []) do
    with {:ok, api_key} <- validate_api_key() do
      do_chat_with_tools(api_key, messages, tools, options)
    end
  end

  defp validate_api_key do
    case get_api_key() do
      nil ->
        Logger.error("ANTHROPIC_API_KEY not found!")
        {:error, :missing_api_key}

      api_key ->
        {:ok, api_key}
    end
  end

  defp do_chat(api_key, messages, options) do
    Logger.info("AnthropicClient.do_chat starting", message_count: length(messages))
    system_prompt = Keyword.get(options, :system_prompt)
    model = Keyword.get(options, :model, @default_model)
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)

    body = build_request_body(messages, model, max_tokens, system_prompt)
    Logger.debug("AnthropicClient request body built", model: model, max_tokens: max_tokens)

    case make_request(api_key, body) do
      {:ok, response} ->
        extract_text_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_chat_with_tools(api_key, messages, tools, options) do
    system_prompt = Keyword.get(options, :system_prompt)
    model = Keyword.get(options, :model, @default_model)
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)

    body =
      messages
      |> build_request_body(model, max_tokens, system_prompt)
      |> Map.put("tools", format_tools(tools))

    case make_request(api_key, body) do
      {:ok, response} ->
        parse_tool_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_request_body(messages, model, max_tokens, system_prompt) do
    # Extract system prompt from messages if not provided via options
    effective_system_prompt = system_prompt || extract_system_from_messages(messages)
    api_messages = format_messages(messages)

    body = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "messages" => api_messages
    }

    if effective_system_prompt do
      Logger.debug("Using system prompt", length: String.length(effective_system_prompt))
      Map.put(body, "system", effective_system_prompt)
    else
      body
    end
  end

  defp extract_system_from_messages(messages) do
    messages
    |> Enum.find(&(get_flex(&1, :role) == "system"))
    |> case do
      nil -> nil
      msg -> get_flex(msg, :content)
    end
  end

  defp format_messages(messages) do
    messages
    |> Enum.reject(&(get_flex(&1, :role) == "system"))
    |> Enum.map(fn msg ->
      %{"role" => get_flex(msg, :role), "content" => get_flex(msg, :content)}
    end)
  end

  defp format_tools(tools) do
    Enum.map(tools, &format_single_tool/1)
  end

  defp format_single_tool(tool) do
    case get_flex(tool, :function) do
      nil -> format_anthropic_tool(tool)
      func -> format_openai_tool(func)
    end
  end

  defp format_openai_tool(func) do
    %{
      "name" => get_flex(func, :name),
      "description" => get_flex(func, :description),
      "input_schema" => get_flex(func, :parameters) || %{"type" => "object"}
    }
  end

  defp format_anthropic_tool(tool) do
    %{
      "name" => get_flex(tool, :name),
      "description" => get_flex(tool, :description),
      "input_schema" => get_flex(tool, :input_schema) || %{"type" => "object"}
    }
  end

  # Flexibly access map keys as either atoms or strings
  defp get_flex(map, key) when is_atom(key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp make_request(api_key, body) do
    Logger.info("AnthropicClient.make_request starting",
      url: @api_url,
      api_key_length: String.length(api_key),
      body_keys: Map.keys(body)
    )

    start_time = System.monotonic_time(:millisecond)

    headers = [
      {"x-api-key", api_key},
      {"anthropic-version", @api_version},
      {"content-type", "application/json"}
    ]

    Logger.debug("AnthropicClient about to call Req.post")

    result =
      Req.post(@api_url,
        headers: headers,
        json: body,
        receive_timeout: 60_000
      )

    elapsed = System.monotonic_time(:millisecond) - start_time

    Logger.info("AnthropicClient Req.post returned",
      elapsed_ms: elapsed,
      result_ok: match?({:ok, _}, result)
    )

    case result do
      {:ok, %Req.Response{status: 200, body: resp_body}} ->
        {:ok, resp_body}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        error_msg = get_in(resp_body, ["error", "message"]) || "Unknown error"
        Logger.error("Anthropic API error (#{status}): #{error_msg}")
        {:error, {:api_error, status, error_msg}}

      {:error, reason} ->
        Logger.error("Anthropic request failed: #{inspect(reason)}")
        {:error, {:request_failed, reason}}
    end
  end

  defp extract_text_response(%{"content" => content}) when is_list(content) do
    text =
      content
      |> Enum.filter(fn block -> block["type"] == "text" end)
      |> Enum.map(fn block -> block["text"] end)
      |> Enum.join("\n")

    {:ok, text}
  end

  defp extract_text_response(response) do
    Logger.warning("Unexpected response format: #{inspect(response)}")
    {:error, :unexpected_response_format}
  end

  defp parse_tool_response(%{"content" => content, "stop_reason" => stop_reason}) do
    tool_uses =
      content
      |> Enum.filter(fn block -> block["type"] == "tool_use" end)

    text_blocks =
      content
      |> Enum.filter(fn block -> block["type"] == "text" end)
      |> Enum.map(fn block -> block["text"] end)
      |> Enum.join("\n")

    if stop_reason == "tool_use" and tool_uses != [] do
      # Convert to OpenAI-compatible format for the agent
      tool_calls =
        Enum.map(tool_uses, fn tool ->
          %{
            "id" => tool["id"],
            "type" => "function",
            "function" => %{
              "name" => tool["name"],
              "arguments" => Jason.encode!(tool["input"])
            }
          }
        end)

      {:ok, %{"content" => text_blocks, "tool_calls" => tool_calls}}
    else
      {:ok, %{"content" => text_blocks, "tool_calls" => nil}}
    end
  end

  defp parse_tool_response(response) do
    extract_text_response(response)
    |> case do
      {:ok, text} -> {:ok, %{"content" => text, "tool_calls" => nil}}
      error -> error
    end
  end

  defp get_api_key do
    Application.get_env(:sys_design_wiz, :anthropic_api_key) ||
      System.get_env("ANTHROPIC_API_KEY")
  end
end
