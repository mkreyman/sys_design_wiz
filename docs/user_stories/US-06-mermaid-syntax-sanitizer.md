# US-06: Mermaid Syntax Fixing (Sanitizer)

## Story

**As an** interviewer,
**I want** the system to automatically fix common Mermaid syntax errors,
**So that** diagrams render reliably even when the AI produces slightly malformed code.

## Acceptance Criteria

1. **Error Detection**
   - Detect invalid Mermaid syntax before rendering
   - Identify common LLM mistakes (unclosed brackets, invalid characters)
   - Log errors for debugging without disrupting user experience

2. **Auto-Correction**
   - Fix unescaped special characters in labels
   - Balance unclosed brackets and parentheses
   - Correct common typos (e.g., `flowcahrt` → `flowchart`)
   - Add missing diagram type declarations

3. **Fallback Handling**
   - Show last valid diagram if current one fails
   - Display friendly error message with raw code for debugging
   - Offer "Show raw Mermaid" option for troubleshooting

4. **Prevention**
   - System prompt includes Mermaid best practices
   - Guide AI toward simpler, more reliable syntax
   - Prefer flowcharts over complex diagram types

## Technical Notes

- Implement sanitizer module in Elixir
- Common fixes:
  - Escape quotes in labels: `"User's Data"` → `"User''s Data"`
  - Remove problematic characters: `<`, `>`, `&` in labels
  - Fix node IDs with spaces: `Load Balancer` → `LB[Load Balancer]`
- Consider using Mermaid's error callback for detection
- Cache successful renders to use as fallback

## Common LLM Mistakes to Handle

```elixir
# Unescaped special characters
"DB[(User's Database)]"  →  "DB[(Users Database)]"

# Invalid node IDs
"Load Balancer --> API"  →  "LB[Load Balancer] --> API"

# Missing direction
"graph\n  A --> B"  →  "graph TD\n  A --> B"

# Unclosed subgraph
"subgraph API\n  A\n"  →  "subgraph API\n  A\nend"
```

## Dependencies

- US-04: Mermaid diagram generation

## Estimation

- **Complexity**: Medium
- **Priority**: P1 (Important)
