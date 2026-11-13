# Day briefing manual validation checklist

The checkboxes below are device and manual acceptance items and remain unchecked. Offline and static evidence gathered so far is recorded in the run logs ([2026-11-07](#run-log-2026-11-07), [2026-11-08](#run-log-2026-11-08)). That log does not tick any box that needs a Watch, a live provider or a person.

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

## Run log 2026-11-08

Branch `todoist/day-briefing-on-voice-upgrade` (on top of aa70304), on the same Mac (macOS 27.0, Xcode 27.0 27A5228h). No Watch or iPhone was connected, `xcrun simctl list runtimes` was still empty, and no live Gemini or Todoist request was made. All provider traffic went through the fail-closed `URLProtocol` fixture with synthetic tokens.

### Commands and results

| Command (repo root) | Result |
| --- | --- |
| `xcodebuild … -scheme "ClaudeWatch Read Harness Tests" -destination 'platform=macOS' test` | 24 tests, 0 failures (9 existing + 15 new) |
| `xcodebuild … -scheme "ClaudeWatch Watch App" -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build` | BUILD SUCCEEDED |
| same with `generic/platform=watchOS` | BUILD SUCCEEDED |
| `xcodebuild … -scheme "ClaudeWatch iPhone App" -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` | BUILD SUCCEEDED |
| same with `generic/platform=iOS` | BUILD SUCCEEDED |
| `swiftc -parse-as-library … Tests/SetupTests.swift && run` | 17 checks passed |

The app builds showed only the existing "App Intents metadata extraction skipped" warning. The harness link step also printed `ld: warning: building for macOS-13.0, but linking with dylib … XCTest … built for newer version 14.0`. That warning comes from the test target's macOS 13 deployment target and is harmless for this run.

### Baseline: new cases against the unmodified services

The new cases were also run with the services reverted to aa70304. Eight of the fifteen failed there. Those failures are the bugs fixed below:

| Case | Observed on aa70304 |
| --- | --- |
| `testBriefingDoesNotRetryTodoistAfterHardFailure` | Each of 401, 403, 429 and 503 was read twice, because the model's repeat call hit Todoist again |
| `testTodoistRateLimitAnd5xxAreUnavailableOrPartialWithoutRetry` | 429 said only "Todoist is unavailable right now." (no rate-limit wording) |
| `testWrongTypedToolArgumentsAreRejectedNotDefaulted` | A numeric `date`/`timeZone`/`pageCursor` or a string `limit` was silently defaulted, and 5 of 6 bad calls reached Todoist |
| `testCombiningMarkTitlesAreBoundedByScalars` | A 1-character title kept 5,001 Unicode scalars |
| `testOversizedToolResultIsTruncatedWithCoverageCaveat` | The whole briefing failed with `toolLimit` after the read |
| `testRepeatedProviderCursorStopsPagingAndBriefingStaysBounded` | The cursor loop ran until `toolLimit` |
| `testForgedAndGarbageCursorsAreRejectedBeforeAnyRead` | An unsigned cursor with the right marker, and a cursor from another adapter instance, were accepted and sent to Todoist |
| `testMalformedTaskRecordsAreSkippedHonestlyWithoutGuessedFields` | One malformed record made the whole page `unavailable` with 0 tasks |

### Fixes (smallest change each; DTO fields, statuses, endpoint, bounds and UI unchanged)

- `TodoistReadService`:
  - 429 now gets its own rate-limit message. The status is still `unavailable`, or `partial` after a completed phase, and there is no retry.
  - Malformed task records (missing or wrong-typed `id`/`content`/`priority`/`project_id`/`due`/`deadline`, or priority outside 1–4) are skipped instead of failing the page. The read becomes `partial` with `complete: false` and a "N task(s) … skipped" message. An unreadable `duration` alone still means unknown duration (the 2026-11-07 decision).
  - Titles are also bounded at 240 Unicode scalars.
  - Cursors are now `payload.signature` with HMAC-SHA256 under a per-instance random key (CryptoKit). `ChatView` keeps one service instance, so cursors stay valid within and across briefings in a session.
  - A provider `next_cursor` equal to the one just sent stops paging as `partial` with "Todoist repeated a page cursor".
- `GeminiDayBriefingService`:
  - Present but wrong-typed tool arguments are rejected.
  - After a `permissionDenied` or `unavailable` read, later calls in the same briefing reuse that result without network.
  - A result over the remaining 16 KiB round budget is cut to the longest task prefix that fits: `partial`, `complete: false`, no `nextCursor`, workload recounted for the sent tasks, plus a message and caveat naming the 16 KiB limit (both shown in the audit footer). No further Todoist reads happen after that. If nothing fits, the existing `toolLimit` error is kept.
- `TodoistModels`: added `TodoistWorkloadSignals(tasks:)` (shared counting, no new fields).

### New offline cases (all mocked)

1. **401/403** (`…401And403AreDenied…`): `permissionDenied`, the overdue phase is not read, and the encoded result does not contain the token even when the provider body echoes it. **429/500/502/503** (`…RateLimitAnd5xx…`): `unavailable` after exactly one request. A 429 on the overdue phase leaves `partial` with today's tasks. **No retry from the loop** (`…DoesNotRetryTodoistAfterHardFailure`): one Todoist request across three Gemini rounds, the deterministic fallback is shown instead of model text, and the token never appears in Gemini bodies.
2. **Timeout** (`…TodoistTimeoutIsUnavailableOrPartial`): simulated by the fixture failing with `URLError(.timedOut)`. The real 20 s timer was not exercised. **Cancellation mid-pagination** at adapter level (`…CancellationMidPagination…`): `partial` with only the completed phase, the late page is not applied, and it returns in under 1.5 s. At briefing level (`…CancelledDuringContinuationRead…`): `CancellationError`, and no further Gemini round.
3. **Malformed JSON**: empty, non-JSON, HTML, truncated, wrong root, `results` missing or null or of the wrong type, and a numeric `next_cursor` all give `unavailable` with 0 tasks. **Malformed records** are skipped as `partial`. **Malformed Gemini bodies** give `invalidResponse` with no Todoist read. **Wrong-typed tool arguments** are rejected before any read.
4. **16 KiB**: 25 titles of 240 control characters (~36 KiB serialized). Fewer than 25 tasks are sent, the status is `partial`, the caveat names 16 KiB, the footer says "coverage is partial", and a second model call does not reread.
5. **Cursors**: twelve forged, garbage, tampered, foreign-instance and oversized cursors all give `invalidArguments` with zero requests. The genuine cursor still works. In the **repeated cursor** case, a cooperative model follows the cursor and the run ends with 2 Todoist reads, 3 Gemini rounds and "coverage is partial".
6. **Hostile titles** (injection text plus JSON-breaking quotes): every Gemini body stays valid JSON with exactly one tool declaration, an unchanged `allowedFunctionNames`, and an identical system instruction across rounds. The mocked model "obeys" with `tasks.delete`/`tasks.update` and a mutation-shaped argument, and all are rejected as `invalidArguments`. A fourth round never happens (`toolLimit`), and every Todoist request was `GET /api/v1/tasks/filter`. The titles reach Gemini only as escaped function-response data.

Observed but not changed: when the model issues a tool call in round 3, the loop still executes that read before stopping with `toolLimit`, even though no round remains to receive it (the hostile case sees 4 GETs). This stays inside the 6-call bound and was left as is.

### Checklist rows updated by this run (boxes stay unchecked)

| Item | Evidence | Status |
| --- | --- | --- |
| Empty, partial, permission-denied and unavailable stay distinct | Plus 401/403/429/5xx/timeout/malformed cases | Mocked pass |
| Unknown tools, arguments, forged cursors rejected before a read | Plus wrong-typed arguments and twelve forged cursors | Mocked pass |
| Hostile titles stay data | Tools, config and system instruction unchanged across rounds; obeyed calls rejected | Mocked pass; real model behavior pending |
| Round, call, byte and timeout bounds | 16 KiB truncation, cursor loop, simulated timeout | Mocked pass (real timer pending) |
| Gemini and Todoist errors make no claims that tasks changed | Fallback on hard failure; malformed Gemini gives an error | Mocked pass |
| Cancellation and stale callbacks | Mid-pagination at adapter and briefing level | Mocked pass; device pending |

### Still untested

Everything listed as untested on 2026-11-07 that needs a device or a live provider is still untested: a Watch, iPhone or simulator, real Gemini function calling and thought signatures, real `/tasks/filter` responses (including real 401/403/429 bodies and `Retry-After`), the Settings token sheet, on-device Keychain, lifecycle and audio interruptions, accessibility, timezone/DST boundaries, and a real network timeout.

## Run log 2026-11-13 (device, owner report)

- **Observed by the owner on the Watch:** after the scheme was switched to Debug, the token was seeded and the briefing reached Gemini. Gemini then returned `400: please set allowed_function_names only when function calling mode is ANY`.
- **Cause:** every round sent `toolConfig.functionCallingConfig.allowedFunctionNames`, including the `AUTO` rounds that follow a tool result. Gemini accepts that field only with `mode: ANY`. The mock harness did not model this rule.
- **Fix:** `allowedFunctionNames` is sent only when `mode` is `ANY` and omitted in `AUTO`; the request still declares only the one read tool. The harness now asserts that the field is absent outside `ANY`.
- **Verified:** harness 24/24 and a Debug generic watchOS build. A real Gemini round trip on the Watch is still pending: re-run and ask "What's due today?".

## Run log 2026-11-13 (late): tool loop replaced

- **Owner report on the Watch:** "The day briefing reached its safety limit" (the 3-round / 6-call bound of the tool loop), plus a request for natural questions such as "what's the hardest task for me today?" and "my day is so full of tasks, what can I shift or how can I relax?", with context that does not burn tokens and routing that tells "day"/"tasks" apart from ordinary uses.
- **Change:** `GeminiDayBriefingService` (tool loop) was replaced by `DayBriefingService`:
  - local `DayIntent` scoring decides routing (no tokens);
  - full paging of today/tomorrow plus overdue, with a 120 s cache;
  - a compact `DayDigest` (about 20 tokens per task, 40 lines listed and the rest summarised);
  - one ordinary Gemini call and a one-line footer.
  - Still Gemini-only and GET-only.
- **Harness:** the 10 tool-loop tests and the old intent test were removed. Added:
  - intent routing (13 day / 11 ordinary questions, plus follow-ups and scope);
  - full paging across 4 pages with exactly one model call;
  - hostile titles flattened to one data line;
  - cache reuse and expiry;
  - a denied read failing before any model call;
  - partial coverage labelled, and the tomorrow filter.
  - Result: 19/19 PASS. The Debug generic watchOS build succeeded.
- **Pending on device:** live Gemini answers to the new question types and live `tomorrow` filter behaviour.
