# US-09: Technology Preference Checkboxes

## Story

**As an** interviewer,
**I want** to specify technology preferences before starting the interview,
**So that** the AI candidate can tailor responses to technologies I'm familiar with or want to learn.

## Acceptance Criteria

1. **Preference Panel**
   - Collapsible settings panel above or beside chat
   - Checkbox groups organized by category
   - Selections persist during session
   - Clear "Reset to defaults" option

2. **Technology Categories**
   - **Databases**: PostgreSQL, MySQL, MongoDB, DynamoDB, Redis, Cassandra
   - **Message Queues**: Kafka, RabbitMQ, SQS, Redis Pub/Sub
   - **Caching**: Redis, Memcached, CDN
   - **Cloud Providers**: AWS, GCP, Azure, Self-hosted
   - **Languages/Frameworks**: (optional, for code examples)

3. **Selection Behavior**
   - Multiple selections allowed per category
   - "No preference" option defaults to candidate's choice
   - At least one option should be selected per relevant category
   - Tooltips explaining each technology (optional)

4. **Visual Design**
   - Compact, non-intrusive layout
   - Clear category labels
   - Selected state clearly visible
   - Mobile-friendly (accordion style on small screens)

## Technical Notes

- Store preferences in LiveView assigns
- Pass preferences to system prompt dynamically
- Consider storing in localStorage for return visits
- Use Phoenix form components with checkboxes

## UI Mockup

```
┌─ Technology Preferences ─────────────────────────────────┐
│                                                          │
│ Databases:     [✓] PostgreSQL  [ ] MySQL  [✓] Redis     │
│ Message Queue: [✓] Kafka       [ ] RabbitMQ             │
│ Cloud:         [✓] AWS         [ ] GCP    [ ] Azure     │
│                                                          │
│ [Reset to Defaults]                          [Collapse ▲]│
└──────────────────────────────────────────────────────────┘
```

## Dependencies

- US-01: Basic chat interface

## Estimation

- **Complexity**: Low
- **Priority**: P2 (Nice to Have)
