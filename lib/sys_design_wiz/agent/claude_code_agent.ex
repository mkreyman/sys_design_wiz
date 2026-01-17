defmodule SysDesignWiz.Agent.ClaudeCodeAgent do
  @moduledoc """
  AI Agent using native Claude Code SDK sessions.

  This agent leverages the Claude Code SDK's native session management for:
  - Automatic context retention across queries
  - Native Elixir streaming support
  - Fault-tolerant supervision with automatic restarts
  - Efficient multi-turn conversations

  ## Usage

  ### Basic Chat

      # Start a session
      {:ok, session} = ClaudeCodeAgent.start_link(system_prompt: "Be helpful")

      # Chat with streaming to console
      ClaudeCodeAgent.stream_chat(session, "Hello!")

      # Chat and get final response
      {:ok, response} = ClaudeCodeAgent.chat(session, "What's 2+2?")

  ### With Phoenix LiveView

      def handle_event("send", %{"message" => msg}, socket) do
        parent = self()
        Task.start(fn ->
          socket.assigns.session
          |> ClaudeCodeAgent.stream_to_pid(msg, parent)
        end)
        {:noreply, assign(socket, streaming: true)}
      end

      def handle_info({:chunk, chunk}, socket) do
        {:noreply, assign(socket, response: socket.assigns.response <> chunk)}
      end

      def handle_info(:stream_complete, socket) do
        {:noreply, assign(socket, streaming: false)}
      end

  ### Supervised Sessions

  Add to your application supervision tree:

      children = [
        {ClaudeCode.Supervisor, [
          [name: :assistant, system_prompt: "You are a helpful assistant"]
        ]}
      ]

  Then use from anywhere:

      :assistant
      |> ClaudeCodeAgent.chat("Hello!")
  """

  require Logger

  @default_system_prompt """
  You are a helpful AI assistant. Be concise and friendly.
  """

  @doc """
  Starts a new Claude Code session.

  ## Options

  - `:system_prompt` - Custom system instructions (default: generic helpful assistant)
  - `:name` - Register the session with a name for global access
  - `:resume` - Session ID to resume from a previous session
  - `:tool_callback` - Function called on tool executions for logging/auditing

  ## Examples

      {:ok, session} = ClaudeCodeAgent.start_link()
      {:ok, session} = ClaudeCodeAgent.start_link(system_prompt: "Be brief")
      {:ok, session} = ClaudeCodeAgent.start_link(name: :my_assistant)
  """
  def start_link(opts \\ []) do
    system_prompt = Keyword.get(opts, :system_prompt, @default_system_prompt)
    name = Keyword.get(opts, :name)
    resume = Keyword.get(opts, :resume)
    tool_callback = Keyword.get(opts, :tool_callback)

    claude_opts =
      [system_prompt: system_prompt]
      |> maybe_add(:name, name)
      |> maybe_add(:resume, resume)
      |> maybe_add(:tool_callback, tool_callback)

    ClaudeCode.start_link(claude_opts)
  end

  @doc """
  Send a message and get the final response (non-streaming).

  ## Parameters

  - `session` - Session PID or registered name
  - `message` - User message string

  ## Returns

  - `{:ok, response}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, response} = ClaudeCodeAgent.chat(session, "What's the weather?")
  """
  def chat(session, message) do
    response =
      session
      |> ClaudeCode.stream(message)
      |> ClaudeCode.Stream.final_text()

    {:ok, response}
  catch
    {:stream_timeout, _ref} ->
      {:error, :timeout}

    {:stream_init_error, {:cli_not_found, msg}} ->
      Logger.error("Claude CLI not found: #{msg}")
      {:error, {:cli_not_found, msg}}

    {:stream_error, reason} ->
      Logger.error("Stream error: #{inspect(reason)}")
      {:error, reason}
  end

  @doc """
  Stream a response, printing chunks to console.

  Useful for CLI applications or debugging.

  ## Examples

      ClaudeCodeAgent.stream_chat(session, "Tell me a story")
  """
  def stream_chat(session, message) do
    session
    |> ClaudeCode.stream(message)
    |> ClaudeCode.Stream.text_content()
    |> Enum.each(&IO.write/1)

    IO.puts("")
    :ok
  end

  @doc """
  Stream a response, sending chunks to a PID.

  Sends `{:chunk, text}` for each chunk and `:stream_complete` when done.
  Perfect for Phoenix LiveView integration.

  ## Parameters

  - `session` - Session PID or registered name
  - `message` - User message string
  - `target_pid` - PID to receive chunk messages

  ## Examples

      # In a LiveView
      Task.start(fn ->
        ClaudeCodeAgent.stream_to_pid(session, msg, self())
      end)
  """
  def stream_to_pid(session, message, target_pid) do
    session
    |> ClaudeCode.stream(message, include_partial_messages: true)
    |> ClaudeCode.Stream.text_deltas()
    |> Enum.each(fn chunk ->
      send(target_pid, {:chunk, chunk})
    end)

    send(target_pid, :stream_complete)
    :ok
  catch
    kind, reason ->
      send(target_pid, {:stream_error, {kind, reason}})
      {:error, {kind, reason}}
  end

  @doc """
  Get the session ID for resuming later.

  ## Examples

      session_id = ClaudeCodeAgent.get_session_id(session)
      # Later...
      {:ok, new_session} = ClaudeCodeAgent.start_link(resume: session_id)
  """
  def get_session_id(session) do
    ClaudeCode.get_session_id(session)
  end

  @doc """
  Stop a session gracefully.
  """
  def stop(session) do
    ClaudeCode.stop(session)
  end

  # Private helpers

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end
