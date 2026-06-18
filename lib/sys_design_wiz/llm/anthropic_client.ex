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

  alias SysDesignWiz.LLM.ModelResolver

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  # The live default model is resolved (newest Sonnet) by ModelResolver; see
  # default_model/1. No hardcoded dated default that could be retired.
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
    model = Keyword.get(options, :model, default_model(api_key))
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)

    body = build_request_body(messages, model, max_tokens, system_prompt)
    Logger.debug("AnthropicClient request body built", model: model, max_tokens: max_tokens)

    case make_request(api_key, body, options) do
      {:ok, response} ->
        extract_text_response(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_chat_with_tools(api_key, messages, tools, options) do
    system_prompt = Keyword.get(options, :system_prompt)
    model = Keyword.get(options, :model, default_model(api_key))
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)

    body =
      messages
      |> build_request_body(model, max_tokens, system_prompt)
      |> Map.put("tools", format_tools(tools))

    case make_request(api_key, body, options) do
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

  defp make_request(api_key, body, options) do
    Logger.info("AnthropicClient.make_request starting",
      url: @api_url,
      api_key_length: String.length(api_key),
      body_keys: Map.keys(body)
    )

    start_time = System.monotonic_time(:millisecond)

    # Injection seam for tests; defaults to Req.post/2 in production.
    post_fun = Keyword.get(options, :http_post, &Req.post/2)

    result = post_with_model_heal(api_key, body, post_fun)

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

  # Builds the Req request struct for a POST to the messages endpoint.
  defp req(api_key) do
    Req.new(
      url: @api_url,
      headers: [
        {"x-api-key", api_key},
        {"anthropic-version", @api_version},
        {"content-type", "application/json"}
      ],
      receive_timeout: 60_000
    )
  end

  # The default model is resolved (newest Sonnet) per the global key by the
  # ModelResolver, so a retired dated id is never hardcoded here.
  defp default_model(api_key) do
    ModelResolver.latest_model(api_key, "sonnet")
  end

  # Sends the request; on a 404 not_found_error (the requested model was retired)
  # re-resolves the newest model of the same tier and retries ONCE with it.
  defp post_with_model_heal(api_key, body, post_fun) do
    result = post_fun.(req(api_key), json: body)

    case result do
      {:ok, %Req.Response{status: 404, body: resp_body}} ->
        heal_post_404(api_key, body, post_fun, result, resp_body)

      _ ->
        result
    end
  end

  defp heal_post_404(api_key, body, post_fun, original_result, resp_body) do
    model = body["model"]

    with true <- model_not_found?(resp_body) and is_binary(model),
         new_model when new_model != model <- ModelResolver.refresh_and_latest(api_key, model) do
      Logger.warning("[anthropic_client] model #{model} not found; retrying with #{new_model}")
      post_fun.(req(api_key), json: Map.put(body, "model", new_model))
    else
      _ -> original_result
    end
  end

  defp model_not_found?(%{"error" => %{"type" => "not_found_error"}}), do: true
  defp model_not_found?(_), do: false

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
