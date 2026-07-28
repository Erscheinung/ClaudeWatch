# iOS Companion App Plan

## Recommendation

Build the companion app. It is the right place for API-key entry, model setup, connection tests, and recovery when the Watch has poor connectivity. Treat it as a medium-to-large addition, not a small screen port: the key requirement is a reliable transport contract between Watch and phone.

**Estimated implementation effort:** 5-8 focused engineering days, plus 1-2 days of physical device and network-condition QA. The existing project is small and uses no dependency manager, so adding the target is low-risk; sharing state and handling WatchConnectivity edge cases are the meaningful work.

## Architecture

- Add an iOS app target and a shared `Core` source group for the model catalog, message DTOs, API client contracts, Keychain helper, and connection-policy types.
- Keep provider keys on the phone Keychain. Do not synchronize them to the Watch by default.
- Add `WatchConnectivity` request/reply messages with a request ID, a compact chat payload, a response payload, timeouts, and provider-safe error codes.
- Persist non-secret settings through `WCSession.updateApplicationContext`: selected model, connection policy, and available-provider status only.
- Keep the Watch direct path for the anonymous Free Cloud endpoint and optional Watch-local keys. The phone remains the secure executor for phone-only and fallback requests.

## Connection Policies

| Policy | Behavior |
| --- | --- |
| Watch only | The Watch sends directly to its configured free endpoint or its own local provider key. No phone fallback. |
| Phone only | The Watch sends the prompt to the companion app; the phone invokes the selected provider with its Keychain key. |
| Hybrid (recommended) | The Watch tries its direct path first. On an eligible network/configuration failure, it retries once through the phone if reachable. |

Phone fallback should be limited to connectivity and missing-watch-key failures. Do not retry provider validation, policy, or quota errors through another route without surfacing them.

## Implementation Steps

- [ ] Add the iOS app target, app icon/configuration, and `Core` source group with explicit target membership. Preserve the current Watch target and compile it after each membership change.
- [ ] Refactor `AIModel`, request/response DTOs, provider client, Keychain wrapper, and connection policy into shared files. Keep Watch-only SwiftUI code in the Watch target.
- [ ] Implement a `WCSession` coordinator on both targets: activation state, reachability, request/reply transport, queued-transfer behavior, timeouts, and a versioned message schema.
- [ ] Implement the iPhone setup dashboard: model picker, provider API-key forms, connection test action, Free Cloud endpoint editor, connection-policy selector, and connection diagnostics.
- [ ] Implement iPhone connection tests by sending a short bounded prompt through the selected route and showing latency, resolved model, and sanitized errors. Never log keys or request headers.
- [ ] Update Watch chat routing for Watch only, Phone only, and Hybrid. Show the active route and fallback result in compact status UI.
- [ ] Add unit tests for route selection, message encoding/decoding, endpoint normalization, and secret-free settings synchronization. Add physical Watch/iPhone tests for reachable, unreachable, locked-phone, and offline cases.
- [ ] Update README with signing/capabilities, paired-device requirements, privacy behavior, and recovery behavior.

## Acceptance Criteria

- A key entered on iPhone can power a Watch request in Phone only and Hybrid modes without the key appearing in Watch storage or WatchConnectivity payloads.
- The iPhone can verify the currently selected model and reports a useful error without exposing credentials.
- Hybrid sends one direct Watch request first, then at most one phone fallback when the failure is eligible and the phone is reachable.
- Existing Watch-only Free Cloud chat remains usable with no paired-phone requirement.
