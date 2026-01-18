defmodule SysDesignWizWeb.ChatLive do
  @moduledoc """
  LiveView for the systems design interview interface.

  Two-panel layout:
  - Left: Chat with AI candidate (text/voice input)
  - Right: Auto-updating Mermaid architecture diagram

  Features:
  - Supervised agent lifecycle
  - Candidate persona with clarifying questions
  - Real-time diagram extraction and rendering
  - Voice input via Web Speech API
  - Technology preferences
  - Mobile-responsive design
  """

  use SysDesignWizWeb, :live_view

  alias SysDesignWiz.Agent.ConversationAgent
  alias SysDesignWiz.Diagram.{MermaidParser, MermaidSanitizer}
  alias SysDesignWiz.Interview.SystemPrompt

  require Logger

  # Type specs for message roles
  @type role :: String.t()
  @type message :: %{role: role(), content: String.t(), timestamp: DateTime.t()}

  @impl true
  @spec mount(map(), map(), Phoenix.LiveView.Socket.t()) :: {:ok, Phoenix.LiveView.Socket.t()}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:session_id, nil)
      |> assign(:agent, nil)
      |> assign(:agent_ref, nil)
      |> assign(:messages, [])
      |> assign(:input_value, "")
      |> assign(:loading, false)
      |> assign(:diagram_code, nil)
      |> assign(:diagram_loading, false)
      |> assign(:show_raw_diagram, false)
      |> assign(:voice_active, false)
      |> assign(:voice_processing, false)
      |> assign(:voice_supported, true)
      |> assign(:voice_transcript, "")
      |> assign(:voice_editing, false)
      |> assign(:tech_preferences, default_tech_preferences())
      |> assign(:show_preferences, false)
      |> assign(:preferences_expanded, %{})

    if connected?(socket) do
      session_id = generate_session_id()

      case start_supervised_agent(session_id, socket.assigns.tech_preferences) do
        {:ok, agent} ->
          ref = Process.monitor(agent)

          Logger.info("Started agent for session",
            session_id: session_id,
            agent_pid: inspect(agent)
          )

          socket =
            socket
            |> assign(:session_id, session_id)
            |> assign(:agent, agent)
            |> assign(:agent_ref, ref)

          {:ok, socket}

        {:error, reason} ->
          Logger.error("Failed to start agent",
            session_id: session_id,
            error: inspect(reason)
          )

          {:ok,
           assign(socket, :messages, [
             create_message("system", "Failed to start agent: #{inspect(reason)}")
           ])}
      end
    else
      {:ok, socket}
    end
  end

  @impl true
  @spec terminate(term(), Phoenix.LiveView.Socket.t()) :: :ok
  def terminate(_reason, socket) do
    if agent = socket.assigns[:agent] do
      Logger.info("Terminating agent",
        session_id: socket.assigns[:session_id],
        agent_pid: inspect(agent)
      )

      DynamicSupervisor.terminate_child(SysDesignWiz.AgentSupervisor, agent)
    end

    :ok
  end

  # Message handling

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) when message != "" do
    send_user_message(socket, message)
  end

  def handle_event("send_message", _params, socket), do: {:noreply, socket}

  def handle_event("update_input", %{"message" => value}, socket) do
    {:noreply, assign(socket, :input_value, value)}
  end

  def handle_event("clear_history", _params, socket) do
    if socket.assigns.agent do
      ConversationAgent.clear_history(socket.assigns.agent)
    end

    {:noreply, assign(socket, messages: [], diagram_code: nil)}
  end

  def handle_event("send_suggestion", %{"text" => text}, socket) do
    send_user_message(socket, text)
  end

  # Diagram events

  def handle_event("toggle_raw_diagram", _params, socket) do
    {:noreply, assign(socket, :show_raw_diagram, !socket.assigns.show_raw_diagram)}
  end

  # Voice events

  def handle_event("toggle_voice", _params, socket) do
    {:noreply, push_event(socket, "toggle_voice", %{})}
  end

  def handle_event("voice_started", _params, socket) do
    {:noreply, assign(socket, voice_active: true, voice_transcript: "", voice_editing: false)}
  end

  def handle_event("voice_stopped", %{"transcript" => transcript}, socket) do
    socket = assign(socket, voice_active: false, voice_processing: true)

    # If transcript is non-empty, enter edit mode instead of auto-sending
    if transcript != "" do
      {:noreply,
       socket
       |> assign(:voice_processing, false)
       |> assign(:voice_editing, true)
       |> assign(:input_value, transcript)
       |> assign(:voice_transcript, transcript)}
    else
      {:noreply, assign(socket, voice_processing: false)}
    end
  end

  def handle_event("voice_transcript", %{"final" => final, "interim" => interim}, socket) do
    transcript = if interim != "", do: final <> interim, else: final
    {:noreply, assign(socket, :voice_transcript, transcript)}
  end

  def handle_event("voice_auto_send", %{"transcript" => transcript}, socket) do
    # Auto-send triggered by pause detection in JS
    socket =
      socket
      |> assign(:voice_active, false)
      |> assign(:voice_processing, false)

    if transcript != "" do
      send_user_message(socket, transcript)
    else
      {:noreply, socket}
    end
  end

  def handle_event("voice_error", %{"error" => error}, socket) do
    Logger.warning("Voice input error", error: error, session_id: socket.assigns.session_id)

    {:noreply,
     socket
     |> assign(:voice_active, false)
     |> assign(:voice_processing, false)
     |> put_flash(:error, "Voice error: #{error}")}
  end

  def handle_event("voice_unsupported", _params, socket) do
    {:noreply, assign(socket, :voice_supported, false)}
  end

  def handle_event("cancel_voice_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:voice_editing, false)
     |> assign(:input_value, "")
     |> assign(:voice_transcript, "")}
  end

  # Preferences events

  def handle_event("toggle_preferences", _params, socket) do
    {:noreply, assign(socket, :show_preferences, !socket.assigns.show_preferences)}
  end

  def handle_event("toggle_preference_section", %{"section" => section}, socket) do
    expanded = socket.assigns.preferences_expanded
    new_expanded = Map.update(expanded, section, true, &(!&1))
    {:noreply, assign(socket, :preferences_expanded, new_expanded)}
  end

  def handle_event("update_preference", %{"category" => category, "tech" => tech}, socket) do
    prefs = socket.assigns.tech_preferences
    current = Map.get(prefs, category, [])

    updated =
      if tech in current do
        List.delete(current, tech)
      else
        [tech | current]
      end

    new_prefs = Map.put(prefs, category, updated)
    {:noreply, assign(socket, :tech_preferences, new_prefs)}
  end

  def handle_event("reset_preferences", _params, socket) do
    {:noreply, assign(socket, :tech_preferences, default_tech_preferences())}
  end

  # Info handlers

  @impl true
  def handle_info({:chat, message}, socket) do
    Logger.debug("ChatLive handle_info :chat received",
      message_length: String.length(message),
      agent: inspect(socket.assigns.agent)
    )

    socket = assign(socket, :diagram_loading, true)

    Logger.debug("ChatLive calling ConversationAgent.chat")
    start_time = System.monotonic_time(:millisecond)

    result = ConversationAgent.chat(socket.assigns.agent, message)

    elapsed = System.monotonic_time(:millisecond) - start_time
    Logger.debug("ChatLive ConversationAgent.chat returned", elapsed_ms: elapsed)

    case result do
      {:ok, response} ->
        Logger.info("Received chat response",
          session_id: socket.assigns.session_id,
          response_length: String.length(response)
        )

        # Extract diagram from response
        diagram_code =
          case MermaidParser.extract(response) do
            {:ok, code} ->
              code
              |> MermaidSanitizer.sanitize()

            :no_diagram ->
              socket.assigns.diagram_code
          end

        # Strip diagram from displayed message for cleaner chat
        display_response = MermaidParser.strip_diagrams(response)

        assistant_message = create_message("assistant", display_response)

        socket =
          socket
          |> update(:messages, &(&1 ++ [assistant_message]))
          |> assign(:loading, false)
          |> assign(:diagram_loading, false)
          |> assign(:diagram_code, diagram_code)

        {:noreply, socket}

      {:error, reason} ->
        Logger.error("Chat error",
          session_id: socket.assigns.session_id,
          error: inspect(reason)
        )

        error_message = create_message("system", "Sorry, an error occurred. Please try again.")

        socket =
          socket
          |> update(:messages, &(&1 ++ [error_message]))
          |> assign(:loading, false)
          |> assign(:diagram_loading, false)

        {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket)
      when ref == socket.assigns.agent_ref do
    Logger.warning("Agent crashed",
      session_id: socket.assigns.session_id,
      reason: inspect(reason)
    )

    error_message =
      create_message(
        "system",
        "Agent disconnected (#{inspect(reason)}). Attempting to restart..."
      )

    socket = update(socket, :messages, &(&1 ++ [error_message]))

    case start_supervised_agent(socket.assigns.session_id, socket.assigns.tech_preferences) do
      {:ok, new_agent} ->
        new_ref = Process.monitor(new_agent)

        Logger.info("Agent restarted",
          session_id: socket.assigns.session_id,
          agent_pid: inspect(new_agent)
        )

        recovery_message = create_message("system", "Agent reconnected. You may continue.")

        socket =
          socket
          |> assign(:agent, new_agent)
          |> assign(:agent_ref, new_ref)
          |> assign(:loading, false)
          |> update(:messages, &(&1 ++ [recovery_message]))

        {:noreply, socket}

      {:error, _} ->
        failure_message =
          create_message("system", "Failed to restart agent. Please refresh the page.")

        socket =
          socket
          |> assign(:agent, nil)
          |> assign(:loading, false)
          |> update(:messages, &(&1 ++ [failure_message]))

        {:noreply, socket}
    end
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    {:noreply, socket}
  end

  # Render

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900">
      <div class="flex flex-col h-screen">
        <%!-- Header --%>
        <header class="flex items-center justify-between px-4 md:px-6 py-3 md:py-4 border-b border-slate-700/50 bg-slate-900/50 backdrop-blur">
          <div class="flex items-center gap-3">
            <div class="w-8 h-8 md:w-10 md:h-10 rounded-xl bg-gradient-to-br from-emerald-500 to-teal-600 flex items-center justify-center shadow-lg">
              <svg
                class="w-5 h-5 md:w-6 md:h-6 text-white"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
                />
              </svg>
            </div>
            <div>
              <h1 class="text-lg md:text-xl font-semibold text-white">SysDesignWiz</h1>
              <p class="text-xs md:text-sm text-slate-400 hidden sm:block">
                Systems Design Interview Practice
              </p>
            </div>
          </div>
          <div class="flex items-center gap-2">
            <%!-- Session Indicator --%>
            <div
              :if={@session_id}
              class="hidden md:flex items-center gap-1.5 px-2 py-1 bg-emerald-500/10 border border-emerald-500/30 rounded-lg"
            >
              <div class="w-2 h-2 bg-emerald-400 rounded-full animate-pulse"></div>
              <span class="text-xs text-emerald-400">Session Active</span>
            </div>
            <button
              phx-click="toggle_preferences"
              class={[
                "px-2 md:px-3 py-1.5 text-sm rounded-lg transition-colors",
                if(@show_preferences,
                  do: "bg-emerald-500/20 text-emerald-400",
                  else: "text-slate-400 hover:text-white hover:bg-white/10"
                )
              ]}
            >
              <svg
                class="w-4 h-4 inline mr-0 md:mr-1"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
                />
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                />
              </svg>
              <span class="hidden md:inline">Preferences</span>
            </button>
            <button
              :if={@messages != []}
              phx-click="clear_history"
              class="px-2 md:px-3 py-1.5 text-sm text-slate-400 hover:text-white hover:bg-white/10 rounded-lg transition-colors"
            >
              <span class="hidden md:inline">Clear chat</span>
              <svg class="w-4 h-4 md:hidden" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                />
              </svg>
            </button>
          </div>
        </header>

        <%!-- Tech Preferences Panel (Mobile Accordion / Desktop Inline) --%>
        <div
          :if={@show_preferences}
          class="px-4 md:px-6 py-3 border-b border-slate-700/50 bg-slate-800/50"
        >
          <%!-- Desktop: Inline layout --%>
          <div class="hidden md:flex flex-wrap gap-6">
            <.preference_group
              label="Databases"
              category="databases"
              options={["PostgreSQL", "MySQL", "MongoDB", "Redis", "DynamoDB", "Cassandra"]}
              selected={@tech_preferences["databases"] || []}
            />
            <.preference_group
              label="Caching"
              category="caching"
              options={["Redis", "Memcached", "CDN", "Varnish"]}
              selected={@tech_preferences["caching"] || []}
            />
            <.preference_group
              label="Message Queues"
              category="queues"
              options={["Kafka", "RabbitMQ", "SQS", "Redis Pub/Sub"]}
              selected={@tech_preferences["queues"] || []}
            />
            <.preference_group
              label="Cloud"
              category="cloud"
              options={["AWS", "GCP", "Azure", "Self-hosted"]}
              selected={@tech_preferences["cloud"] || []}
            />
          </div>
          <%!-- Mobile: Accordion layout --%>
          <div class="md:hidden space-y-2">
            <.preference_accordion
              label="Databases"
              category="databases"
              options={["PostgreSQL", "MySQL", "MongoDB", "Redis", "DynamoDB", "Cassandra"]}
              selected={@tech_preferences["databases"] || []}
              expanded={@preferences_expanded["databases"] || false}
            />
            <.preference_accordion
              label="Caching"
              category="caching"
              options={["Redis", "Memcached", "CDN", "Varnish"]}
              selected={@tech_preferences["caching"] || []}
              expanded={@preferences_expanded["caching"] || false}
            />
            <.preference_accordion
              label="Message Queues"
              category="queues"
              options={["Kafka", "RabbitMQ", "SQS", "Redis Pub/Sub"]}
              selected={@tech_preferences["queues"] || []}
              expanded={@preferences_expanded["queues"] || false}
            />
            <.preference_accordion
              label="Cloud"
              category="cloud"
              options={["AWS", "GCP", "Azure", "Self-hosted"]}
              selected={@tech_preferences["cloud"] || []}
              expanded={@preferences_expanded["cloud"] || false}
            />
          </div>
          <button
            phx-click="reset_preferences"
            class="mt-2 text-xs text-slate-500 hover:text-slate-300"
          >
            Reset to defaults
          </button>
        </div>

        <%!-- Main Content: Two Panels (stacked on mobile, side-by-side on desktop) --%>
        <div class="flex-1 flex flex-col md:flex-row overflow-hidden">
          <%!-- Left Panel: Chat --%>
          <div class="flex-1 md:w-1/2 flex flex-col border-b md:border-b-0 md:border-r border-slate-700/50 min-h-0">
            <%!-- Messages --%>
            <div
              class="flex-1 overflow-y-auto p-4 space-y-4"
              id="messages"
              phx-hook="ScrollToBottom"
            >
              <%!-- Empty State --%>
              <%= if @messages == [] and not @loading do %>
                <div class="flex flex-col items-center justify-center h-full text-center px-4">
                  <div class="w-16 h-16 rounded-2xl bg-gradient-to-br from-emerald-500/20 to-teal-500/20 flex items-center justify-center mb-6 border border-emerald-500/30">
                    <svg
                      class="w-8 h-8 text-emerald-400"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="1.5"
                        d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                      />
                    </svg>
                  </div>
                  <h2 class="text-xl font-medium text-white mb-2">
                    Ready for your interview
                  </h2>
                  <p class="text-slate-400 mb-6 max-w-sm">
                    I'm your candidate. Give me a systems design problem and I'll walk you through my approach.
                  </p>
                  <div class="flex flex-wrap justify-center gap-2">
                    <.suggestion_chip text="Design a URL shortener" />
                    <.suggestion_chip text="Design Twitter's feed" />
                    <.suggestion_chip text="Design a rate limiter" />
                  </div>
                </div>
              <% end %>

              <%!-- Messages --%>
              <%= for message <- @messages do %>
                <.message_bubble message={message} />
              <% end %>

              <%!-- Typing indicator --%>
              <.typing_indicator :if={@loading} />
            </div>

            <%!-- Input Area --%>
            <div class="p-3 md:p-4 border-t border-slate-700/50 bg-slate-800/30">
              <%!-- Voice transcript preview (when actively listening) --%>
              <div
                :if={@voice_active && @voice_transcript != ""}
                class="mb-2 p-2 bg-emerald-500/10 border border-emerald-500/30 rounded-lg text-sm text-emerald-300"
              >
                <span class="text-emerald-500">Listening:</span> {@voice_transcript}
              </div>
              <%!-- Voice processing indicator --%>
              <div
                :if={@voice_processing}
                class="mb-2 p-2 bg-amber-500/10 border border-amber-500/30 rounded-lg text-sm text-amber-300 flex items-center gap-2"
              >
                <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                  <circle
                    class="opacity-25"
                    cx="12"
                    cy="12"
                    r="10"
                    stroke="currentColor"
                    stroke-width="4"
                  >
                  </circle>
                  <path
                    class="opacity-75"
                    fill="currentColor"
                    d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                  >
                  </path>
                </svg>
                Processing speech...
              </div>
              <%!-- Voice editing mode banner --%>
              <div
                :if={@voice_editing}
                class="mb-2 p-2 bg-blue-500/10 border border-blue-500/30 rounded-lg text-sm text-blue-300 flex items-center justify-between"
              >
                <span>Edit your message before sending</span>
                <button
                  type="button"
                  phx-click="cancel_voice_edit"
                  class="text-blue-400 hover:text-blue-300"
                >
                  Cancel
                </button>
              </div>

              <form phx-submit="send_message" class="flex items-center gap-2">
                <%!-- Voice button with keyboard shortcut hint --%>
                <button
                  :if={@voice_supported}
                  type="button"
                  phx-click="toggle_voice"
                  phx-hook="VoiceInput"
                  id="voice-input"
                  title="Toggle voice input (Ctrl+M)"
                  class={[
                    "p-2.5 md:p-3 rounded-xl transition-all",
                    cond do
                      @voice_processing -> "bg-amber-500 text-white"
                      @voice_active -> "bg-red-500 text-white animate-pulse"
                      true -> "bg-slate-700 text-slate-400 hover:text-white hover:bg-slate-600"
                    end
                  ]}
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z"
                    />
                  </svg>
                </button>

                <%!-- Text input --%>
                <input
                  type="text"
                  name="message"
                  id="message-input"
                  value={@input_value}
                  phx-change="update_input"
                  phx-hook="FocusInput"
                  placeholder={
                    cond do
                      @voice_active -> "Listening..."
                      @voice_editing -> "Edit and press Enter to send"
                      true -> "Ask a question or give feedback..."
                    end
                  }
                  class="flex-1 bg-slate-700/50 px-3 md:px-4 py-2.5 md:py-3 text-white placeholder-slate-500 rounded-xl focus:outline-none focus:ring-2 focus:ring-emerald-500/50 text-sm md:text-base"
                  autocomplete="off"
                  disabled={@loading || @agent == nil || @voice_active}
                />

                <%!-- Send button --%>
                <button
                  type="submit"
                  disabled={@loading || @input_value == "" || @agent == nil}
                  class="p-2.5 md:p-3 bg-gradient-to-r from-emerald-500 to-teal-500 text-white rounded-xl hover:from-emerald-600 hover:to-teal-600 disabled:opacity-50 disabled:cursor-not-allowed transition-all shadow-lg shadow-emerald-500/25 disabled:shadow-none"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8"
                    />
                  </svg>
                </button>
              </form>
              <%!-- Keyboard shortcut hint --%>
              <p
                :if={@voice_supported}
                class="mt-1.5 text-xs text-slate-600 text-center hidden md:block"
              >
                Press <kbd class="px-1 py-0.5 bg-slate-700 rounded text-slate-400">Ctrl+M</kbd>
                to toggle voice input
              </p>
            </div>
          </div>

          <%!-- Right Panel: Diagram --%>
          <div class="flex-1 md:w-1/2 flex flex-col bg-slate-900/50 min-h-0">
            <div class="px-4 py-2 md:py-3 border-b border-slate-700/50 flex items-center justify-between">
              <h2 class="text-sm font-medium text-slate-400">Architecture Diagram</h2>
              <div class="flex items-center gap-2">
                <%!-- Diagram loading indicator --%>
                <div
                  :if={@diagram_loading}
                  class="flex items-center gap-1.5 text-xs text-amber-400"
                >
                  <svg class="w-3.5 h-3.5 animate-spin" fill="none" viewBox="0 0 24 24">
                    <circle
                      class="opacity-25"
                      cx="12"
                      cy="12"
                      r="10"
                      stroke="currentColor"
                      stroke-width="4"
                    >
                    </circle>
                    <path
                      class="opacity-75"
                      fill="currentColor"
                      d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                    >
                    </path>
                  </svg>
                  Updating...
                </div>
                <%!-- Show raw toggle --%>
                <button
                  :if={@diagram_code}
                  phx-click="toggle_raw_diagram"
                  class={[
                    "text-xs px-2 py-1 rounded transition-colors",
                    if(@show_raw_diagram,
                      do: "bg-slate-700 text-white",
                      else: "text-slate-500 hover:text-white"
                    )
                  ]}
                >
                  {if @show_raw_diagram, do: "Show Diagram", else: "Show Raw"}
                </button>
              </div>
            </div>
            <div class="flex-1 overflow-auto p-4">
              <%= if @diagram_code do %>
                <%= if @show_raw_diagram do %>
                  <%!-- Raw Mermaid code view --%>
                  <div class="bg-slate-800 rounded-lg p-4 font-mono text-sm text-slate-300 overflow-x-auto">
                    <pre class="whitespace-pre-wrap">{@diagram_code}</pre>
                  </div>
                <% else %>
                  <%!-- Rendered diagram with transition --%>
                  <div
                    id="mermaid-diagram"
                    phx-hook="Mermaid"
                    phx-update="ignore"
                    data-code={@diagram_code}
                    class="flex items-center justify-center min-h-full transition-opacity duration-300"
                  >
                    <%!-- Mermaid renders here via JS hook --%>
                  </div>
                <% end %>
              <% else %>
                <div class="flex flex-col items-center justify-center h-full text-center">
                  <div class="w-16 h-16 rounded-2xl bg-slate-800 flex items-center justify-center mb-4 border border-slate-700">
                    <svg
                      class="w-8 h-8 text-slate-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="1.5"
                        d="M4 5a1 1 0 011-1h14a1 1 0 011 1v2a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM4 13a1 1 0 011-1h6a1 1 0 011 1v6a1 1 0 01-1 1H5a1 1 0 01-1-1v-6zM16 13a1 1 0 011-1h2a1 1 0 011 1v6a1 1 0 01-1 1h-2a1 1 0 01-1-1v-6z"
                      />
                    </svg>
                  </div>
                  <p class="text-slate-500 text-sm">
                    Diagram will appear here as we discuss the architecture
                  </p>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Components

  @spec preference_group(map()) :: Phoenix.LiveView.Rendered.t()
  defp preference_group(assigns) do
    ~H"""
    <div>
      <p class="text-xs text-slate-500 mb-1">{@label}</p>
      <div class="flex flex-wrap gap-1">
        <%= for tech <- @options do %>
          <button
            type="button"
            phx-click="update_preference"
            phx-value-category={@category}
            phx-value-tech={tech}
            class={[
              "px-2 py-1 text-xs rounded transition-colors",
              if(tech in @selected,
                do: "bg-emerald-500/20 text-emerald-400 border border-emerald-500/50",
                else: "bg-slate-700/50 text-slate-400 hover:text-white border border-transparent"
              )
            ]}
          >
            {tech}
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @spec preference_accordion(map()) :: Phoenix.LiveView.Rendered.t()
  defp preference_accordion(assigns) do
    ~H"""
    <div class="border border-slate-700/50 rounded-lg overflow-hidden">
      <button
        type="button"
        phx-click="toggle_preference_section"
        phx-value-section={@category}
        class="w-full px-3 py-2 flex items-center justify-between bg-slate-800/50 text-sm text-slate-300"
      >
        <span>
          {@label}
          <span :if={@selected != []} class="text-emerald-400 ml-1">
            ({length(@selected)})
          </span>
        </span>
        <svg
          class={["w-4 h-4 transition-transform", if(@expanded, do: "rotate-180")]}
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
        </svg>
      </button>
      <div :if={@expanded} class="p-2 bg-slate-900/50">
        <div class="flex flex-wrap gap-1">
          <%= for tech <- @options do %>
            <button
              type="button"
              phx-click="update_preference"
              phx-value-category={@category}
              phx-value-tech={tech}
              class={[
                "px-2 py-1 text-xs rounded transition-colors",
                if(tech in @selected,
                  do: "bg-emerald-500/20 text-emerald-400 border border-emerald-500/50",
                  else: "bg-slate-700/50 text-slate-400 hover:text-white border border-transparent"
                )
              ]}
            >
              {tech}
            </button>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @spec suggestion_chip(map()) :: Phoenix.LiveView.Rendered.t()
  defp suggestion_chip(assigns) do
    ~H"""
    <button
      phx-click="send_suggestion"
      phx-value-text={@text}
      class="px-3 md:px-4 py-2 bg-slate-800/50 hover:bg-slate-700/50 border border-slate-700/50 hover:border-emerald-500/50 text-slate-300 hover:text-white rounded-full text-xs md:text-sm transition-all"
    >
      {@text}
    </button>
    """
  end

  @spec message_bubble(map()) :: Phoenix.LiveView.Rendered.t()
  defp message_bubble(assigns) do
    ~H"""
    <div class={[
      "flex gap-2 md:gap-3",
      if(@message.role == "user", do: "flex-row-reverse", else: "flex-row")
    ]}>
      <div class={[
        "w-7 h-7 md:w-8 md:h-8 rounded-lg flex items-center justify-center flex-shrink-0",
        avatar_classes(@message.role)
      ]}>
        <%= if @message.role == "user" do %>
          <svg class="w-3.5 h-3.5 md:w-4 md:h-4 text-white" fill="currentColor" viewBox="0 0 24 24">
            <path d="M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />
          </svg>
        <% else %>
          <svg
            class="w-3.5 h-3.5 md:w-4 md:h-4 text-white"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M9.75 3.104v5.714a2.25 2.25 0 01-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 014.5 0m0 0v5.714c0 .597.237 1.17.659 1.591L19 14.5"
            />
          </svg>
        <% end %>
      </div>
      <div class={[
        "max-w-[85%] rounded-2xl px-3 md:px-4 py-2 md:py-3",
        message_classes(@message.role)
      ]}>
        <div class="prose prose-sm prose-invert max-w-none text-sm md:text-base">
          {render_content(@message)}
        </div>
        <%!-- Timestamp --%>
        <div class="mt-1 text-[10px] md:text-xs opacity-50">
          {format_timestamp(@message)}
        </div>
      </div>
    </div>
    """
  end

  @spec typing_indicator(map()) :: Phoenix.LiveView.Rendered.t()
  defp typing_indicator(assigns) do
    ~H"""
    <div class="flex gap-2 md:gap-3">
      <div class="w-7 h-7 md:w-8 md:h-8 rounded-lg bg-gradient-to-br from-emerald-500 to-teal-500 flex items-center justify-center flex-shrink-0">
        <svg
          class="w-3.5 h-3.5 md:w-4 md:h-4 text-white"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9.75 3.104v5.714a2.25 2.25 0 01-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 014.5 0m0 0v5.714c0 .597.237 1.17.659 1.591L19 14.5"
          />
        </svg>
      </div>
      <div class="bg-slate-800/50 backdrop-blur border border-slate-700/50 rounded-2xl px-3 md:px-4 py-2 md:py-3">
        <div class="flex items-center gap-1">
          <div class="w-2 h-2 bg-emerald-400 rounded-full animate-bounce [animation-delay:-0.3s]">
          </div>
          <div class="w-2 h-2 bg-emerald-400 rounded-full animate-bounce [animation-delay:-0.15s]">
          </div>
          <div class="w-2 h-2 bg-emerald-400 rounded-full animate-bounce"></div>
        </div>
      </div>
    </div>
    """
  end

  # Styles

  @spec avatar_classes(String.t()) :: String.t()
  defp avatar_classes("user"), do: "bg-gradient-to-br from-blue-500 to-cyan-500"
  defp avatar_classes("assistant"), do: "bg-gradient-to-br from-emerald-500 to-teal-500"
  defp avatar_classes("system"), do: "bg-gradient-to-br from-amber-500 to-orange-500"
  defp avatar_classes(_), do: "bg-gradient-to-br from-slate-500 to-slate-600"

  @spec message_classes(String.t()) :: String.t()
  defp message_classes("user"), do: "bg-gradient-to-br from-blue-500 to-cyan-500 text-white"

  defp message_classes("assistant"),
    do: "bg-slate-800/50 backdrop-blur border border-slate-700/50 text-slate-100"

  defp message_classes("system"),
    do: "bg-amber-500/20 border border-amber-500/30 text-amber-200"

  defp message_classes(_),
    do: "bg-slate-800/50 border border-slate-700/50 text-slate-100"

  @spec render_content(message()) :: Phoenix.HTML.safe() | String.t()
  defp render_content(%{role: "assistant", content: content}) do
    case Earmark.as_html(content) do
      {:ok, html, _} ->
        sanitized = HtmlSanitizeEx.markdown_html(html)
        Phoenix.HTML.raw(sanitized)

      {:error, _, _} ->
        content
    end
  end

  defp render_content(%{content: content}), do: content

  @spec format_timestamp(message()) :: String.t()
  defp format_timestamp(%{timestamp: timestamp}) when not is_nil(timestamp) do
    Calendar.strftime(timestamp, "%H:%M")
  end

  defp format_timestamp(_), do: ""

  # Private functions

  @spec create_message(String.t(), String.t()) :: message()
  defp create_message(role, content) do
    %{role: role, content: content, timestamp: DateTime.utc_now()}
  end

  @spec send_user_message(Phoenix.LiveView.Socket.t(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  defp send_user_message(socket, message) do
    if socket.assigns.agent do
      user_message = create_message("user", message)

      socket =
        socket
        |> update(:messages, &(&1 ++ [user_message]))
        |> assign(:input_value, "")
        |> assign(:loading, true)
        |> assign(:voice_transcript, "")
        |> assign(:voice_editing, false)

      send(self(), {:chat, message})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @spec generate_session_id() :: String.t()
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end

  @spec start_supervised_agent(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  defp start_supervised_agent(session_id, tech_preferences) do
    system_prompt = SystemPrompt.build(tech_preferences: tech_preferences)

    child_spec = {
      ConversationAgent,
      name: via_tuple(session_id), system_prompt: system_prompt
    }

    DynamicSupervisor.start_child(SysDesignWiz.AgentSupervisor, child_spec)
  end

  @spec via_tuple(String.t()) :: {:via, Registry, {atom(), String.t()}}
  defp via_tuple(session_id) do
    {:via, Registry, {SysDesignWiz.AgentRegistry, session_id}}
  end

  @spec default_tech_preferences() :: map()
  defp default_tech_preferences do
    %{
      "databases" => ["PostgreSQL", "Redis"],
      "caching" => [],
      "queues" => ["Kafka"],
      "cloud" => ["AWS"]
    }
  end
end
