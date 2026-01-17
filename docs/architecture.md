# SysDesignWiz Architecture

## Overview

SysDesignWiz is an AI agent that plays the **interviewee/candidate** role in systems design interviews. The user acts as the interviewer, and the agent demonstrates good interview behavior: asking clarifying questions, giving concise casual answers, and generating architecture diagrams using Mermaid.

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Browser (LiveView)                          │
├─────────────────────┬───────────────────────────────────────────────┤
│    Chat Panel       │              Diagram Panel                    │
│  ┌───────────────┐  │  ┌─────────────────────────────────────────┐  │
│  │ Messages      │  │  │                                         │  │
│  │ - User        │  │  │         Mermaid Diagram                 │  │
│  │ - Candidate   │  │  │         (auto-updates)                  │  │
│  └───────────────┘  │  │                                         │  │
│  ┌───────────────┐  │  └─────────────────────────────────────────┘  │
│  │ Input (text)  │  │                                               │
│  │ [🎤] Voice    │  │                                               │
│  └───────────────┘  │                                               │
└─────────────────────┴───────────────────────────────────────────────┘
```

## Tech Stack

- **Phoenix 1.7 / LiveView** - Real-time web interface
- **Claude Code SDK** - LLM integration (via OpenAI-compatible client)
- **Mermaid.js** - Diagram rendering (client-side)
- **Web Speech API** - Voice input (client-side)
- **Tailwind CSS** - Styling

## Module Structure

```
lib/sys_design_wiz/
├── agent/
│   └── conversation_agent.ex    # GenServer - conversation state
├── llm/
│   ├── client_behaviour.ex      # Behaviour for LLM clients
│   └── openai_client.ex         # OpenAI API client
├── context/
│   └── simple_memory.ex         # In-memory message history
├── diagram/
│   ├── mermaid_parser.ex        # Extract mermaid from responses
│   └── mermaid_sanitizer.ex     # Fix common syntax errors
└── interview/
    └── system_prompt.ex         # Candidate persona prompt

lib/sys_design_wiz_web/
├── live/
│   └── chat_live.ex             # Main interview interface
└── components/
    └── core_components.ex       # Shared UI components

assets/js/
├── app.js                       # Main JS entry
└── hooks/
    ├── mermaid_hook.js          # Diagram rendering
    ├── voice_input_hook.js      # Web Speech API
    └── scroll_hook.js           # Auto-scroll chat
```

## Data Flow

### 1. User Sends Message (Text)

```
User Input → LiveView → ConversationAgent.chat/2 → OpenAI API
                                    ↓
                              Response with potential Mermaid
                                    ↓
                           MermaidParser.extract/1
                                    ↓
                    LiveView assigns: messages + diagram_code
                                    ↓
                         Browser renders both panels
```

### 2. User Sends Message (Voice)

```
Voice Input → Web Speech API → transcript → LiveView event
                                    ↓
                           (same as text flow)
```

### 3. Diagram Auto-Update

```
Each assistant response → MermaidParser.extract/1
                                    ↓
                    If diagram found: update @diagram_code
                                    ↓
                    MermaidHook re-renders diagram
```

## Key Components

### ConversationAgent (GenServer)

Manages conversation state per session:
- System prompt (candidate persona)
- Message history (SimpleMemory)
- LLM client reference

```elixir
%State{
  memory: %SimpleMemory{},
  llm_client: SysDesignWiz.LLM.OpenAIClient,
  tools: []  # No tools needed for this agent
}
```

### System Prompt (Candidate Persona)

Defines the agent's behavior:
- Ask 2-4 clarifying questions before designing
- Respond in short, casual paragraphs
- Generate Mermaid diagrams when discussing architecture
- Reference technologies from user preferences

### MermaidParser

Extracts Mermaid code blocks from LLM responses:

```elixir
def extract(response) do
  # Look for ```mermaid ... ``` blocks
  # Return {:ok, diagram_code} or :no_diagram
end
```

### MermaidSanitizer

Fixes common LLM mistakes in Mermaid syntax:
- Escape special characters in labels
- Fix node IDs with spaces
- Add missing direction declarations
- Balance unclosed subgraphs

### ChatLive (LiveView)

Two-panel layout with:
- Left: Chat messages + input (text/voice)
- Right: Mermaid diagram (auto-updating)
- Optional: Tech preference panel (collapsible)

Assigns:
```elixir
%{
  messages: [],
  input_value: "",
  loading: false,
  diagram_code: nil,
  tech_preferences: %{},
  voice_active: false
}
```

## JavaScript Hooks

### MermaidHook

```javascript
// Renders Mermaid diagram when @diagram_code changes
Hooks.Mermaid = {
  mounted() { this.render(); },
  updated() { this.render(); },
  render() {
    const code = this.el.dataset.code;
    if (code) mermaid.render('diagram', code, this.el);
  }
}
```

### VoiceInputHook

```javascript
// Web Speech API integration
Hooks.VoiceInput = {
  mounted() {
    this.recognition = new webkitSpeechRecognition();
    this.recognition.continuous = true;
    this.recognition.interimResults = true;
    // ... event handlers push to LiveView
  }
}
```

## Configuration

### Environment Variables

```bash
OPENAI_API_KEY=sk-...  # Required for LLM
```

### Application Config

```elixir
# config/config.exs
config :sys_design_wiz, :llm_client, SysDesignWiz.LLM.OpenAIClient

# config/test.exs
config :sys_design_wiz, :llm_client, SysDesignWiz.LLM.MockClient
```

## Testing Strategy

1. **Unit Tests**: MermaidParser, MermaidSanitizer, SystemPrompt
2. **Agent Tests**: ConversationAgent with mocked LLM client
3. **LiveView Tests**: ChatLive with mocked agent
4. **Integration**: Full flow with stubbed LLM responses

## Security Considerations

- XSS protection via HtmlSanitizeEx for markdown
- Mermaid code sanitized before rendering
- No user data persistence (in-memory only)
- Voice input stays client-side (Web Speech API)
