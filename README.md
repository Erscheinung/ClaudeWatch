# ClaudeWatch

A standalone, voice-first watchOS assistant. Originally built for Claude, the app now defaults to Gemini Flash-Lite and also supports other providers with your own keys.

## Watch experience

- **Tap to speak.** The home screen shows a microphone and a short instruction. Opening the microphone has its own state; “Listening” appears once recording begins.
- **Tap the arrow to send.** While listening, light trails orbit the sphere, a timer shows recording duration, and a haptic confirms recording started. Questions send automatically at 60 seconds. Cancel discards the recording.
- **See progress.** A rotating violet ring and “Thinking…” identify the request in progress. Cancel stops waiting; failed requests offer Retry question without recording again.
- **Read comfortably.** Answers use Dynamic Type, regular body text, inline Markdown emphasis and links, spaced paragraphs, headings, and lists. Code is shown in monospace; pipe tables are simplified into rows. New answers open at their beginning.
- **Ask again.** A persistent bottom Ask button starts a new recording immediately. The answer area extends toward the bottom edge, with controls kept below the text.
- **Start fresh.** Tap the new-chat (square and pencil) button beside Ask, or swipe left, to clear displayed answers and return to the microphone. This also cancels recording, pending requests, and playback. Ask keeps previous answers on screen; questions are still independent.
- **Choose reply length.** Settings → Replies → Output length offers Light (256 tokens), Balanced (768 tokens, the default), and Heavy (2,048 tokens). The setting persists and applies to text and audio answers without changing the model. Heavy allows more detail and can take longer or cost more; it does not guarantee accuracy.
- **Choose whether to listen.** Settings → Replies → Read aloud is on by default and persists across launches. Switch it off for text-only replies. The speaker button reads the latest answer on demand, and changes to Stop during playback. Speech uses the formatted answer’s plain text.
- **Find settings.** Swipe right, or tap the faint handle and chevron on the left edge. The home screen also includes a quiet swipe hint. Opening Settings cancels active recording or requests and stops speech.

Animations run only during active voice states and respect Reduce Motion and reduced luminance. Buttons have VoiceOver labels. Leaving the app for the background cancels microphone activity and pending requests. Conversation history stays in memory for the current session; each question is sent independently.

## Setup

1. Open Settings from the welcome screen and add your Gemini API key. Keys are stored in the Watch Keychain.
2. Choose a model under **Model**. Only providers with saved keys appear.
3. Leave **Voice → Send as → Audio** selected for Gemini: a recording goes directly to the model.
4. For another provider, select **Text**. Gemini first transcribes the recording, then the selected provider receives the transcript. This mode also requires a Gemini key; it does not use Apple Dictation.
5. Configure **Output length** and **Read aloud**, return to chat, and tap the mic.

The catalog includes Gemini, Claude, OpenAI, Groq, Perplexity, and OpenRouter models. Provider availability and billing depend on your account. Usage information in the app is informational, not a live balance.

## Run the Watch app

Requirements: a compatible Xcode installation, an Apple Watch with network access, and a provider API key. The current Watch app target is configured for watchOS 27.0; the project and complication retain 10.0 settings. Choose a compatible device/SDK or deliberately align deployment targets before running.

```bash
cd ClaudeWatch
open ClaudeWatch.xcodeproj
```

Select **ClaudeWatch Watch App**, choose your signing team and bundle identifier, then run on your watch. Add the **Claude Watch** microphone complication from the watch face editor to launch the app quickly.

The UX overhaul and subsequent answer-layout, New Chat, and output-length changes were implemented without builds, tests, simulator runs, or device testing at the user's request. Device validation is still pending, including small displays, accessibility sizes, audio interruptions, and the animated recording flow.

## Project layout

```text
ClaudeWatch/
├── ClaudeWatch.xcodeproj/
├── ClaudeWatch Watch App/
│   ├── ClaudeWatchApp.swift    # Persisted settings and Keychain access
│   ├── Models/                # Provider catalog and messages
│   ├── Services/              # Multi-provider API client
│   └── Views/                 # Voice flow, answer formatting, settings
└── ClaudeWatchComplication/
cloudflare-worker/             # Optional legacy free-cloud proxy
```

The API client uses the chosen output-token ceiling and asks for accurate, complete, watch-friendly responses, including clarification when the question is unclear. It no longer forces every answer into 1–4 sentences. Text-mode transcription has a separate 2,048-token ceiling so longer recordings are less likely to lose the end of the question; a transcript reported as truncated is rejected rather than sent as an incomplete question. [Gemini documents `MAX_TOKENS` as the output-limit finish reason](https://ai.google.dev/api/generate-content). No model IDs or defaults were changed. Voice recordings use temporary files removed after sending or cancellation. Failed-request audio is retained only in memory for retry and replaced when a new question starts.

## Development and security

See [AGENTS.md](AGENTS.md) for interaction and implementation guidance. Keep credentials in Keychain; never commit provider keys or bake shared keys into the app. Model IDs live in `Models/ClaudeModel.swift` and should be checked with the provider before changing them.

The optional [Cloudflare Worker](cloudflare-worker/README.md) and legacy free-cloud client code remain in the repository. The current Watch settings use provider keys and do not expose a free-cloud or fallback endpoint editor. Deploying the Worker is separate from the Watch UX.
