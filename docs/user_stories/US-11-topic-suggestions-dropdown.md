# US-11: Topic Suggestions Dropdown (Stretch)

## Story

**As an** interviewer,
**I want** a dropdown of common system design topics,
**So that** I can quickly start an interview without thinking of a problem.

## Acceptance Criteria

1. **Topic List**
   - Dropdown/autocomplete at the top of chat
   - 15-20 common system design problems
   - Organized by difficulty or category
   - Search/filter functionality

2. **Suggested Topics**
   - URL Shortener (beginner)
   - Rate Limiter (beginner)
   - Notification System (intermediate)
   - Twitter/Social Feed (intermediate)
   - Distributed Cache (intermediate)
   - Search Autocomplete (intermediate)
   - Video Streaming (Netflix) (advanced)
   - Ride Sharing (Uber) (advanced)
   - Distributed Message Queue (advanced)
   - Real-time Collaborative Editor (advanced)

3. **Selection Behavior**
   - Selecting a topic auto-populates first message
   - Or immediately sends as interviewer's opening
   - Custom topic option ("Other...")
   - Recently used topics shown first

4. **Topic Details** (optional)
   - Brief description on hover
   - Difficulty indicator (⭐ to ⭐⭐⭐)
   - Estimated time to complete
   - Key concepts covered

## Technical Notes

- Store topics in a config file or module
- Use Phoenix LiveView's `live_select` or custom component
- Consider keyboard navigation (arrow keys, Enter)
- Track usage for "recent" feature

## UI Mockup

```
┌─ Choose a Topic ──────────────────────────────────────┐
│ 🔍 Search topics...                               [▼] │
├───────────────────────────────────────────────────────┤
│ ⭐    URL Shortener                                   │
│ ⭐    Rate Limiter                                    │
│ ⭐⭐   Notification System                            │
│ ⭐⭐   Twitter Feed                                   │
│ ⭐⭐⭐  Video Streaming Platform                      │
│ ───────────────────────────────────                   │
│ ✏️    Custom topic...                                 │
└───────────────────────────────────────────────────────┘
```

## Dependencies

- US-01: Basic chat interface

## Estimation

- **Complexity**: Low
- **Priority**: P3 (Stretch Goal)
