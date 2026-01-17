# Agent Requirements

## High-Level Requirements

### 1. Conversational Agent
- Build an agent that a user can chat with using natural language (e.g., via a simple console or web interface).
- The agent should maintain conversational context across multiple turns.

### 2. Domain Knowledge
- The agent should answer factual questions based on live data from APIs
- Never make up data - always ground responses in tool output
- Example query patterns:
  - "When was the last [event]?"
  - "What's the next [event] and where is it happening?"
  - "How many [items] did [subject] complete in [year]?"
  - "Show me all successful [items]."
  - "Tell me about the most recent [item] from [location]."

### 3. Tool Design

Tools should handle:
- **API request construction** - Build proper requests with parameters
- **Response parsing** - Extract and normalize relevant data
- **Data cleaning** - Handle missing/null fields gracefully
- **Error handling** - Return meaningful errors, not raw exceptions
- **Fallbacks** - Gracefully degrade when APIs are unavailable

Tool implementation patterns:
```elixir
@impl true
def execute(args) do
  # 1. Extract and validate parameters
  action = Map.get(args, "action")

  # 2. Emit telemetry for observability
  SysDesignWiz.Telemetry.span([:sys_design_wiz, :tool], %{action: action}, fn ->
    # 3. Dispatch to specific handler
    dispatch_action(action, args)
  end)
end

# 4. Handle each action with clear error messages
defp get_data(params) do
  case client().fetch_data(params) do
    {:ok, data} ->
      {:ok, format_response(data)}
    {:error, :not_found} ->
      {:error, "No data found matching your criteria"}
    {:error, reason} ->
      {:error, "Failed to fetch data: #{inspect(reason)}"}
  end
end
```

### 4. LLM Integration

The LLM should:
- **Interpret user intent** - Understand what the user is asking for
- **Decide when to call tools** - Use tools for data retrieval, not for reasoning
- **Use tool results** - Ground responses in actual data from tools
- **Format responses** - Present data clearly with headers and lists

Critical rules:
- **Never hardcode answers** - Always fetch live data from tools
- **Never skip tool usage** - If data is available via tools, use them
- **Cite sources** - Reference specific data points from tool output

### 5. Agentic Behavior

The agent should demonstrate autonomous reasoning:

1. **Multiple tool calls** - Make several calls to gather complete information
   - "Compare rockets X and Y" → Call rocket_info for each
   - "Launches this year from location Z" → search + count calls

2. **Clarifying questions** - Ask when user input is ambiguous
   - "Which rocket?" when multiple options exist
   - "What time period?" for open-ended queries

3. **Iterative refinement** - Improve responses for accuracy
   - Check if answer is complete before responding
   - Make follow-up calls if initial data is insufficient

4. **Error recovery** - Handle failures gracefully
   - Try alternative approaches when primary fails
   - Inform user of limitations when data unavailable

## System Prompt Guidelines

Structure your system prompt with:

```
You are [Agent Name], a [role description].

PERSONALITY:
- [Communication style]
- [Behavior traits]
- [Domain expertise signals]

CAPABILITIES:
- [What the agent can do with tools]
- [Types of queries it can handle]
- [Data sources available]

BEHAVIOR RULES:
- ALWAYS use tools to answer questions - never make up data
- If information is ambiguous, ask clarifying questions
- Make multiple tool calls if needed for complete answers
- Format responses with clear structure (headers, lists)
- Cite specific facts from tool results

LIMITATIONS:
- [What the agent cannot do]
- [Data that is not available]
- [Types of queries to deflect]
```

## API Client Patterns

### Behaviour for Testability
```elixir
defmodule SysDesignWiz.API.ClientBehaviour do
  @callback fetch_items(opts :: map()) :: {:ok, list(map())} | {:error, term()}
  @callback get_item(id :: String.t()) :: {:ok, map()} | {:error, term()}
end
```

### Client Implementation
```elixir
defmodule SysDesignWiz.API.Client do
  @behaviour SysDesignWiz.API.ClientBehaviour

  @base_url "https://api.example.com"
  @timeout 15_000

  defp client do
    Req.new(
      base_url: @base_url,
      receive_timeout: @timeout,
      retry: :transient,
      max_retries: 3
    )
  end

  @impl true
  def fetch_items(opts) do
    endpoint = build_endpoint(opts)

    case Req.get(client(), url: endpoint) do
      {:ok, %{status: 200, body: body}} -> {:ok, normalize_response(body)}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

### Configurable Client for Testing
```elixir
# In your tool module:
defp api_client do
  Application.get_env(:sys_design_wiz, :api_client, SysDesignWiz.API.Client)
end

# In test_helper.exs:
Mox.defmock(SysDesignWiz.API.MockClient, for: SysDesignWiz.API.ClientBehaviour)

# In config/test.exs:
config :sys_design_wiz, :api_client, SysDesignWiz.API.MockClient
```

## Quality Gates

Before shipping, verify:
- [ ] All tool actions return `{:ok, result}` or `{:error, message}` tuples
- [ ] Error messages are user-friendly, not raw exceptions
- [ ] Telemetry spans cover all external API calls
- [ ] Tests mock external dependencies via behaviours
- [ ] System prompt enforces tool usage for data queries
- [ ] Agent asks clarifying questions for ambiguous input
