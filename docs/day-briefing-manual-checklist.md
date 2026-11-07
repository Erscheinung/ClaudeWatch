# Day briefing manual validation checklist

The checkboxes below are device and manual acceptance items and remain unchecked. Offline and static evidence gathered so far is recorded in the [run log](#run-log-2026-11-07). That log does not tick any box that needs a Watch, a live provider or a person.

## Offline read-harness preparation

An executable XCTest target is wired as `ClaudeWatch Read Harness Tests`. It is
a standalone macOS Foundation/XCTest bundle (macOS 13 or later); it does not
host the Watch app, require a paired Watch, use Keychain credentials, or call
Todoist/Gemini. The target compiles the actual normalized models, Todoist read
adapter, and Gemini day-briefing loop, with an injected `URLSession` whose
`URLProtocol` fixture fails closed on every unhandled URL or method.

The future manual command, to run only when Xcode/macOS validation is
authorized, is:

```text
xcodebuild -project ClaudeWatch/ClaudeWatch.xcodeproj \
  -scheme "ClaudeWatch Read Harness Tests" \
  -destination 'platform=macOS' test
```

This command was first run on 2026-11-07 on the integration branch. The results are in the [run log](#run-log-2026-11-07) below. The prepared
offline cases cover adapter pagination and stable-ID deduplication within a
read, due/overdue and deadline fields, unknown duration workload signals,
empty-success versus missing-credential permission denial, Gemini function-call
ID correlation and credential exclusion from the tool history, invalid tool
allowlist input before Todoist transport, one failed phase retaining only the
successful phase as partial, the three-round/six-call loop bound, and
cancellation of a delayed synthetic read. Coverage of Watch UI, Keychain
account switching, device lifecycle, speech, calendar/availability, real
provider wire compatibility, and full app integration remains manual and
pending below.

The synthetic input/expected-output catalog for the read and Gemini boundaries
is [day-briefing-fixtures.md](day-briefing-fixtures.md). It remains the
documentation oracle; cases not represented by the offline target and all
runtime observations remain pending.

## Setup and regression

- [ ] Existing installs keep the feature flag off; generic Anthropic and Gemini Q&A still work with each provider's existing key/model controls.
- [ ] Gemini remains required for the briefing, transcription, and audio mode; Anthropic never receives Todoist tools.
- [ ] Current one-tap record/second-tap send behavior, bottom Ask control, accessibility labels, Read aloud, manual Stop, and answer rendering remain usable.
- [ ] Replace/account-switching the Todoist credential affects only the Todoist account; removing it disables the feature and does not remove provider keys.
- [ ] No TodoistToday token is displayed, migrated, read, logged, or sent.

## Read contract and date semantics

- [ ] With mocked pages, “today” tasks and “overdue” tasks remain distinct; a due date with a time, all-day due date, recurring due instance, and date-only deadline render with their separate semantics.
- [ ] Device timezone boundaries around midnight and DST produce the requested local date; account/filter timezone uncertainty is stated rather than silently normalized.
- [ ] A task with no duration remains unknown; it is not counted as zero minutes. Known minute/day durations and priority counts produce workload signals.
- [ ] Deadline-only tasks are not falsely reported as covered by the Todoist due filters.
- [ ] A complete live empty result says “none found” while partial live, unavailable/network, and permission-denied results remain distinct and honest; this slice has no stale cache, so no result may be labeled stale.
- [ ] A first page with a continuation cursor does not claim the whole backlog; the bounded follow-up reports completion or remaining coverage.

## Gemini tool safety

- [ ] Valid tasks.findByDate calls preserve function-call IDs/metadata and return a matching function response.
- [ ] Unknown tools, unknown arguments, malformed dates/timezones, out-of-range limits, oversized/forged cursors, and mutation-shaped requests are rejected before any Todoist read.
- [ ] Malicious/instruction-like task titles remain data and cannot change the tool allowlist or system instructions.
- [ ] Three-round, six-call, page-size, result-byte, timeout, and one-read-at-a-time bounds terminate honestly with a retryable message.
- [ ] Gemini errors, quota/rate limits, Todoist errors, empty answers, and partial reads do not produce claims that tasks changed.
- [ ] The app-owned final audit envelope remains present for successful/partial reads; with no completed read, only the deterministic no-results fallback is shown.
- [ ] No API key or Todoist credential enters Gemini prompts, function arguments, tool results, journals, or logs.

## Lifecycle and device behavior

- [ ] Cancel/Stop interrupts pending Gemini/Todoist work, removes only the in-flight placeholder, and never lets a stale callback update a newer request or screen.
- [ ] Leaving Chat, opening Settings, backgrounding, and changing provider/model stop active reads and speech.
- [ ] Auto-speak reads a completed briefing with the existing speech controls; manual Read/Stop remains available and no answer is obstructed.
- [ ] Small watch displays, Dynamic Type/VoiceOver, reduced motion, and reduced luminance remain legible for loading, partial, empty, error, and long-title states.

## Run log 2026-11-07

Branch `todoist/day-briefing-on-voice-upgrade` (from `voice-upgrade` f0b5a0d), on a Mac with Xcode 27.0 (27A5228h). No Watch or iPhone was connected, no simulator runtime is installed (`xcrun simctl list runtimes` is empty), and no live Gemini or Todoist request was made.

### Commands and results

| Command (repo root) | Result |
| --- | --- |
| `xcodebuild … -scheme "ClaudeWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build` | BUILD SUCCEEDED |
| same with `generic/platform=watchOS` | BUILD SUCCEEDED |
| `xcodebuild … -scheme "ClaudeWatch iPhone App" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` | BUILD SUCCEEDED |
| same with `generic/platform=iOS` | BUILD SUCCEEDED |
| `xcodebuild … -scheme "ClaudeWatch Read Harness Tests" -destination 'platform=macOS' test` | 9 tests, 0 failures |
| `swiftc -parse-as-library … Tests/SetupTests.swift && run` | 17 checks passed |

The only build warning was the existing "App Intents metadata extraction skipped".

### What the harness found

- As prepared, the harness had never compiled: it used an unqualified `Reply` type. Fixed with a file-level typealias.
- On the unmodified Week 3 services, 6 of 7 cases passed. The correlation case failed because `URLSession` hands `URLProtocol` the POST body as `httpBodyStream`, not `httpBody`. This was a test bug; the test now reads the stream, and all 7 passed.
- New case `testTodoistV1DurationObjectShapeDecodes` failed against the original adapter (`unavailable`, 0 tasks), because Todoist v1 sends `duration` as `{amount, unit}`. The adapter was fixed and the case now passes.
- New case `testDayBriefingIntentRoutesOnlyTaskQuestions` covers voice routing on the integrated branch.

### Checklist items, offline and static evidence only (boxes stay unchecked)

| Item | Evidence | Status |
| --- | --- | --- |
| Feature off by default | `AppSettings.init` defaults to false and forces false without a token (code reading) | Static only; device pending |
| Gemini only; Anthropic never gets tools | `canUseDayBriefing` requires a Gemini preferred model and a Gemini key; the briefing is the only caller of the tool loop | Static only |
| One-tap UX, Ask, Read/Stop unchanged | No home or answer view changes; the feature-off `send` path is unchanged; Watch builds succeed | Device pending |
| Replace or remove the Todoist account only | Separate Keychain account `todoist-read-token`; removing it disables the feature and does not touch provider accounts | Device pending |
| No TodoistToday token | `grep TodoistToday` finds no Swift reference | Static pass |
| Today and overdue kept distinct; due, deadline and recurring fields | Harness pagination case (buckets, recurring flag, date-only deadline) | Mocked pass |
| Midnight, DST and account timezone | Not covered | Pending |
| Unknown duration is not zero | Harness pagination and v1-shape cases | Mocked pass |
| Deadline-only coverage caveat | Caveat string is always attached; no live check | Partial |
| Empty, partial, permission-denied and unavailable stay distinct | Harness empty/denied and failed-phase cases | Mocked pass (401/403/429 not yet mocked) |
| Continuation does not claim the whole backlog | Harness pagination (`complete: false` plus cursor, then complete) | Mocked pass |
| Function-call ID correlation | Harness correlation case (ID echoed, token absent from the body) | Mocked pass |
| Unknown tools and arguments rejected before a read | Harness invalid-input case (no Todoist request) | Mocked pass (forged cursor not yet mocked) |
| Hostile titles stay data | Hostile title passes through as data in the harness; model behavior not tested | Partial; live pending |
| Round, call and byte bounds | Harness 3-round/6-call case | Mocked pass (16 KiB bound and timeout not yet mocked) |
| No-results fallback and audit footer | Harness invalid-input case (fallback) and correlation case (footer) | Mocked pass |
| No key or token in prompts, logs or arguments | Correlation case checks the Gemini body; no `print`/`os_log`/`Logger` in Watch sources | Mocked and static pass |
| Cancellation and stale callbacks | Harness delayed-read cancel; `requestID` guard and `cancelActivity` on background, disappear, Settings and model picker (code reading) | Mocked pass; device pending |
| Auto-speak of the briefing | Uses the existing `speech.speak` path | Device pending |
| Small displays, Dynamic Type, VoiceOver, reduced motion | Not covered | Pending |

### Still untested

Every item that needs a Watch, iPhone or simulator, or real Gemini and Todoist accounts: live wire compatibility (Gemini function calling on 3.5 Flash-Lite with thought signatures, the real `/tasks/filter` responses), voice transcription feeding routing, the Settings token sheet, Keychain on device, lifecycle and audio interruptions, accessibility, and timezone or DST boundaries. The mock gaps are 401/403/429 statuses, timeouts, malformed JSON, the 16 KiB result cap and forged cursors.
