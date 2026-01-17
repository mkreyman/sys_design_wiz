import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import mermaid from "mermaid"

// Initialize Mermaid with dark theme
mermaid.initialize({
  startOnLoad: false,
  theme: 'dark',
  securityLevel: 'loose',
  flowchart: {
    useMaxWidth: true,
    htmlLabels: true,
    curve: 'basis'
  }
})

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

// Focus input when mounted and after loading completes
Hooks.FocusInput = {
  mounted() {
    this.el.focus()
  },
  updated() {
    if (!this.el.disabled) {
      this.el.focus()
    }
  }
}

// Auto-scroll messages container to bottom when new messages arrive
Hooks.ScrollToBottom = {
  mounted() {
    this.scrollToBottom()
  },
  updated() {
    this.scrollToBottom()
  },
  scrollToBottom() {
    this.el.scrollTop = this.el.scrollHeight
  }
}

// Mermaid diagram rendering hook
Hooks.Mermaid = {
  mounted() {
    this.renderDiagram()
  },
  updated() {
    this.renderDiagram()
  },
  async renderDiagram() {
    const code = this.el.dataset.code
    if (!code || code.trim() === '') {
      this.el.innerHTML = ''
      return
    }

    try {
      // Generate unique ID for each render
      const id = `mermaid-${Date.now()}`
      const { svg } = await mermaid.render(id, code)
      this.el.innerHTML = svg
    } catch (error) {
      console.error('Mermaid render error:', error)
      this.el.innerHTML = `<div class="text-red-400 p-4 text-sm">
        <p class="font-semibold mb-2">Diagram rendering error</p>
        <pre class="bg-slate-900 p-2 rounded text-xs overflow-x-auto">${this.escapeHtml(code)}</pre>
      </div>`
    }
  },
  escapeHtml(text) {
    const div = document.createElement('div')
    div.textContent = text
    return div.innerHTML
  }
}

// Voice input hook using Web Speech API
Hooks.VoiceInput = {
  mounted() {
    this.recognition = null
    this.isListening = false
    this.finalTranscript = ''
    this.pauseTimer = null
    this.autoSendEnabled = true
    this.pauseDelay = 2000 // 2 seconds of silence triggers auto-send

    // Check for browser support
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
    if (!SpeechRecognition) {
      this.pushEvent('voice_unsupported', {})
      return
    }

    this.recognition = new SpeechRecognition()
    this.recognition.continuous = true
    this.recognition.interimResults = true
    this.recognition.lang = 'en-US'

    this.recognition.onresult = (event) => {
      let interimTranscript = ''

      // Reset pause timer on any speech activity
      this.resetPauseTimer()

      for (let i = event.resultIndex; i < event.results.length; i++) {
        const transcript = event.results[i][0].transcript
        if (event.results[i].isFinal) {
          this.finalTranscript += transcript + ' '
        } else {
          interimTranscript += transcript
        }
      }

      // Send transcript updates to LiveView
      this.pushEvent('voice_transcript', {
        final: this.finalTranscript.trim(),
        interim: interimTranscript
      })

      // Start pause timer for auto-send
      if (this.autoSendEnabled && this.finalTranscript.trim()) {
        this.startPauseTimer()
      }
    }

    this.recognition.onerror = (event) => {
      console.error('Speech recognition error:', event.error)
      this.pushEvent('voice_error', { error: event.error })
      this.stopListening()
    }

    this.recognition.onend = () => {
      if (this.isListening) {
        // Auto-restart if still supposed to be listening
        this.recognition.start()
      }
    }

    // Listen for toggle events from LiveView
    this.handleEvent('toggle_voice', () => {
      if (this.isListening) {
        this.stopListening()
      } else {
        this.startListening()
      }
    })

    this.handleEvent('stop_voice', () => {
      this.stopListening()
    })

    // Handle auto-send toggle from LiveView
    this.handleEvent('set_auto_send', ({ enabled }) => {
      this.autoSendEnabled = enabled
    })

    // Global keyboard shortcut: Ctrl+M to toggle voice
    this.keyboardHandler = (event) => {
      if (event.ctrlKey && event.key === 'm') {
        event.preventDefault()
        if (this.isListening) {
          this.stopListening()
        } else {
          this.startListening()
        }
      }
    }
    document.addEventListener('keydown', this.keyboardHandler)
  },

  startListening() {
    if (!this.recognition) return

    this.finalTranscript = ''
    this.isListening = true
    this.recognition.start()
    this.pushEvent('voice_started', {})
  },

  stopListening() {
    if (!this.recognition) return

    this.clearPauseTimer()
    this.isListening = false
    this.recognition.stop()
    this.pushEvent('voice_stopped', { transcript: this.finalTranscript.trim() })
  },

  startPauseTimer() {
    this.clearPauseTimer()
    this.pauseTimer = setTimeout(() => {
      if (this.isListening && this.finalTranscript.trim()) {
        // Notify LiveView that pause was detected (for auto-send)
        this.pushEvent('voice_auto_send', { transcript: this.finalTranscript.trim() })
        this.stopListening()
      }
    }, this.pauseDelay)
  },

  resetPauseTimer() {
    this.clearPauseTimer()
  },

  clearPauseTimer() {
    if (this.pauseTimer) {
      clearTimeout(this.pauseTimer)
      this.pauseTimer = null
    }
  },

  destroyed() {
    this.clearPauseTimer()
    if (this.recognition) {
      this.isListening = false
      this.recognition.stop()
    }
    if (this.keyboardHandler) {
      document.removeEventListener('keydown', this.keyboardHandler)
    }
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket
