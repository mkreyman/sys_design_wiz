# Competition Starter Template

Pre-configured Phoenix project for 2-hour competition sprints.

**Default AI Engine:** Claude Code SDK (`claude_code ~> 0.14`)

## Quick Start

```bash
# 1. Copy to workspace with your project name
cp -r ~/workspace/.claude/skills/ai-agent-builder/competition-starter ~/workspace/<your_project>

# 2. Run setup script (renames modules, updates configs)
cd ~/workspace/<your_project>
./setup.sh <YourProjectName>

# 3. Configure authentication (choose one):
#    Option A: Claude subscription
claude && claude /login
#    Option B: API key
export ANTHROPIC_API_KEY="sk-ant-your-key"

# 4. Verify PLT (should be instant if pre-built)
mix dialyzer

# 5. Start development
mix phx.server
```

## Pre-Built Components

### AI Components
- **ClaudeCodeClient**: Wraps Claude Code SDK with ClientBehaviour pattern
- **ClaudeCodeAgent**: Native sessions with streaming support
- **ConversationAgent**: GenServer with tool execution support

### Infrastructure
- **Quality Gates**: `mix precommit` alias configured
- **Pre-commit Hook**: Ready to install
- **LLM Client Behaviour**: Mox-ready pattern with DI
- **Test Setup**: Mocks, fixtures, and ClaudeCode.Test stubs

### UI Components
- **LiveView Chat**: Production-ready chat interface with:
  - DynamicSupervisor for agent lifecycle management
  - Process monitoring with automatic crash recovery
  - `connected?/1` check to prevent agent orphaning
  - XSS-safe markdown rendering (HtmlSanitizeEx)

### Context Management
- **SimpleMemory**: In-memory with timestamps and auto-trimming (20 messages)
- **Claude Sessions**: Automatic context retention across queries

## Directory Structure

```
lib/sys_design_wiz/
├── agent/
│   ├── conversation_agent.ex    # GenServer with tool execution
│   └── claude_code_agent.ex     # Native Claude Code sessions
├── llm/
│   ├── client_behaviour.ex      # Behaviour for LLM swapping/mocking
│   ├── claude_code_client.ex    # Default Claude Code implementation
│   └── openai_client.ex         # Legacy OpenAI support
└── context/
    └── simple_memory.ex         # In-memory message list

lib/sys_design_wiz_web/
└── live/
    └── chat_live.ex             # Single LiveView for chat UI

test/
├── support/
│   ├── mocks.ex                 # Mox definitions
│   └── fixtures.ex              # Test helpers
├── agent/
│   ├── conversation_agent_test.exs
│   └── claude_code_agent_test.exs
└── llm/
    └── claude_code_client_test.exs
```

## Configuration

### Authentication

The Claude Code SDK handles authentication automatically:

```bash
# Development: Claude subscription
claude && claude /login

# Production: API key
export ANTHROPIC_API_KEY="sk-ant-your-key"
```

### Switching LLM Providers

In `config/config.exs`:

```elixir
# Default: Claude Code SDK
config :sys_design_wiz, :llm_client, SysDesignWiz.LLM.ClaudeCodeClient

# Alternative: OpenAI (requires OPENAI_API_KEY)
config :sys_design_wiz, :llm_client, SysDesignWiz.LLM.OpenAIClient
```

## Agent Usage

### Simple Approach (Native Sessions)

```elixir
alias SysDesignWiz.Agent.ClaudeCodeAgent

{:ok, session} = ClaudeCodeAgent.start_link(system_prompt: "Be helpful")
{:ok, response} = ClaudeCodeAgent.chat(session, "Hello!")
ClaudeCodeAgent.stop(session)
```

### With Streaming (LiveView)

```elixir
ClaudeCodeAgent.stream_to_pid(session, "Tell me a story", self())

# Receive:
# {:chunk, "Once"} -> {:chunk, " upon"} -> ... -> :stream_complete
```

### Traditional GenServer Approach

```elixir
alias SysDesignWiz.Agent.ConversationAgent

{:ok, agent} = ConversationAgent.start_link(system_prompt: "Be helpful")
{:ok, response} = ConversationAgent.chat(agent, "Hello!")
```

## Testing

```elixir
# Use ClaudeCode.Test for SDK calls
ClaudeCode.Test.stub(ClaudeCode, fn _query, _opts ->
  [ClaudeCode.Test.text("Stubbed response")]
end)

# Use Mox for ClientBehaviour implementations
expect(MockClient, :chat, fn _messages, _opts ->
  {:ok, "Mocked response"}
end)
```

## After Setup

1. Configure authentication (Claude subscription or API key)
2. Update the system prompt in `conversation_agent.ex` or `claude_code_agent.ex`
3. Implement competition-specific features
4. Run `mix precommit` before every commit

## PLT Status

To build PLT (takes 3-5 minutes, do this BEFORE competition):

```bash
mix deps.get
mix dialyzer --plt
```

The PLT will be cached for instant dialyzer runs during competition.
