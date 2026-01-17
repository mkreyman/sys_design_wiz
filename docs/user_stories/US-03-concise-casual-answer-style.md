# US-03: Concise, Casual Answer Style

## Story

**As an** interviewer,
**I want** the AI candidate to respond in short paragraphs with a casual tone,
**So that** the interaction feels like a real interview with a thoughtful but approachable candidate.

## Acceptance Criteria

1. **Response Length**
   - Answers are 2-4 short paragraphs maximum
   - Each paragraph focuses on one key point
   - No lengthy walls of text

2. **Casual Tone**
   - Conversational language, not overly formal
   - Uses phrases like "So basically...", "The way I see it...", "Good point..."
   - Occasional filler words for natural flow ("well", "actually", "you know")
   - Slight imperfections that feel human (like a non-native English speaker)

3. **Structure**
   - Direct answer first, then brief explanation
   - Uses simple language to explain complex concepts
   - Avoids jargon unless interviewer uses it first

4. **Interaction Style**
   - Acknowledges good questions from interviewer
   - Admits uncertainty when appropriate ("I'm not 100% sure, but...")
   - Asks for feedback ("Does that make sense?", "Want me to go deeper on that?")

## Technical Notes

- Define tone in system prompt
- Include examples of desired response style
- May need to tune temperature for more natural responses

## Example Responses

**Too formal (avoid):**
> "The system would utilize a distributed caching layer implemented with Redis to ensure low-latency access to frequently requested data. This architectural decision optimizes read performance while maintaining consistency guarantees through the implementation of a cache-aside pattern."

**Desired style:**
> "So for the caching layer, I'd probably go with Redis. It's fast and handles this kind of thing well. The basic idea is we check the cache first, and if it's not there, we grab it from the database and stick it in the cache for next time. Pretty standard pattern, but it works great for read-heavy stuff like this."

## Dependencies

- US-01: Basic chat interface
- US-02: Candidate persona with clarifying questions

## Estimation

- **Complexity**: Low
- **Priority**: P0 (Critical Path)
