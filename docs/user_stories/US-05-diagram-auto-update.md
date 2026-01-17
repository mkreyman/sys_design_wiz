# US-05: Diagram Auto-Update on Context Changes

## Story

**As an** interviewer,
**I want** the diagram to automatically update as the conversation progresses,
**So that** I can see the design evolve in real-time without asking for explicit diagram updates.

## Acceptance Criteria

1. **Automatic Updates**
   - Diagram updates when candidate discusses new components
   - Diagram reflects changes when candidate revises the design
   - Updates happen seamlessly without explicit "draw diagram" requests

2. **Update Triggers**
   - Adding new components (services, databases, caches)
   - Modifying connections between components
   - Adding or changing data flows
   - Scaling discussions (adding replicas, sharding)

3. **Update Behavior**
   - Smooth transition between diagram versions
   - Previous diagram remains visible until new one renders
   - No flickering or jarring changes
   - Loading indicator during diagram generation

4. **Context Awareness**
   - Candidate tracks what's already in the diagram
   - New additions build on existing structure
   - Removes components if design changes significantly
   - Maintains consistent styling across updates

## Technical Notes

- Parse each response for architectural changes
- Maintain diagram state in LiveView assigns
- Use diffing to minimize re-renders
- Consider debouncing rapid updates
- Store diagram history for potential undo feature

## Example Flow

```
Interviewer: "Let's add a cache layer"

Candidate: "Good idea! I'll add Redis between the API servers and the database..."

[Diagram automatically updates to show Redis cache]

Interviewer: "What about write-through vs write-back?"

Candidate: "For this use case, I'd go with write-through..."

[Diagram updates to show write flow arrows]
```

## Dependencies

- US-04: Mermaid diagram generation

## Estimation

- **Complexity**: Medium-High
- **Priority**: P1 (Important)
