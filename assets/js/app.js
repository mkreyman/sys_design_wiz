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
// Store recognition directly on window to survive module reloads
Hooks.VoiceInput = {
  mounted() {
    console.log('VoiceInput: Hook mounted, recognition exists:', !!window._sdwRecognition)

    // Update hook reference
    window._sdwHook = this
    window._sdwIsListening = window._sdwIsListening || false
    window._sdwFinalTranscript = window._sdwFinalTranscript || ''
    window._sdwAutoSend = window._sdwAutoSend !== false
    window._sdwPauseDelay = window._sdwPauseDelay || 2000

    // Only initialize recognition once
    if (!window._sdwRecognition) {
      console.log('VoiceInput: Initializing recognition (first time)')

      // Check for browser support
      const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition
      if (!SpeechRecognition) {
        this.pushEvent('voice_unsupported', {})
        return
      }

      window._sdwRecognition = new SpeechRecognition()
      window._sdwRecognition.continuous = true
      window._sdwRecognition.interimResults = true
      window._sdwRecognition.lang = 'en-US'

      window._sdwRecognition.onresult = (event) => {
        let interimTranscript = ''

        // Reset pause timer on any speech activity
        if (window._sdwHook) window._sdwHook.resetPauseTimer()

        for (let i = event.resultIndex; i < event.results.length; i++) {
          const transcript = event.results[i][0].transcript
          if (event.results[i].isFinal) {
            window._sdwFinalTranscript += transcript + ' '
          } else {
            interimTranscript += transcript
          }
        }

        // Send transcript updates to LiveView
        if (window._sdwHook) {
          window._sdwHook.pushEvent('voice_transcript', {
            final: window._sdwFinalTranscript.trim(),
            interim: interimTranscript
          })
        }

        // Start pause timer for auto-send
        if (window._sdwAutoSend && window._sdwFinalTranscript.trim() && window._sdwHook) {
          window._sdwHook.startPauseTimer()
        }
      }

      window._sdwRecognition.onerror = (event) => {
        console.error('VoiceInput: Speech recognition error:', event.error)
        // "aborted" error is normal when stopping, don't treat it as a real error
        if (event.error !== 'aborted' && window._sdwHook) {
          window._sdwHook.pushEvent('voice_error', { error: event.error })
        }
        window._sdwIsListening = false
      }

      window._sdwRecognition.onend = () => {
        console.log('VoiceInput: onend fired, isListening:', window._sdwIsListening, 'stopping:', window._sdwStopping)
        window._sdwStopping = false
        if (window._sdwIsListening) {
          // Auto-restart if still supposed to be listening
          console.log('VoiceInput: Auto-restarting recognition')
          try {
            window._sdwRecognition.start()
          } catch (e) {
            console.error('VoiceInput: Failed to auto-restart', e)
            window._sdwIsListening = false
          }
        }
      }
    } else {
      console.log('VoiceInput: Recognition already initialized, reusing')
    }

    // Listen for toggle events from LiveView
    this.handleEvent('toggle_voice', () => {
      console.log('VoiceInput: toggle_voice event received, isListening:', window._sdwIsListening, 'recognition:', !!window._sdwRecognition)
      if (window._sdwIsListening) {
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
      window._sdwAutoSend = enabled
    })

    // Global keyboard shortcut: Ctrl+M to toggle voice
    if (!window._sdwKeyboardHandler) {
      window._sdwKeyboardHandler = (event) => {
        if (event.ctrlKey && event.key === 'm') {
          event.preventDefault()
          console.log('VoiceInput: Ctrl+M pressed, hook:', !!window._sdwHook, 'isListening:', window._sdwIsListening, 'recognition:', !!window._sdwRecognition)
          if (!window._sdwHook) {
            console.warn('VoiceInput: No hook reference! Cannot toggle voice.')
            return
          }
          if (window._sdwIsListening) {
            window._sdwHook.stopListening()
          } else {
            window._sdwHook.startListening()
          }
        }
      }
      document.addEventListener('keydown', window._sdwKeyboardHandler)
    }
  },

  startListening() {
    console.log('VoiceInput: startListening called, recognition:', !!window._sdwRecognition, 'isListening:', window._sdwIsListening)

    if (!window._sdwRecognition) {
      console.warn('VoiceInput: No recognition available')
      return
    }

    // If we're in a stopping state, wait and retry
    if (window._sdwStopping) {
      console.log('VoiceInput: Recognition is stopping, will retry in 200ms')
      setTimeout(() => {
        if (window._sdwHook) {
          window._sdwHook.startListening()
        }
      }, 200)
      return
    }

    try {
      window._sdwFinalTranscript = ''
      window._sdwIsListening = true
      window._sdwRecognition.start()
      this.pushEvent('voice_started', {})
      console.log('VoiceInput: Started listening successfully')
    } catch (e) {
      console.error('VoiceInput: Failed to start', e.message)
      // Recognition might already be running, try to stop and restart
      window._sdwIsListening = false
      try {
        window._sdwRecognition.stop()
      } catch (stopError) {
        // Ignore stop errors
      }
      // Try again after a short delay
      setTimeout(() => {
        if (!window._sdwIsListening && window._sdwHook) {
          window._sdwHook.startListening()
        }
      }, 200)
    }
  },

  stopListening() {
    if (!window._sdwRecognition) return

    console.log('VoiceInput: Stopping listening')
    this.clearPauseTimer()
    window._sdwIsListening = false
    window._sdwStopping = true
    try {
      window._sdwRecognition.stop()
    } catch (e) {
      console.error('VoiceInput: Error stopping', e)
      window._sdwStopping = false
    }
    this.pushEvent('voice_stopped', { transcript: (window._sdwFinalTranscript || '').trim() })
  },

  startPauseTimer() {
    this.clearPauseTimer()
    const self = this
    window._sdwPauseTimer = setTimeout(() => {
      if (window._sdwIsListening && (window._sdwFinalTranscript || '').trim()) {
        // Notify LiveView that pause was detected (for auto-send)
        const transcript = (window._sdwFinalTranscript || '').trim()
        // Clear transcript BEFORE stopping so voice_stopped gets empty transcript
        // This prevents voice_stopped from triggering edit mode
        window._sdwFinalTranscript = ''
        self.pushEvent('voice_auto_send', { transcript: transcript })
        self.stopListening()
      }
    }, window._sdwPauseDelay || 2000)
  },

  resetPauseTimer() {
    this.clearPauseTimer()
  },

  clearPauseTimer() {
    if (window._sdwPauseTimer) {
      clearTimeout(window._sdwPauseTimer)
      window._sdwPauseTimer = null
    }
  },

  destroyed() {
    // Don't destroy global state - just clear the hook reference
    if (window._sdwHook === this) {
      window._sdwHook = null
    }
    // Don't stop recognition or clear state on destroy
    // The global state persists across remounts
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
