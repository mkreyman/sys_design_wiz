defmodule SysDesignWiz.Agent.ConversationAgent do
  @moduledoc """
  GenServer managing a single conversation session.

  Maintains message history in-memory and delegates to LLM client for responses.
  Supports tool use for enhanced agent capabilities.
  """

  use GenServer

  require Logger

  alias SysDesignWiz.Constants.Roles
  alias SysDesignWiz.Context.ContextTrimmer
  alias SysDesignWiz.Context.SimpleMemory
  alias SysDesignWiz.Tools.ToolBehaviour

  @type agent :: pid() | atom() | {:via, module(), term()}
  @type message :: %{role: String.t(), content: String.t()}
  @type state :: %{
          memory: SimpleMemory.t(),
          llm_client: module(),
          tools: [module()],
          tool_map: %{String.t() => module()}
        }

  @default_system_prompt """
  You are a helpful AI assistant. Be concise and friendly.
  """

  @max_tool_iterations 5

  # Client API

  @doc """
  Starts a new conversation agent.

  ## Options
  - `:system_prompt` - Custom system prompt (optional)
  - `:tools` - List of tool modules implementing ToolBehaviour (optional)
  - `:llm_client` - Custom LLM client module (optional, for testing)
  - `:name` - GenServer name for registration
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Send a message and get a response (without tool use).

  ## Parameters
  - `agent` - Agent PID or registered name
  - `message` - User message string

  ## Returns
  - `{:ok, response}` on success
  - `{:error, reason}` on failure
  """
  # Timeout must be longer than the LLM client's receive_timeout (60s)
  @chat_timeout 65_000

  @spec chat(agent(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def chat(agent, message) do
    GenServer.call(agent, {:chat, message}, @chat_timeout)
  end

  @doc """
  Send a message with tool use enabled.

  The agent will automatically execute tool calls from the LLM
  and return the final response.

  ## Parameters
  - `agent` - Agent PID or registered name
  - `message` - User message string

  ## Returns
  - `{:ok, response}` on success
  - `{:error, reason}` on failure
  """
  @spec chat_with_tools(agent(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def chat_with_tools(agent, message) do
    GenServer.call(agent, {:chat_with_tools, message}, 60_000)
  end

  @doc """
  Get the conversation history.
  """
  @spec get_history(agent()) :: [message()]
  def get_history(agent) do
    GenServer.call(agent, :get_history)
  end

  @doc """
  Clear the conversation history, keeping only the system prompt.
  """
  @spec clear_history(agent()) :: :ok
  def clear_history(agent) do
    GenServer.call(agent, :clear_history)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    system_prompt = Keyword.get(opts, :system_prompt, @default_system_prompt)
    client = Keyword.get(opts, :llm_client, llm_client())
    tools = Keyword.get(opts, :tools, [])

    state = %{
      memory: SimpleMemory.new(system_prompt),
      llm_client: client,
      tools: tools,
      tool_map: build_tool_map(tools)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:chat, user_message}, _from, state) do
    Logger.debug("ConversationAgent.handle_call :chat received",
      user_message_length: String.length(user_message),
      llm_client: state.llm_client
    )

    state = update_in(state.memory, &SimpleMemory.add_message(&1, Roles.user(), user_message))

    messages =
      state.memory
      |> SimpleMemory.get_messages()
      |> maybe_trim_context()

    Logger.debug("ConversationAgent calling llm_client.chat",
      message_count: length(messages),
      llm_client: state.llm_client
    )

    start_time = System.monotonic_time(:millisecond)

    result = state.llm_client.chat(messages, [])

    elapsed = System.monotonic_time(:millisecond) - start_time
    Logger.debug("ConversationAgent llm_client.chat returned", elapsed_ms: elapsed)

    case result do
      {:ok, response} ->
        state =
          update_in(state.memory, &SimpleMemory.add_message(&1, Roles.assistant(), response))

        {:reply, {:ok, response}, state}

      {:error, reason} = error ->
        Logger.error("LLM chat failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:chat_with_tools, user_message}, _from, state) do
    state = update_in(state.memory, &SimpleMemory.add_message(&1, Roles.user(), user_message))

    messages =
      state.memory
      |> SimpleMemory.get_messages()
      |> maybe_trim_context()

    openai_tools = Enum.map(state.tools, &ToolBehaviour.to_openai_tool/1)

    case run_tool_loop(state.llm_client, messages, openai_tools, state.tool_map, 0) do
      {:ok, response, updated_messages} ->
        state = save_tool_conversation(state, updated_messages)
        {:reply, {:ok, response}, state}

      {:error, reason} = error ->
        Logger.error("LLM chat with tools failed: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, SimpleMemory.get_messages(state.memory), state}
  end

  @impl true
  def handle_call(:clear_history, _from, state) do
    system_prompt = SimpleMemory.get_system_prompt(state.memory)
    state = put_in(state.memory, SimpleMemory.new(system_prompt))
    {:reply, :ok, state}
  end

  # Tool Execution Loop

  defp run_tool_loop(_client, _messages, _tools, _tool_map, iteration)
       when iteration >= @max_tool_iterations do
    {:error, :max_tool_iterations_exceeded}
  end

  defp run_tool_loop(client, messages, tools, tool_map, iteration) do
    case client.chat_with_tools(messages, tools, []) do
      {:ok, %{"content" => content, "tool_calls" => nil}} ->
        clean_content = strip_surrounding_quotes(content)
        {:ok, clean_content, messages ++ [%{role: Roles.assistant(), content: clean_content}]}

      {:ok, %{"content" => content, "tool_calls" => []}} when is_binary(content) ->
        # Empty tool_calls list with content - treat as final response
        clean_content = strip_surrounding_quotes(content)
        {:ok, clean_content, messages ++ [%{role: Roles.assistant(), content: clean_content}]}

      {:ok, %{"content" => content}} when is_binary(content) and content != "" ->
        clean_content = strip_surrounding_quotes(content)
        {:ok, clean_content, messages ++ [%{role: Roles.assistant(), content: clean_content}]}

      {:ok, %{"tool_calls" => tool_calls} = response}
      when is_list(tool_calls) and tool_calls != [] ->
        # Add assistant message with tool calls to history
        assistant_message = build_assistant_tool_message(response)
        messages = messages ++ [assistant_message]

        # Execute each tool call
        tool_results = Enum.map(tool_calls, &execute_tool_call(&1, tool_map))

        # Add tool results to messages
        messages = messages ++ tool_results

        # Continue the loop
        run_tool_loop(client, messages, tools, tool_map, iteration + 1)

      {:ok, %{"content" => nil}} ->
        {:ok, "", messages}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_assistant_tool_message(%{"tool_calls" => tool_calls} = response) do
    %{
      role: Roles.assistant(),
      content: response["content"],
      tool_calls:
        Enum.map(tool_calls, fn tc ->
          %{
            id: tc["id"],
            type: tc["type"],
            function: %{
              name: tc["function"]["name"],
              arguments: tc["function"]["arguments"]
            }
          }
        end)
    }
  end

  defp execute_tool_call(tool_call, tool_map) do
    tool_name = tool_call["function"]["name"]
    tool_id = tool_call["id"]

    case Map.get(tool_map, tool_name) do
      nil ->
        build_tool_error(tool_id, "Unknown tool: #{tool_name}")

      tool_module ->
        execute_known_tool(tool_module, tool_call, tool_id)
    end
  end

  defp execute_known_tool(tool_module, tool_call, tool_id) do
    case Jason.decode(tool_call["function"]["arguments"]) do
      {:ok, args} ->
        run_tool(tool_module, args, tool_id)

      {:error, _} ->
        build_tool_error(tool_id, "Invalid arguments JSON")
    end
  end

  defp run_tool(tool_module, args, tool_id) do
    case tool_module.execute(args) do
      {:ok, result} ->
        %{role: Roles.tool(), tool_call_id: tool_id, content: result}

      {:error, reason} ->
        build_tool_error(tool_id, inspect(reason))
    end
  end

  defp build_tool_error(tool_id, message) do
    %{
      role: Roles.tool(),
      tool_call_id: tool_id,
      content: Jason.encode!(%{error: message})
    }
  end

  defp save_tool_conversation(state, messages) do
    # Extract only user/assistant messages for clean history
    # Skip the system message (already in memory) and tool-related messages
    new_messages =
      messages
      |> Enum.drop(1)
      |> Enum.filter(fn msg ->
        msg.role in [Roles.user(), Roles.assistant()] and not Map.has_key?(msg, :tool_calls)
      end)

    Enum.reduce(new_messages, state, fn msg, acc ->
      update_in(acc.memory, &SimpleMemory.add_message(&1, msg.role, msg.content || ""))
    end)
  end

  defp build_tool_map(tools) do
    tools
    |> Enum.map(fn module -> {module.name(), module} end)
    |> Map.new()
  end

  # Private Functions

  defp maybe_trim_context(messages) do
    # Use consolidated context trimming
    ContextTrimmer.trim(messages, preserve_system_prompt: true)
  end

  defp llm_client do
    Application.get_env(:sys_design_wiz, :llm_client, SysDesignWiz.LLM.OpenAIClient)
  end

  defp strip_surrounding_quotes(nil), do: nil
  defp strip_surrounding_quotes(""), do: ""

  defp strip_surrounding_quotes(content) when is_binary(content) do
    trimmed = String.trim(content)

    # Use regex to match content wrapped in double quotes
    case Regex.run(~r/^"(.+)"$/s, trimmed) do
      [_, inner] -> String.trim(inner)
      _ -> trimmed
    end
  end
end
