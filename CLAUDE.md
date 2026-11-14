# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

ClaudeWatch is a standalone, voice-first watchOS assistant (now Gemini-first despite the name) with a small iPhone setup companion. [AGENTS.md](AGENTS.md) holds the binding Watch UX contract; [docs/SCOPE.md](docs/SCOPE.md) describes what the app does and what the Week 3 Todoist day briefing adds.

## Layout and pitfalls

- The git root is this directory. The Xcode project and all Swift sources are in `ClaudeWatch/`. **The enclosing `~/Documents/WatchOS Apps/` folder is a separate git repo with everything untracked**, so run git commands from this directory, not its parent.
- `~/Desktop/Code/ClaudeWatch` is a stale early snapshot that only carries the original `todoist/read-only-day-briefing` commits. Do not develop there.
- The project uses explicit file membership in `project.pbxproj` and has no synchronized folders and no package manager. A new `.swift` file must be added to each target that compiles it. The `xcodeproj` Ruby gem installed here (1.15) cannot open this project (objectVersion 56), so edit the pbxproj directly with unique IDs, then run `plutil -lint` on it.
- Root `README.md` is the user-facing doc. `ClaudeWatch/README.md` only points to it. PLAN.md and FIXES_TO_IMPLEMENT.md are historical (July 2026). Some of their items, such as Free Cloud and the gateway editor, are no longer exposed in the Watch UI.

## Build and test

Run these from the repo root. No simulator runtimes are installed on this Mac (`xcrun simctl list runtimes` is empty), so use generic destinations. Signing is not needed for compile checks.

```bash
# Watch app (embeds the complication)
xcodebuild -project ClaudeWatch/ClaudeWatch.xcodeproj -scheme "ClaudeWatch Watch App" \
  -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
#   device SDK: -destination 'generic/platform=watchOS'

# iPhone companion (embeds the Watch app)
xcodebuild -project ClaudeWatch/ClaudeWatch.xcodeproj -scheme "ClaudeWatch iPhone App" \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
#   device SDK: -destination 'generic/platform=iOS'

# Offline Todoist/Gemini read harness (macOS XCTest, fail-closed URLProtocol, no real network or keys)
xcodebuild -project ClaudeWatch/ClaudeWatch.xcodeproj -scheme "ClaudeWatch Read Harness Tests" \
  -destination 'platform=macOS' test
#   one test: append -only-testing:"ClaudeWatch Read Harness Tests/DayBriefingReadHarnessTests/testTodoistV1DurationObjectShapeDecodes"

# Setup / model-discovery checks (plain swiftc executable, mocked Google endpoint)
swiftc -parse-as-library 'ClaudeWatch/ClaudeWatch Watch App/Models/ClaudeModel.swift' \
  ClaudeWatch/Shared/GeminiModelCatalog.swift Tests/SetupTests.swift -o /tmp/ClaudeWatch-SetupTests \
  && /tmp/ClaudeWatch-SetupTests
```

The only expected build warning is "App Intents metadata extraction skipped". Debug Watch builds accept `--ui-demo-answer` and `--ui-demo-answer --ui-demo-speaking`, which show a sample answer and narration without calling providers. These flags are compiled out of Release builds. For device runs, keep the bundle IDs `com.Erscheinung.ClaudeWatch.watchkitapp` (Watch) and `com.Erscheinung.ClaudeWatch` (iPhone). The Watch target deploys to watchOS 27.0, while the project and complication target 10.0.

The optional `cloudflare-worker/` (legacy free-cloud proxy) is deployed with `npm install && npm run deploy` (wrangler) and is not used by the current Watch UI.

## Architecture

Targets: **ClaudeWatch Watch App** (+ **ClaudeWatchComplication** widget extension), **ClaudeWatch iPhone App**, and **ClaudeWatch Read Harness Tests** (macOS unit-test bundle that compiles the Todoist and briefing sources directly, with no host app).

- `ClaudeWatchApp.swift` holds `AppSettings`, the single `ObservableObject` for persisted settings. It stores UserDefaults for preferences and a **private** `KeychainStore` (service `com.claudewatch.credentials`). Provider keys use account = `AIProvider.rawValue`; the Todoist read token uses account `todoist-read-token`. `preferredModel` only returns a model whose provider has a key, with Gemini Flash-Lite as the fallback default.
- `Models/ClaudeModel.swift` is the provider-neutral catalog: `AIModel`, `AIProvider` (Gemini, Anthropic, OpenAI, Groq, Perplexity, OpenRouter, Pollinations), `VoiceInputMode`, `ReplyLength` (token ceilings), and `ConnectionMode`. The iPhone target also compiles it. Check model IDs with the provider before changing them.
- `Services/ClaudeAPIService.swift` defines `actor ChatAPIService`. It sends one-shot requests per provider (Anthropic Messages, Gemini generateContent, OpenAI-compatible for the rest), sends Gemini audio directly in Audio mode, and runs Gemini transcription in Text mode. Questions are **independent**; no history is sent.
- `Views/ChatView.swift` is the whole voice flow and its state machine. It contains `VoiceRecorder` (AVAudioRecorder to a temp WAV file), the ordered audio-session owner (async activate/deactivate on dedicated queues), and `SpeechOutput` (sentence-by-sentence AVSpeechSynthesizer). Each request has a `requestID` UUID guard, and `cancelActivity()` runs on background, disappear, Settings, model picker and New chat. `send(_:)` is the single routing point for transcription, the day briefing, text Q&A and audio Q&A.
- `Views/MessageBubble.swift` holds `AnswerFormatting` (block/inline Markdown parsing) and `AnswerText`, which renders answers. `Models/SpeechText.swift` derives the spoken text from the same `AnswerFormatting.blocks`. AGENTS.md's `AnswerFormatting.plainText` no longer exists. `Models/VoiceCatalog.swift` maps voice slots (Female 1–3, Male 1–2) to installed voices.
- `Shared/` is compiled into both apps. `GeminiModelCatalog` lists live Gemini models. `CompanionConnection` performs the foreground-only WatchConnectivity key handoff: the phone verifies the key, then sends it with `sendMessage`. The Watch acknowledges only after a Keychain write succeeds. Keys are never put in application context or transfer queues.
- **Week 3 Todoist day briefing** (default off, Gemini only, read only):
  - `Models/TodoistModels.swift` holds the frozen read DTO.
  - `Services/TodoistReadService.swift` is the GET-only `/api/v1/tasks/filter` adapter. It covers the `today` and `overdue` phases, caps reads at 25 tasks, dedupes by ID, and issues opaque two-phase cursors. Unknown duration is never counted as zero.
  - `Services/DayBriefingService.swift` (since 2026-11-13; it replaced the Gemini tool loop and its "safety limit"): `DayIntent` scores the transcript locally (strong/task/time/self/planning signals minus "what day is it", tech "tasks", weather, places), so day questions route and ordinary ones do not; follow-ups after a briefing need less evidence. The service reads today (or tomorrow) plus overdue by paging `findTasks` until Todoist has no next cursor (no page cap; cached 120 s), builds a `DayDigest` (one `#|prio|when|effort|title` line per task, overdue then P1 first, 40 lines listed and the rest summarised by priority; titles flattened to one line), and makes ONE ordinary `sendMessage` call to the preferred Gemini model. The answer ends with one footer line (`Todoist · N tasks · read HH:mm [· partial]`). A denied/unavailable read with no tasks fails before any model call. **Week digest (2026-11-14):**
  - "week", "weekend", "this weekend", "when can I fit…" and other weekday names route to `.week`; today's and tomorrow's own weekday names keep `.today` / `.tomorrow`.
  - When a digest host and secret are in the Keychain (accounts `week-digest-host` / `week-digest-token`; Debug seeds them once from `.env` `WEEK_DIGEST_HOST` / `WEEK_DIGEST_TOKEN`), a week question is one digest GET plus ONE Gemini call. Day questions add one `Calendar:` line for that date.
  - The request has an 8 s timeout, a 32 KiB cap, HTTPS only, no redirects, and the secret goes only to the configured host.
  - Failure statuses become footer notes ("week digest secret rejected / unavailable / format not supported") and the briefing falls back to the Todoist read (`7 days` for week).
  - A stale (older than 3 h) or partial digest still answers, with "stale" in the footer.
  - The contract is in `docs/week-digest-contract.md`.
  - The contract is frozen in [docs/todoist-read-contract.md](docs/todoist-read-contract.md). Do not change its DTO fields or statuses. The checklist is [docs/day-briefing-manual-checklist.md](docs/day-briefing-manual-checklist.md), and synthetic cases are in [docs/day-briefing-fixtures.md](docs/day-briefing-fixtures.md).
- The iPhone app (`ClaudeWatch iPhone App/ClaudeWatchPhoneApp.swift`) handles Gemini only: paste a key, verify it by listing models, pick a model, then Send to Watch. It has its own `PhoneKeychain`. [COMPANION_IOS_PLAN.md](COMPANION_IOS_PLAN.md) describes the unbuilt phone-routed and Hybrid execution modes (WCSession request/reply, Watch only / Phone only / Hybrid policies).

## Rules that are easy to break

These are from AGENTS.md and the user's standing preferences.

- **UX contract:** one tap starts recording and the second tap (send arrow) sends. No hold-to-talk. Keep the ready, preparing, listening, thinking and answer states distinct, with labels, timer, Cancel and Retry. Answers stay unobstructed, open at their beginning, and keep the bottom Ask / New chat / Read-Stop row. Swiping right or tapping the subtle left-edge cue opens Settings; swiping left starts a new chat. Animate only active states, and respect Reduce Motion and reduced luminance.
- **UI changes need approval.** Show before/after mockups (PNGs) and get the user's OK before changing the existing orb UI, gestures or layout. Additive Settings rows in the existing style are the least invasive option.
- Render answers through `AnswerText`, never with raw `Text(String)`. Speech goes through `SpeechText` and honors the persisted Read aloud setting.
- Text voice mode needs a Gemini key even for other answer providers (Gemini does the transcription). Audio mode requires a Gemini model. Setup copy must match this.
- Do not imply conversation memory. Day-briefing planning sessions and memory are out of scope.
- Keys live in Keychain only. Never put them in source, logs, prompts or tool arguments. Test keys come only through env or launch arguments. Exception: the developer's Todoist read token can live in the gitignored, 0600 repo-root `.env`, which only the Watch Debug configuration reads (`ClaudeWatch/Config/DebugLocalSecrets.xcconfig` → Info.plist `CWDevTodoistToken` → a one-time Keychain seed under `#if DEBUG`). `.env` must have no `#` lines, because it is parsed as xcconfig. Never print or commit its value. Never reuse TodoistToday credentials.
- Update the root README and the in-app Setup guide (`SetupHelpView`) whenever controls change.
- Report validation honestly: state what was built, run or tested and on what, and keep device, voice and live-provider checks marked pending until they are actually run.

## Related planning (mAI-unified)

The Todoist work is tracked in the user's Todoist project **mAI**, section "Nov Week 1 Tasks" (W03 = this Watch read slice). The unified planner lives in `~/Code/mai-unified`: a Go core `nai`, with the contracts in `packages/contracts/README.md`, the boundary in `docs/claudewatch-todoist-plan.md`, and `docs/decisions/0001-go-single-core.md`. Future Watch plan-awareness should consume the core's `today.export` file pushed by the phone. Future Watch writes are proposals only, reviewed on the phone. The Watch's direct Todoist read token can never unlock writes.

## Related project: Todoist → Apple Calendar sync (AWS Lambda)

[`Erscheinung/Todoist-Apple-Calendar-Sync`](https://github.com/Erscheinung/Todoist-Apple-Calendar-Sync) is the owner's separate public repo (local clone `~/Documents/Todoist-Apple-Calendar`). ClaudeWatch does not call it today, but it is the natural source of calendar context for the Watch later.
- **What it does:** a one-way sync from all active Todoist tasks with a due date into one iCloud calendar over CalDAV. It manages only the events it created.
  - Date-only tasks become all-day events.
  - Timed tasks use the Todoist duration, or 1 h when none is set.
  - Floating times are rendered in `DISPLAY_TIMEZONE` (default `Asia/Kolkata`).
  - Alerts fire 10 min before timed tasks and at 09:00 for all-day tasks.
  - Completed, deleted or undated tasks remove their events.
- **Infrastructure** (`infra/template.yaml`, CloudFormation):
  - a 256 MB Lambda;
  - two EventBridge UTC cron rules (every 15 min, 07:30–23:45 IST);
  - DynamoDB on-demand for the task↔event mapping;
  - SSM Parameter Store for the Todoist token and the iCloud app-specific password;
  - a private S3 artifact bucket.
- **Commands:**
  - `scripts/deploy.sh --region ap-south-1` deploys. It prompts for secrets without echo and runs one test sync.
  - `scripts/rotate-secrets.sh` replaces secrets without a redeploy.
  - `aws lambda invoke --function-name todoist-apple-calendar-sync …` is a manual sync.
- **Rules:**
  - Secrets live only in SSM, never in either repo. Never print them, and never put the owner's account IDs, calendar names or tokens in this public repo.
  - The sync stays one-way: Todoist is the source of truth.
  - Any future Watch use must stay read-only, and must not put cloud credentials on the Watch. It should read a small derived file, not provider APIs. Task and calendar data should keep the same Gemini-only rule as the day briefing.
- **Ways a Lambda like this could reach Google Calendar** (not built; for future planning):
  1. **Service account plus a shared calendar.** Create a dedicated calendar and share it ("Make changes to events") with a service account's email. The Lambda signs JWTs with the service-account key, stored in SSM. There's no user OAuth and nothing expires, and it works for a personal Gmail account without domain-wide delegation. It can only see calendars explicitly shared with it, which is good least-privilege.
  2. **User OAuth with a refresh token.** Run the installed-app consent flow once locally, store the refresh token in SSM, and let the Lambda mint access tokens (`google-auth`). Use the narrowest scope: `calendar.events` for writing to one calendar, or `calendar.freebusy` / `calendar.readonly` for reading busy time. While the OAuth consent screen is in **Testing** mode, refresh tokens expire after 7 days, so publish the app or prefer option 1.
  3. **Read-only private iCal address.** Google's "secret address in iCal format" lets the Lambda fetch busy events as ICS with no OAuth. Treat the URL as a secret in SSM. It is read-only, so it suits free/busy, not writing.
  4. **Publish ICS, let Google subscribe.** The Lambda writes an `.ics` file to S3, behind a hard-to-guess or rotating presigned URL, and Google Calendar adds it via "From URL". There's no Google credential at all. However, Google refreshes subscribed feeds only every several hours to a day, so it's only good for slow-changing data.
  5. **Apps Script bridge.** A time-driven Google Apps Script inside the Google account pulls from an authenticated Lambda Function URL (shared secret in Script Properties) and writes events with `CalendarApp`. Google auth then stays inside Google, and AWS never holds a Google credential.
  - In every option, a Watch should read only a small derived digest (for example, per-day busy blocks and tasks) from a presigned or authenticated URL. It should never hold Google or AWS credentials itself.

## Proposed architecture changes (2026-11-14, under review)

Nothing here is decided. A first implementation of the week briefing is in the working tree (uncommitted, not run on a device) and is under review. The full review and the implementation prompt live in the unified planner repo: `~/Code/mai-unified/docs/proposals/2026-11-14-architecture-review.md` and `~/Code/mai-unified/docs/prompts/2026-11-14/07-claudewatch-week-context.md`.

- **Keep:** task and calendar data go to Gemini only; one model call per briefing; the frozen Todoist read contract; the orb UI.
- **Week context from one digest.** The Watch would fetch one small, versioned week digest (week tasks plus calendar busy blocks) from an HTTPS endpoint with a read-only bearer secret, then make one Gemini call. The Watch never holds Google or AWS credentials. The digest comes from the calendar-sync Lambda's Function URL (proposed: its own read-only function), which reads free/busy from calendars shared with a service account, so no OAuth refresh token can expire and no event titles leave Google.
- **Routing.** `DayIntent.Scope` gains `week`. Review points: match week words as words, keep today's and tomorrow's weekday names on their own scope, do not swallow digest errors, check the digest version and age, show the build time in local time, and give day questions today's busy blocks.
- **Fallback.** With no digest configured or reachable, the briefing uses the direct Todoist read as now and says that week and calendar context is unavailable.
- **Configuration.** URL and secret in Keychain only, seeded in Debug builds from the gitignored `.env` like the Todoist token. A Settings row needs approved before/after mockups first. Never commit a real endpoint URL or secret to this public repo.
- **Later:** the same digest can carry the planner's `today.export`; Watch writes stay proposals reviewed on the phone or daemon.
