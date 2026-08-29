# ClaudeWatch

A standalone, voice-first watchOS chat client for fast AI answers. ClaudeWatch is built around small or low-latency models and keeps responses brief enough for the wrist.

## Access Modes

### Free Cloud

Free Cloud is ready on first launch. It uses Pollinations' anonymous legacy OpenAI-compatible endpoint, `https://text.pollinations.ai/openai`, with the verified `openai` route (currently backed by GPT-OSS 20B). No API key is sent by the Watch.

This is a convenience route, not a production SLA. Its model, rate limits, and availability are controlled by the upstream provider and can change without notice.

Qwen3 4B, Kimi K2, and Gemma 3 4B remain available through a personal OpenRouter key. They can move back into Free Cloud when a controlled gateway with those routes is deployed.

### Bring Your Own Key

Developers can select a model and add an API key for its provider directly on the Watch. Keys are stored in the Watch Keychain, and requests go directly to the provider over HTTPS.

| Provider | Fast models included |
| --- | --- |
| Groq | Llama 3.1 8B Instant, GPT-OSS 20B |
| Anthropic | Claude Haiku |
| OpenAI | GPT-4.1 Nano, GPT-4o mini |
| Google AI | Gemini 2.5 Flash-Lite |
| Perplexity | Sonar |
| OpenRouter | Curated free models when a personal OpenRouter key is used |

## Requirements

- Xcode 15+
- watchOS 10+
- An Apple Watch with network access
- A provider API key for Bring Your Own Key mode

## Run the Watch App

```bash
cd ClaudeWatch
open ClaudeWatch.xcodeproj
```

In Xcode, select the **ClaudeWatch Watch App** target, choose a signing team, give the bundle identifier a unique value, select a Watch simulator or paired watch, and run with `Cmd + R`.

### Watch controls

- Tap the centre sphere once to start recording, then tap it again to send.
- Swipe right from the left edge of the chat screen to open **Settings**.
- The default **Audio** voice mode sends one recording directly to Gemini, avoiding a separate transcription request. Use **Text** mode only when you need to send voice queries to a non-Gemini model.
- Add the **Claude Watch** complication from the Watch face editor. Its microphone glyph opens the app directly to the voice interface.

The app icon provides dedicated Watch launcher and App Store slots, and the complication uses a system microphone glyph rather than relying on the app icon. The chat sphere is intentionally static between state changes to keep the Watch interface responsive. A physical watch provides the most reliable voice-entry experience.

## Optional Free Cloud Proxy

The included Worker is optional. It forwards only the verified anonymous route and applies a basic rate limit if you want an endpoint you control.

```bash
cd ../cloudflare-worker
npm install
npx wrangler login
npm run deploy
```

Copy the resulting Worker base URL, for example `https://claudewatch-free-cloud.example.workers.dev`, then open **Settings > Free Cloud Gateway** in the Watch app and paste it. The app appends `/v1/chat/completions` itself. Leave the built-in Pollinations URL unchanged to use the default route.

Before making the worker public, configure Cloudflare WAF/rate-limit rules or replace its best-effort in-memory limiter with a Durable Object.

## Bring Your Own Key

1. In the app, open **Settings** and set **Mode** to **Your Key**.
2. Choose a model under **Model**.
3. Add the corresponding provider key under **API Keys**.
4. Return to chat and speak or type a question.

The app caps outputs at 180 tokens and supplies a concise watch-specific system prompt. Change `systemPrompt` or the `max_tokens` values in `ClaudeAPIService.swift` for a different response style.

## Project Layout

```text
ClaudeWatch/
├── ClaudeWatch.xcodeproj/
├── ClaudeWatch Watch App/
│   ├── Models/                 # Provider-neutral model catalog and messages
│   ├── Services/               # Speech recognition and multi-provider client
│   └── Views/                  # Watch chat, model picker, and settings
└── README.md
cloudflare-worker/
├── src/index.ts                # Free-cloud model allowlist and proxy
└── wrangler.toml
```

## Security

- Provider keys are stored in the Watch Keychain, not `UserDefaults`.
- Bring Your Own Key requests are sent directly to the provider selected by the user.
- Do not put shared provider keys in source code, `Info.plist`, or the Watch app.
- The Free Cloud route has a hard allowlist and output cap. Its availability is upstream-controlled; production deployments should use an operator-controlled gateway and edge rate limiting.

## Model Maintenance

Provider model identifiers and free routes change. Update `AIModel.allCases` in `ClaudeModel.swift`, verify the endpoint with a real request, and update `FREE_MODELS` in `cloudflare-worker/src/index.ts` together when rotating the free-cloud offering.
