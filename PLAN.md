# ClaudeWatch Multi-Model Overhaul Plan

## Goal

Turn the Anthropic-only watch app into a fast, watch-first multi-model client with two clear access paths:

1. **Free Cloud**: a verified anonymous OpenAI-compatible route is used by default; an optional deployable gateway can add operator-controlled rate limiting.
2. **Bring Your Own Key**: developers select a provider and securely store their own key on the watch.

## Implementation Steps

- [x] Replace the Claude-specific model type with a provider-neutral catalog of fast models: OpenRouter free Qwen/Kimi routes, Groq-hosted open models, Claude Haiku, GPT-4o mini, Gemini Flash, and Perplexity Sonar.
- [x] Add connection-mode and provider configuration, persist selection in `UserDefaults`, and migrate secrets from `UserDefaults` to Keychain.
- [x] Replace the Anthropic-only request client with a unified chat service supporting Anthropic, OpenAI-compatible providers, Google Gemini, and the hosted free-cloud gateway.
- [x] Redesign onboarding, chat, model picker, and settings around fast model selection, connection status, system Dictation, concise responses, and a compact Watch-friendly visual language inspired by modern AI chat clients.
- [x] Add a Cloudflare Worker gateway template that validates model IDs against the curated free allowlist, applies basic rate limits, and forwards OpenAI-compatible chat requests.
- [x] Rewrite the README with model/provider coverage, gateway deployment, BYOK setup, API-key security, project structure, and watch deployment instructions.
- [x] Compile the Watch app for a watchOS device SDK and resolve source-level SDK errors. The local Xcode beta sandbox cannot start its simulator/macro services, so simulator UI validation and Worker dependency installation remain environment-limited.

## Product Decisions

- The verified default route is configured in the Watch app so Quick Chat works out of the box. The URL remains editable because anonymous free services can change or be replaced by an operator-controlled gateway.
- “Free” labels mean no user key is required for the configured route. Availability and quotas remain dependent on the upstream provider.
- The app deliberately prioritizes small/fast models and limits answers to 180 output tokens by default for a responsive wrist experience.
- The Watch app sends conversations directly to provider APIs in BYOK mode. A gateway is strongly recommended for any shared or production credential.
