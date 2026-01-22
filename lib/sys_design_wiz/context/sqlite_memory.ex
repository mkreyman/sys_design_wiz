defmodule SysDesignWiz.Context.SqliteMemory do
  @moduledoc """
  SQLite-backed message storage for conversation context.

  Persists messages to SQLite database, allowing conversations to survive
  application restarts and crashes. Sessions are identified by a unique
  session_id (typically a UUID from the browser).

  This module implements the same interface as SimpleMemory but uses
  the database for persistence instead of in-memory storage.
  """

  @behaviour SysDesignWiz.Context.MemoryBehaviour

  import Ecto.Query

  alias SysDesignWiz.Context.ContextTrimmer
  alias SysDesignWiz.Context.Message
  alias SysDesignWiz.Context.Session
  alias SysDesignWiz.Repo

  @type t :: %__MODULE__{
          session: Session.t(),
          system_prompt: String.t()
        }

  defstruct [:session, :system_prompt]

  @doc """
  Creates a new memory store or loads existing one for the given session ID.

  If a session with the given ID exists, loads it and its messages.
  Otherwise, creates a new session with the provided system prompt.
  """
  @impl true
  @spec new(String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def new(session_id, system_prompt) do
    case find_or_create_session(session_id, system_prompt) do
      {:ok, session} ->
        {:ok, %__MODULE__{session: session, system_prompt: session.system_prompt}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds a message to the conversation history.

  Persists the message to SQLite and updates the session's updated_at timestamp.
  Automatically trims oldest messages using ContextTrimmer.
  """
  @impl true
  @spec add_message(t(), String.t(), String.t()) :: {:ok, t()} | {:error, term()}
  def add_message(%__MODULE__{session: session} = memory, role, content) do
    Repo.transaction(fn ->
      # Insert the new message
      %Message{}
      |> Message.changeset(%{
        session_id: session.id,
        role: role,
        content: content
      })
      |> Repo.insert!()

      # Touch the session to update updated_at
      session
      |> Session.touch_changeset()
      |> Repo.update!()

      # Trim old messages if needed
      trim_messages_if_needed(session.id)

      memory
    end)
  end

  @doc """
  Gets all messages formatted for LLM API, including system prompt.

  Retrieves messages from SQLite ordered by insertion time.
  """
  @impl true
  @spec get_messages(t()) :: [%{role: String.t(), content: String.t()}]
  def get_messages(%__MODULE__{session: session, system_prompt: system_prompt}) do
    messages =
      Message
      |> where([m], m.session_id == ^session.id)
      |> order_by([m], asc: m.inserted_at)
      |> select([m], %{role: m.role, content: m.content})
      |> Repo.all()

    [%{role: "system", content: system_prompt} | messages]
  end

  @doc """
  Gets the system prompt.
  """
  @impl true
  @spec get_system_prompt(t()) :: String.t()
  def get_system_prompt(%__MODULE__{system_prompt: prompt}), do: prompt

  @doc """
  Gets the message count (excluding system prompt).
  """
  @impl true
  @spec message_count(t()) :: non_neg_integer()
  def message_count(%__MODULE__{session: session}) do
    Message
    |> where([m], m.session_id == ^session.id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Clears the conversation history, keeping only the system prompt.
  """
  @impl true
  @spec clear_history(t()) :: {:ok, t()} | {:error, term()}
  def clear_history(%__MODULE__{session: session} = memory) do
    Message
    |> where([m], m.session_id == ^session.id)
    |> Repo.delete_all()

    {:ok, memory}
  end

  # Private functions

  defp find_or_create_session(session_id, system_prompt) do
    case Repo.get_by(Session, session_id: session_id) do
      nil ->
        %Session{}
        |> Session.changeset(%{session_id: session_id, system_prompt: system_prompt})
        |> Repo.insert()

      session ->
        # Touch the session to update updated_at
        session
        |> Session.touch_changeset()
        |> Repo.update()
    end
  end

  defp trim_messages_if_needed(session_id) do
    # Get all messages for this session
    messages =
      Message
      |> where([m], m.session_id == ^session_id)
      |> order_by([m], asc: m.inserted_at)
      |> select([m], %{id: m.id, role: m.role, content: m.content})
      |> Repo.all()

    # Apply trimming logic
    trimmed = ContextTrimmer.trim_history(messages)

    # Find messages to delete (those not in trimmed list)
    trimmed_ids = MapSet.new(Enum.map(trimmed, & &1.id))

    messages_to_delete =
      messages
      |> Enum.reject(fn msg -> MapSet.member?(trimmed_ids, msg.id) end)
      |> Enum.map(& &1.id)

    if messages_to_delete != [] do
      Message
      |> where([m], m.id in ^messages_to_delete)
      |> Repo.delete_all()
    end
  end
end
