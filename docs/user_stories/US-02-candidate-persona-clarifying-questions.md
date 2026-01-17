# US-02: Candidate Persona with Clarifying Questions

## Story

**As an** interviewer,
**I want** the AI candidate to ask clarifying questions before diving into solutions,
**So that** I can observe good interview behavior and practice responding to candidate questions.

## Acceptance Criteria

1. **Initial Response Behavior**
   - When given a design problem, candidate first asks 2-4 clarifying questions
   - Questions cover scope, scale, constraints, and requirements
   - Questions are numbered for easy reference

2. **Question Categories**
   - Functional requirements ("What features are must-haves vs nice-to-haves?")
   - Scale/traffic ("How many users? What's the expected QPS?")
   - Constraints ("Any latency requirements? Budget constraints?")
   - Existing systems ("Are there systems we need to integrate with?")

3. **Follow-up Handling**
   - Candidate acknowledges answers to clarifying questions
   - Candidate may ask follow-up questions if answers reveal new concerns
   - Eventually proceeds to solution after gathering enough context

4. **Persona Consistency**
   - Candidate maintains consistent personality throughout session
   - References previous answers in later discussion
   - Shows good listening by summarizing what was discussed

## Technical Notes

- System prompt defines candidate persona
- Track conversation context through Claude Code SDK sessions
- Questions should feel natural, not scripted

## Example Interaction

```
Interviewer: "Design a URL shortener like bit.ly"

Candidate: "Great question! Before I dive in, I'd like to understand a few things:

1. What's the expected scale? How many URLs per day are we looking to shorten?
2. Do we need analytics - like tracking how many times a shortened URL was clicked?
3. Should URLs expire, or do they live forever?
4. Are there any requirements around custom short URLs (vanity URLs)?

Once I understand these, I can propose a design that fits your needs."
```

## Dependencies

- US-01: Basic chat interface

## Estimation

- **Complexity**: Medium
- **Priority**: P0 (Critical Path)
