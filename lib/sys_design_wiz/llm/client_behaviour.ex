defmodule SysDesignWiz.LLM.ClientBehaviour do
  @moduledoc """
  Behaviour for LLM clients.

  Allows swapping implementations (OpenAI, Anthropic, local) and mocking in tests.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type options :: keyword()

  @doc """
  Send a chat completion request to the LLM.

  ## Parameters
  - `messages` - List of message maps with `role` and `content`
  - `options` - Optional keyword list with model params (model, temperature, max_tokens)

  ## Returns
  - `{:ok, response_content}` on success
  - `{:error, reason}` on failure
  """
  @callback chat(messages :: [message()], options :: options()) ::
              {:ok, String.t()} | {:error, term()}

  @doc """
  Send a chat completion request with tool use enabled.

  ## Parameters
  - `messages` - List of message maps
  - `tools` - List of tool definitions
  - `options` - Optional keyword list

  ## Returns
  - `{:ok, response}` where response may include tool calls
  - `{:error, reason}` on failure
  """
  @callback chat_with_tools(messages :: [message()], tools :: [map()], options :: options()) ::
              {:ok, map()} | {:error, term()}
end
