# US-07: Text Input

## Story

**As an** interviewer,
**I want** a text input field to type my questions and responses,
**So that** I can communicate with the AI candidate using my keyboard.

## Acceptance Criteria

1. **Input Field**
   - Multi-line text area at bottom of chat panel
   - Placeholder text: "Ask a question or give feedback..."
   - Auto-resize up to 4 lines as user types
   - Clear visual focus state

2. **Submission**
   - Enter key sends message (Shift+Enter for new line)
   - Send button for mouse/touch users
   - Input clears after successful send
   - Prevent empty message submission

3. **State Management**
   - Disabled while waiting for AI response
   - Visual indication of disabled state (grayed out)
   - Re-enables automatically when response completes
   - Preserves draft if user navigates away (optional)

4. **Accessibility**
   - Proper ARIA labels
   - Keyboard navigation support
   - Screen reader compatible
   - Sufficient color contrast

## Technical Notes

- Use Phoenix LiveView form with `phx-submit`
- Handle `phx-keydown` for Enter key submission
- Consider `phx-debounce` for rapid typing
- Store input value in socket assigns for controlled input

## UI Mockup

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│  [Chat messages area]                                   │
│                                                         │
├─────────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────┐ ┌──┐│
│ │ Ask a question or give feedback...              │ │➤ ││
│ └─────────────────────────────────────────────────┘ └──┘│
└─────────────────────────────────────────────────────────┘
```

## Dependencies

- US-01: Basic chat interface

## Estimation

- **Complexity**: Low
- **Priority**: P0 (Critical Path)
