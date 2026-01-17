defmodule SysDesignWiz.LLM.OpenAIClient do
  @moduledoc """
  OpenAI API client implementation.

  Uses the ChatCompletions endpoint with GPT-4o as default model.
  Includes telemetry instrumentation for observability.
  """

  @behaviour SysDesignWiz.LLM.ClientBehaviour

  alias SysDesignWiz.LLM.CircuitBreaker
  alias SysDesignWiz.Telemetry

  require Logger

  @default_model "gpt-4o"
  @default_temperature 0.7
  @default_max_tokens 1024
  @retry_delay_ms 1000

  @impl true
  def chat(messages, options \\ []) do
    model = Keyword.get(options, :model, @default_model)
    temperature = Keyword.get(options, :temperature, @default_temperature)
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)

    metadata = %{
      model: model,
      message_count: length(messages),
      max_tokens: max_tokens
    }

    body = %{
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }

    # Use circuit breaker to protect against cascading failures
    CircuitBreaker.call(fn ->
      Telemetry.span([:sys_design_wiz, :llm], metadata, fn ->
        do_chat_request(body, model, length(messages))
      end)
    end)
  end

  @impl true
  def chat_with_tools(messages, tools, options \\ []) do
    model = Keyword.get(options, :model, @default_model)
    temperature = Keyword.get(options, :temperature, @default_temperature)
    max_tokens = Keyword.get(options, :max_tokens, @default_max_tokens)

    metadata = %{
      model: model,
      message_count: length(messages),
      tool_count: length(tools),
      max_tokens: max_tokens
    }

    body = %{
      model: model,
      messages: messages,
      tools: tools,
      temperature: temperature,
      max_tokens: max_tokens
    }

    # Use circuit breaker to protect against cascading failures
    CircuitBreaker.call(fn ->
      Telemetry.span([:sys_design_wiz, :llm], metadata, fn ->
        do_chat_with_tools_request(body, model, length(messages), length(tools))
      end)
    end)
  end

  # Private helper functions for API requests

  defp do_chat_request(body, model, message_count) do
    Logger.debug("LLM request",
      model: model,
      message_count: message_count
    )

    case make_api_request(body) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => %{"content" => content}} | _]}}} ->
        Logger.debug("LLM response received", content_length: String.length(content))
        {:ok, content}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("LLM error response", status: status)
        {:error, {status, body}}

      {:error, reason} ->
        Logger.error("LLM request failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp do_chat_with_tools_request(body, model, message_count, tool_count) do
    Logger.debug("LLM request with tools",
      model: model,
      message_count: message_count,
      tool_count: tool_count
    )

    case make_api_request(body) do
      {:ok, %{status: 200, body: %{"choices" => [%{"message" => message} | _]}}} ->
        Logger.debug("LLM response with tools received")
        {:ok, message}

      {:ok, %{status: status, body: body}} ->
        Logger.warning("LLM error response", status: status)
        {:error, {status, body}}

      {:error, reason} ->
        Logger.error("LLM request failed", reason: inspect(reason))
        {:error, reason}
    end
  end

  defp make_api_request(body) do
    Req.post(api_url(),
      json: body,
      headers: headers(),
      retry: :transient,
      retry_delay: retry_delay()
    )
  end

  defp api_url, do: "https://api.openai.com/v1/chat/completions"

  defp headers do
    [
      {"authorization", "Bearer #{api_key()}"},
      {"content-type", "application/json"}
    ]
  end

  defp api_key do
    Application.fetch_env!(:sys_design_wiz, :openai_api_key)
  end

  defp retry_delay do
    fn attempt -> attempt * @retry_delay_ms end
  end
end
