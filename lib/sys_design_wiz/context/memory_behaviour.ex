defmodule SysDesignWiz.Context.MemoryBehaviour do
  @moduledoc """
  Behaviour defining the contract for conversation memory implementations.

  Implementations must support:
  - Creating new memory stores with a system prompt
  - Adding messages to the conversation
  - Retrieving formatted messages for LLM APIs
  - Getting message counts
  - Clearing history
  """

  @type session_id :: String.t()
  @type message :: %{role: String.t(), content: String.t()}
  @type memory :: term()

  @doc """
  Creates a new memory store or loads existing one for the given session ID.

  Returns the memory state that should be passed to other functions.
  """
  @callback new(session_id(), String.t()) :: {:ok, memory()} | {:error, term()}

  @doc """
  Adds a message to the conversation history.

  Returns updated memory state.
  """
  @callback add_message(memory(), String.t(), String.t()) :: {:ok, memory()} | {:error, term()}

  @doc """
  Gets all messages formatted for LLM API, including system prompt.

  Returns list of messages with role and content keys.
  """
  @callback get_messages(memory()) :: [message()]

  @doc """
  Gets the system prompt.
  """
  @callback get_system_prompt(memory()) :: String.t()

  @doc """
  Gets the message count (excluding system prompt).
  """
  @callback message_count(memory()) :: non_neg_integer()

  @doc """
  Clears the conversation history, keeping only the system prompt.
  """
  @callback clear_history(memory()) :: {:ok, memory()} | {:error, term()}
end
