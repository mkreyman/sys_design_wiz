# US-12: Requirements Checklist Tracking (Stretch)

## Story

**As an** interviewer,
**I want** to see a checklist of requirements that have been addressed,
**So that** I can track interview coverage and ensure all topics are discussed.

## Acceptance Criteria

1. **Checklist Display**
   - Sidebar or collapsible panel showing requirements
   - Checkmarks for addressed items
   - Visual distinction for partially vs fully addressed
   - Progress indicator (e.g., "7/12 requirements covered")

2. **Requirement Categories**
   - Functional requirements
   - Non-functional requirements (scalability, latency, availability)
   - Data model
   - API design
   - Trade-offs discussed
   - Edge cases considered

3. **Auto-Detection**
   - System detects when candidate addresses a requirement
   - Updates checklist automatically during conversation
   - Highlights newly addressed items
   - Candidate may explicitly call out requirements

4. **Manual Override**
   - Interviewer can manually check/uncheck items
   - Add custom requirements
   - Notes field for each requirement (optional)

## Technical Notes

- Parse conversation for requirement keywords
- Use simple NLP or keyword matching
- Store checklist state in LiveView assigns
- Consider using Claude to assess coverage

## Checklist Items

```markdown
## Functional Requirements
- [ ] Core use case defined
- [ ] User flows identified
- [ ] Edge cases discussed

## Scale & Performance
- [ ] Traffic estimates (QPS, DAU)
- [ ] Storage estimates
- [ ] Latency requirements

## Architecture
- [ ] High-level components
- [ ] Data flow
- [ ] API endpoints

## Deep Dives
- [ ] Database schema
- [ ] Caching strategy
- [ ] Failure handling

## Trade-offs
- [ ] Consistency vs Availability
- [ ] Cost vs Performance
- [ ] Complexity vs Maintainability
```

## UI Mockup

```
┌─ Requirements Coverage ───────────────┐
│ Progress: ████████░░ 75% (9/12)       │
├───────────────────────────────────────┤
│ ✅ Core use case defined              │
│ ✅ Traffic estimates                  │
│ ✅ High-level architecture            │
│ ⬜ Database schema (not yet)          │
│ 🔶 Caching strategy (partial)         │
│ ✅ Failure handling                   │
└───────────────────────────────────────┘
```

## Dependencies

- US-01: Basic chat interface
- US-02: Candidate persona with clarifying questions

## Estimation

- **Complexity**: Medium-High
- **Priority**: P3 (Stretch Goal)
