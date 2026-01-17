# US-01: Basic Chat Interface

## Story

**As an** interviewer practicing systems design interviews,
**I want** a simple chat interface to communicate with the AI candidate,
**So that** I can conduct mock interviews in a familiar conversation format.

## Acceptance Criteria

1. **Chat Layout**
   - Two-panel layout: chat messages on the left, diagram on the right
   - Messages display with clear distinction between interviewer (user) and candidate (AI)
   - Messages are timestamped
   - Chat area auto-scrolls to newest message

2. **Message Display**
   - Interviewer messages aligned right with distinct styling
   - Candidate messages aligned left with distinct styling
   - Support for markdown rendering in candidate responses
   - Loading indicator while candidate is "thinking"

3. **Input Area**
   - Text input field at bottom of chat panel
   - Submit button (or Enter key) to send message
   - Input clears after sending
   - Disabled state while waiting for response

4. **Session Management**
   - New session starts with empty chat
   - Session persists during page session (browser tab)
   - Clear visual indication of active session

## Technical Notes

- Use Phoenix LiveView for real-time updates
- Stream responses from Claude Code SDK
- Use Tailwind CSS for responsive layout
- Mobile-friendly design (stack panels vertically on small screens)

## Dependencies

- None (foundational story)

## Estimation

- **Complexity**: Medium
- **Priority**: P0 (Critical Path)
