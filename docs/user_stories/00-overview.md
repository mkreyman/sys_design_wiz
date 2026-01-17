# SysDesignWiz - User Stories Overview

## Project Vision

An AI agent that plays the **interviewee/candidate** role in systems design interviews. The user acts as the interviewer, and the agent demonstrates good interview behavior: asking clarifying questions, giving concise answers, and drawing architecture diagrams.

## Epics

### Epic 1: Core Chat Experience
- US-01: Basic chat interface
- US-02: Candidate persona with clarifying questions
- US-03: Concise, casual answer style

### Epic 2: Diagram Generation
- US-04: Mermaid diagram generation
- US-05: Diagram auto-update on context changes
- US-06: Mermaid syntax fixing (sanitizer)

### Epic 3: Input Modes
- US-07: Text input
- US-08: Voice input with mic toggle

### Epic 4: Technology Preferences
- US-09: Technology preference checkboxes
- US-10: Preference-aware responses

### Epic 5: Stretch Features
- US-11: Topic suggestions dropdown
- US-12: Requirements checklist tracking
- US-13: Session export to markdown

## Timeline

**Target**: 1 day build (including stretch goals)

## Tech Stack

- Phoenix 1.7 / LiveView
- Claude Code SDK (`claude_code ~> 0.14`)
- Mermaid.js for diagram rendering
- Web Speech API for voice input
- Tailwind CSS for UI
