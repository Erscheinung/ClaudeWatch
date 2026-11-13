# ClaudeWatch

A standalone, voice-first watchOS assistant. Originally built for Claude, the app now defaults to Gemini Flash-Lite and also supports other providers with your own keys.

## Watch experience

- **See your model.** The home screen shows a compact chip for the selected model. Tap it to change models. VoiceOver reports whether a key is saved; this does not imply a live connection or remaining quota.
- **Tap to speak.** The home screen shows a microphone and a short instruction. Opening the microphone has its own state; “Listening” appears once recording begins.
- **Tap the arrow to send.** While listening, light trails orbit the sphere, a timer shows recording duration, and a haptic confirms recording started. Questions send automatically at 60 seconds. Cancel discards the recording.
- **See progress.** A rotating violet ring and “Thinking…” identify the request in progress. Cancel stops waiting; failed requests offer Retry question without recording again.
- **Read comfortably.** Answers use Dynamic Type, regular body text, inline Markdown emphasis and links, spaced paragraphs, headings, and lists. Code is shown in monospace; pipe tables are simplified into rows. New answers open at their beginning.
- **Ask again.** A persistent bottom Ask button starts a new recording immediately. The answer scroll view fills the space above a compact bottom control row. New chat, Read/Stop, and Ask sit together near the bottom edge, with 44-point tap targets and an 8-point bottom buffer; the text stays above the controls.
- **Start fresh.** Tap the new-chat (square and pencil) button beside Ask, or swipe left, to clear displayed answers and return to the microphone. This also cancels recording, pending requests, and playback. Ask keeps previous answers on screen; questions are still independent.
- **Choose reply length.** Settings → Replies → Output length offers Light (256 tokens), Balanced (768 tokens, the default), and Heavy (2,048 tokens). The setting persists and applies to text and audio answers without changing the model. Heavy allows more detail and can take longer or cost more; it does not guarantee accuracy.
- **Choose whether to listen.** Settings → Read aloud → Read answers is on by default and persists across launches. Switch it off for text-only replies. The speaker button reads the latest answer on demand, and becomes a filled cyan control labeled Stop while speech is preparing or playing. Controls wrap into a second row when the watch width or text size requires it. Stop cancels queued and active narration, and the controls retain full tap targets near the watch’s bottom edge. Speech uses the formatted answer’s plain text.
- **Choose a voice.** Settings → Read aloud → Voice lists simple slots (Female 1–3, Male 1–2) ranked from the voices installed on the watch; tap one to hear it. Speed (Slow, Normal, Fast) sits beside it. Answers are spoken one sentence at a time, so speech starts quickly and Stop cuts in at once; code blocks are skipped, links are read as "link", and emoji and symbols are cleaned up. watchOS exposes only standard-quality voices to apps (no Enhanced or Premium), so Female 1 is the best available rather than a studio voice.
- **Ask about your day (optional).** Settings → Todoist day briefing → Connect Todoist, then turn on Day briefing. With a Gemini model, ask “What's due today, what's overdue, and what looks overloaded?”. ClaudeWatch reads today's and overdue Todoist tasks with GET-only requests and never changes them. Answers end with the data's freshness and coverage. Unknown durations are counted as unknown, not zero, and with no calendar the answer never claims the work fits your day. The feature is off by default, works only with a Gemini model, and uses its own Todoist token, separate from provider keys. When it is on, each question is first transcribed so task questions can be routed; other questions are answered as before. See [docs/SCOPE.md](docs/SCOPE.md).
- **Find settings.** Swipe right, or tap the faint handle and chevron on the left edge. The home screen also includes a quiet swipe hint. Opening Settings cancels active recording or requests and stops speech.

Animations run only during active voice states and respect Reduce Motion and reduced luminance. Buttons have VoiceOver labels. Leaving the app for the background cancels microphone activity and pending requests. Conversation history stays in memory for the current session; each question is sent independently.

## Setup

1. On first launch, choose **Set up from iPhone** or **Enter a key here**. The iPhone route requires the new **ClaudeWatch iPhone App** target to be installed on your paired iPhone.
2. On iPhone, paste a Gemini API key and tap **Verify key**. The app requests Google's live model list, filters for Gemini chat models, and lets you choose one. Successful listing verifies the key for that request; it does not guarantee generation access, audio support, billing, or quota for every listed model.
3. Keep ClaudeWatch open on both devices and tap **Send to Watch**. A success message appears only after the watch writes the key to Keychain. The chosen model and model list persist on the watch. If either device is unavailable, reconnect and send again; credentials are not left in a background transfer queue.
4. Watch-only setup remains available in Settings → Gemini → Add Gemini key. Other providers' keys can also be entered on the watch; the iPhone companion currently handles Gemini only.
5. Choose a model from the home chip or Settings. Leave **Send as → Audio** selected for Gemini to send recordings directly. **Text** mode uses Gemini transcription before sending the transcript to your selected provider, so it also requires a Gemini key.
6. Configure **Replies → Output length** and **Read aloud → Read answers**, Voice, and Speed. Return to chat and tap the mic.

Keys are saved in each device's Keychain. The phone sends a key only to Google for verification and through Apple's paired WatchConnectivity session to your watch; no ClaudeWatch server receives it. Removing the iPhone copy leaves the watch copy in place. Existing watch keys and settings are preserved on app updates. The app does not offer an account-free voice setup because its transcription pipeline requires Gemini.

Gemini models fetched by the companion are cached on the watch; watch-only setup and other providers use the bundled catalog. The catalog includes Gemini, Claude, OpenAI, Groq, Perplexity, and OpenRouter models. Provider availability and billing depend on your account. Usage information in the app is informational, not a live balance.

## Run the Watch app

Requirements: a compatible Xcode installation, an Apple Watch with network access, and a provider API key. The current Watch app target is configured for watchOS 27.0; the project and complication retain 10.0 settings. Choose a compatible device/SDK or deliberately align deployment targets before running.

```bash
cd ClaudeWatch
open ClaudeWatch.xcodeproj
```

Select **ClaudeWatch Watch App**, choose your signing team, then run on your watch. Preserve the existing `com.Erscheinung.ClaudeWatch.watchkitapp` identifier to update the real app. For phone setup, select **ClaudeWatch iPhone App** and run it on the paired iPhone; its companion identifier is `com.Erscheinung.ClaudeWatch`. The watch still runs independently after setup. Add the **Claude Watch** microphone complication from the watch face editor to launch the app quickly.

The UX overhaul and subsequent answer-layout, New Chat, and output-length changes were implemented without builds, tests, simulator runs, or device testing at the user's request. The narration Stop and audio responsiveness fix subsequently passed a Debug build for the watchOS simulator and an isolated Swift harness using the actual audio lifecycle code with mock audio APIs. The harness covered cancellation during activation, replacement playback, stale completion/release callbacks, natural completion, and audio work staying off the main thread. That earlier fix did not include a simulator app launch or watch installation. See the November 2026 validation results below for subsequent device checks. First launch after reinstall, small displays, accessibility sizes, audio interruptions, and the animated recording flow still need validation.

Audio-session transitions are ordered and tied to the recording or narration that owns them. Category changes and speech synthesis run on dedicated queues; activation and deactivation use the asynchronous watchOS APIs. Cancellation updates the controls immediately and stops speech before releasing its audio session. Old callbacks cannot release a newer session. [Apple documents that stopping speech clears unspoken utterances too](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer/stopspeaking(at:)).

### Developer shortcut: Todoist token from `.env` (Debug only)

To avoid typing a 40-character Todoist token on the watch, put it in a gitignored `.env` at the repo root:

```bash
cp .env.example .env && chmod 600 .env   # then set TODOIST_API_TOKEN = <token>
```

The file must contain only `KEY = value` lines with no `#` comments, because Xcode reads it as an xcconfig. The Watch target's **Debug** configuration uses `ClaudeWatch/Config/DebugLocalSecrets.xcconfig` as its base, which includes `.env` if it exists and passes the token to the bundle's Info.plist (`CWDevTodoistToken`). On first launch, a Debug build copies the token into the watch Keychain and turns **Day briefing** on. It only does this when no Todoist token is already saved and you have not set the toggle. It runs once per install, so after **Remove Todoist account** it stays removed. Release builds do not use this configuration, and the seeding code is compiled out of them.

Trade-off: a Debug `.app` built with `.env` carries the token in plain text in its Info.plist. Keep Debug builds on your own devices and use a token you can revoke.

## Project layout

```text
ClaudeWatch/
├── ClaudeWatch.xcodeproj/
├── ClaudeWatch Watch App/
│   ├── ClaudeWatchApp.swift    # Persisted settings and Keychain access
│   ├── Models/                # Provider catalog and messages
│   ├── Services/              # Multi-provider API client
│   └── Views/                 # Voice flow, answer formatting, settings
├── ClaudeWatch iPhone App/    # Key verification and paired watch setup
├── Shared/                    # Model discovery and WatchConnectivity handoff
└── ClaudeWatchComplication/
cloudflare-worker/             # Optional legacy free-cloud proxy
```

The API client uses the chosen output-token ceiling and asks for accurate, complete, watch-friendly responses, including clarification when the question is unclear. It no longer forces every answer into 1–4 sentences. Text-mode transcription has a separate 2,048-token ceiling so longer recordings are less likely to lose the end of the question; a transcript reported as truncated is rejected rather than sent as an incomplete question. [Gemini documents `MAX_TOKENS` as the output-limit finish reason](https://ai.google.dev/api/generate-content). No model IDs or defaults were changed. Voice recordings use temporary files removed after sending or cancellation. Failed-request audio is retained only in memory for retry and replaced when a new question starts.

## Development and security

See [AGENTS.md](AGENTS.md) for interaction and implementation guidance. Keep credentials in Keychain; never commit provider keys or bake shared keys into the app. The only exception is the Debug-only `.env` Todoist shortcut described above: the file is gitignored and the token is never in source. Model IDs live in `Models/ClaudeModel.swift` and should be checked with the provider before changing them.

The optional [Cloudflare Worker](cloudflare-worker/README.md) and legacy free-cloud client code remain in the repository. The current Watch settings use provider keys and do not expose a free-cloud or fallback endpoint editor. Deploying the Worker is separate from the Watch UX.

## Setup validation

The model-discovery and handoff-format checks use the actual shared implementation with a mocked Google endpoint, without real keys or provider charges:

```bash
swiftc -parse-as-library 'ClaudeWatch/ClaudeWatch Watch App/Models/ClaudeModel.swift' ClaudeWatch/Shared/GeminiModelCatalog.swift Tests/SetupTests.swift -o /tmp/ClaudeWatch-SetupTests
/tmp/ClaudeWatch-SetupTests
```

Debug watch builds support `--ui-demo-answer` and `--ui-demo-answer --ui-demo-speaking` for a clearly labeled sample answer and narration. These flags never call providers or start recording, do not alter saved credentials, and are excluded from Release builds. Launch without flags to return to the normal app.

November 2026 implementation validation: Debug builds passed for watchOS Simulator and iOS Simulator SDK destinations, and signed Debug builds passed for the connected Apple Watch Ultra 3 (watchOS 27.0) and iPhone 15 (iOS 27.0.1). Both apps were installed and opened. Device Hub showed the compact model chip with the swipe hint visible, model-picker navigation, the revised Settings summary, a sample answer at its beginning with the controls below it, narration's filled Stop state, and the return to the idle speaker control after Stop. The companion's **Check watch connection** received a readiness reply from the actual paired watch without sending credentials. The watch was relaunched without demo flags and left on its normal home screen.

All 17 setup checks passed, covering model filtering, future model persistence, transfer encoding and validation, pagination, header-only key transmission, rejection messages, repeated-page protection, and cancellation. SDK builds emitted only the App Intents metadata-extraction warning; no App Intents dependency is present. No simulator runtime was installed or launched. A real-key verification and transfer, actual voice-question/provider round trip, small watches, larger accessibility sizes, and subjective voice quality remain unvalidated for these changes. The existing watch key and preferences were preserved; no provider request using that key was made during this validation.

## Day briefing validation (2026-11-07)

On branch `todoist/day-briefing-on-voice-upgrade`, generic Debug builds passed for watchOS, watchOS Simulator, iOS and iOS Simulator. The offline read harness passed 9 of 9 tests, using a fail-closed mock transport with no keys:

```bash
xcodebuild -project ClaudeWatch/ClaudeWatch.xcodeproj -scheme "ClaudeWatch Read Harness Tests" -destination 'platform=macOS' test
```

The setup checks passed 17 of 17. No device, simulator, live Gemini call or live Todoist call was run for this change. Per-item status and the remaining gaps are in [docs/day-briefing-manual-checklist.md](docs/day-briefing-manual-checklist.md#run-log-2026-11-07).
