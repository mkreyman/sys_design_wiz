# US-10: Preference-Aware Responses

## Story

**As an** interviewer,
**I want** the AI candidate to use my selected technologies in their design,
**So that** I can practice with relevant tech stacks and learn how they apply.

## Acceptance Criteria

1. **Technology Usage**
   - Candidate uses selected technologies in their proposals
   - Explains why chosen tech fits the use case
   - Mentions trade-offs vs alternatives when relevant
   - Diagrams reflect selected technology names

2. **Natural Integration**
   - Preferences feel like candidate's own choices
   - No robotic "you selected X so I'll use X"
   - Candidate may suggest alternatives if selection doesn't fit
   - Explains reasoning as any good candidate would

3. **Context Sensitivity**
   - Uses appropriate tech for the problem domain
   - Doesn't force-fit incompatible technologies
   - Offers to explain unfamiliar technologies if asked
   - Respects "no preference" by making sensible defaults

4. **Diagram Updates**
   - Technology names appear in diagram labels
   - Uses appropriate icons/shapes for different tech types
   - Consistent naming throughout conversation

## Technical Notes

- Inject preferences into system prompt
- Format: "The interviewer prefers: {tech_list}. Use these when appropriate."
- Update prompt when preferences change mid-session
- Track which technologies have been discussed

## Example Interaction

**Preferences**: PostgreSQL, Kafka, AWS

```
Interviewer: "How would you handle the messaging layer?"

Candidate: "For the messaging piece, I'd go with Kafka since we're
on AWS - we could use Amazon MSK to manage it. Kafka's great for
this because we need high throughput and the ability to replay
messages if something goes wrong.

The producers would be our API servers, and we'd have consumer
groups for each downstream service. Want me to add that to the
diagram?"
```

## Dependencies

- US-09: Technology preference checkboxes
- US-02: Candidate persona with clarifying questions

## Estimation

- **Complexity**: Low
- **Priority**: P2 (Nice to Have)
