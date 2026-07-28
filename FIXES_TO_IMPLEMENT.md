# Follow-up Fix Analysis

## P0: Prove and Stabilize Quick Chat

- **Add an in-app connection test.** The default anonymous route was verified with a live request on 2026-07-28, but the Watch has no way to test it before a real chat. Add a bounded `Reply with ok` action in settings with latency and sanitized status.
- **Separate free-route metadata from provider catalog metadata.** The default free route uses Pollinations' legacy `openai` model, while Qwen/Kimi/Gemma require personal OpenRouter keys today. Model availability needs an explicit route capability rather than relying only on `isFreeCloudModel`.
- **Make endpoint migration safe.** Store a versioned default endpoint and migrate stale blank/custom `UserDefaults` values. Do not overwrite a user-provided URL.
- **Replace the best-effort Worker limiter for public use.** The in-memory map resets between isolates. Use a Cloudflare Durable Object or WAF rate-limit rule before promoting it as a public proxy.

## P1: Correctness and Resilience

- **Verify model IDs continuously.** Model identifiers and provider capabilities are mutable. Add a checked catalog update process and provider contract tests using non-secret test credentials in CI.
- **Add request cancellation and retry policy.** The current 35-second timeout is bounded but a dismissed Watch view does not cancel its task. Cancel pending work on view exit and retry only transient transport errors once.
- **Persist conversations intentionally.** The current session disappears after relaunch. Add a small, encrypted/local conversation store with a clear-history action and retention limit.
- **Surface provider errors better.** Normalize authentication, quota, endpoint, and unsupported-model errors so users can correct configuration without decoding raw HTTP text.

## P2: Product Quality

- **Add haptics and accessible states.** Notify on response/error, provide VoiceOver labels for status icons, and support Dynamic Type validation on small Watch sizes.
- **Run real-device QA.** Test the anonymous route and every BYOK adapter on an actual paired Watch over Wi-Fi, cellular, and phone relay. The local Xcode beta environment cannot run the simulator service.
- **Add the iOS companion app.** Follow [COMPANION_IOS_PLAN.md](COMPANION_IOS_PLAN.md) to place key setup, connection testing, and hybrid routing on the phone.
