# US-08: Voice Input with Mic Toggle

## Story

**As an** interviewer,
**I want** to speak my questions using a microphone,
**So that** I can practice verbal interview skills and interact more naturally.

## Acceptance Criteria

1. **Mic Toggle Button**
   - Clear microphone icon button next to text input
   - Visual states: off (default), listening, processing
   - Click to start listening, click again to stop
   - Keyboard shortcut (e.g., Ctrl+M or spacebar hold)

2. **Voice Recognition**
   - Uses Web Speech API for browser-native recognition
   - Continuous listening while mic is active
   - Transcribed text appears in input field in real-time
   - Auto-punctuation where supported

3. **Visual Feedback**
   - Pulsing animation while listening
   - Audio level indicator (optional)
   - "Listening..." status text
   - Transcription preview as user speaks

4. **Submission Flow**
   - Auto-send after pause in speech (configurable delay)
   - Or manual send with button/Enter key
   - Option to edit transcription before sending

5. **Error Handling**
   - Graceful fallback if mic not available
   - Permission request with clear explanation
   - Error message if recognition fails
   - Works in supported browsers only (Chrome, Edge, Safari)

## Technical Notes

- Use Web Speech API (`webkitSpeechRecognition` / `SpeechRecognition`)
- Implement in JavaScript hook, communicate with LiveView via `pushEvent`
- Handle browser compatibility (not supported in Firefox)
- Consider interim vs final results for real-time display

## JavaScript Hook Outline

```javascript
Hooks.VoiceInput = {
  mounted() {
    this.recognition = new (window.SpeechRecognition || window.webkitSpeechRecognition)();
    this.recognition.continuous = true;
    this.recognition.interimResults = true;

    this.recognition.onresult = (event) => {
      const transcript = Array.from(event.results)
        .map(result => result[0].transcript)
        .join('');
      this.pushEvent("transcript_update", {text: transcript});
    };
  }
}
```

## UI States

```
[🎤] Off (gray)      - Click to start listening
[🎤] Listening (red, pulsing) - Click to stop
[🎤] Processing (orange) - Converting speech to text
```

## Dependencies

- US-07: Text input

## Estimation

- **Complexity**: Medium
- **Priority**: P1 (Important)
