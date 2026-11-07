# ClaudeWatch scope

Updated 2026-11-07 on branch `todoist/day-briefing-on-voice-upgrade` (from `voice-upgrade` @ f0b5a0d). This page describes what the code does today. Where something is unvalidated, it says so. Validation evidence is listed in [day-briefing-manual-checklist.md](day-briefing-manual-checklist.md#run-log-2026-11-07).

## What the Watch app does today

ClaudeWatch is a standalone watchOS voice assistant. It needs no phone at runtime once a key is on the watch.

| Area | Behavior |
| --- | --- |
| Home | Voice orb with a compact model chip (tap to change model), a subtle left-edge Settings cue and a swipe hint. |
| Voice flow | Tap once to record. The mic has its own "Opening mic…" state, then shows Listening with a timer, orbit animation and haptic. Tap the arrow to send; recordings auto-send at 60 s. Cancel discards. Thinking shows a progress ring and Cancel. A failed request offers Retry, which reuses the in-memory audio. |
| Answers | Markdown is rendered by `AnswerText`, and new answers open at their beginning. A bottom row holds New chat, Read/Stop and Ask. Swipe left starts a new chat, which clears answers and cancels activity. Every question is independent, with no conversation memory. |
| Read aloud | On by default. Speech is sentence by sentence with voice slots (Female 1–3, Male 1–2) and speed (Slow/Normal/Fast). Stop cancels at once. |
| Replies | Output length is Light (256 tokens), Balanced (768, default) or Heavy (2,048). |
| Lifecycle | Backgrounding, leaving the view, opening Settings or the model picker, and New chat all cancel the recording, request and speech. A per-request UUID ignores stale callbacks. |
| Complication | A microphone complication launches the app. |

### Voice input modes

- **Audio** (default): the WAV recording goes straight to the selected Gemini model in one `generateContent` call. Requires a Gemini model.
- **Text**: Gemini Flash-Lite transcribes the recording (2,048-token ceiling; a truncated transcript is rejected), then the transcript goes to the selected provider. Requires a Gemini key even when another provider answers.

### Providers

The answer providers are Gemini (default, Gemini 3.5 Flash-Lite), Anthropic Claude, OpenAI, Groq, Perplexity, OpenRouter and Pollinations. Each uses its own key, stored in the Watch Keychain (`ChatAPIService`; Anthropic Messages, Gemini generateContent, OpenAI-compatible for the rest). OpenRouter and the others work only in Text mode, because they receive the Gemini transcript. The legacy Free Cloud route and the Cloudflare Worker remain in code but are not exposed in Settings.

## What the iPhone companion does today

The companion is Gemini-only setup:

1. Paste a key and verify it by listing Google's models (paginated and filtered to chat models).
2. Pick a model and tap **Send to Watch**. This is a foreground WatchConnectivity `sendMessage`. The Watch replies success only after its Keychain write succeeds. Keys never go into application context or background transfers.
3. **Check watch connection** sends a key-free readiness probe.

The phone does not execute requests. The Watch-only, Phone-only and Hybrid routing in [COMPANION_IOS_PLAN.md](../COMPANION_IOS_PLAN.md) is not built.

## What Week 3 adds: the Todoist day briefing

The question it answers is "What's due today, what's overdue, and what looks overloaded?" on the wrist. The frozen boundary is [todoist-read-contract.md](todoist-read-contract.md). It is ported from `todoist/read-only-day-briefing` (00e8b0d, plus local 9a9a435 and 0ea4eee) onto the voice-upgrade lineage.

| Constraint | How it holds in code |
| --- | --- |
| Default off | `AppSettings.todoistBriefingEnabled` defaults to false. It is forced off when there is no token and turns off when the token is removed. |
| Separate credential | The Todoist token has its own Keychain account, `todoist-read-token`, entered in Settings → Todoist day briefing. Replace and remove do not touch provider keys. TodoistToday is never read. |
| Gemini only | `canUseDayBriefing` requires the enabled flag, a token, a Gemini preferred model and a Gemini key. Other providers never see Todoist tools or data. |
| GET only | `TodoistReadService` issues only `GET /api/v1/tasks/filter?query=today|overdue`. There is no mutation endpoint, Sync command or write type. |
| Pagination | The limit is 1–25 tasks per call. Today and overdue each have a phase cursor, wrapped in an app-issued opaque cursor (1 KiB max, marker-checked). Tasks are deduped by ID within a call. A truncated read is reported as `complete: false`. |
| Bounded tool loop | One tool, `tasks.findByDate`. Unknown tools and arguments are rejected before any read. Bounds are 3 Gemini rounds, 6 calls and 16 KiB of results. The model `functionCall` part and its ID are preserved and answered by a matching `functionResponse`. |
| Honest output | The app appends a footer with the fetch time, complete or partial coverage, Todoist status, the unknown-duration count ("unknown is not zero"), timezone and deadline caveats, and "no calendar, so no feasibility claim". If no read completed, the answer is a deterministic no-results message. Task titles are untrusted data, and descriptions and comments are never sent. |

**Routing on the integrated branch.** The briefing has no new home-screen control, so the orb UI is unchanged. When the feature is available, `ChatView.send` transcribes the recording with Gemini Flash-Lite (even in Audio mode), then `DayBriefingIntent` checks the transcript:

- A task or day question ("what's due today", "on my plate", "overdue", "Todoist", "day briefing") goes to the briefing loop.
- Anything else continues as normal Q&A. Text mode reuses the transcript. Audio mode sends the original audio, as before.

With the feature off, the request path is the same as before. With it on, Audio-mode questions cost one extra transcription call. The 00e8b0d "Day briefing" button was not ported, because home-screen UI changes need mockup approval first.

**Bug fixed while porting.** The adapter decoded Todoist's `duration` as a flat integer. Todoist v1 sends `{"amount", "unit"}`, so any page containing a task with a duration failed to decode and the whole read reported `unavailable`. The adapter now accepts the object, falls back to the flat form, and treats an unrecognized shape as unknown duration. The regression test is `testTodoistV1DurationObjectShapeDecodes`.

### Out of scope for Week 3

Task create, complete, edit and delete; calendar, availability and health inputs; scheduling-feasibility claims; conversation memory and planning sessions; an OAuth browser flow; a phone read broker or cache; and any planner rewrite.

## How this connects to mAI-unified (later weeks)

From `~/Code/mai-unified` (`packages/contracts/README.md`, `docs/claudewatch-todoist-plan.md`, `docs/decisions/0001-go-single-core.md`):

- **nAI decides, mAI talks.** One deterministic Go core (`packages/nai`) is the planner and the authority (journal, drafts, approvals, commands) on every host. The iPhone runs it through gomobile. ClaudeWatch is the voice layer.
- **The read contract stays pinned.** The Week 3 DTO is an independent existing contract. Canonical UUIDs and revisions would be added only by a future host mapper, never by changing this slice. Its partial today/overdue coverage is not a complete canonical inventory.
- **Plan-aware answers come from `today.export`.** The core's pure `today.export` operation turns a planning result into a small, title-truncated JSON for one local date: `items[{start,end,title,kind}]`, `more`, `unplaced`, `plannedMinutes`, `capacityMinutes`, `warnings`. The phone can push it to the Watch, and e-ink or Pi displays can read the same file. That is the route to "what's my plan today" on the Watch, instead of the Watch calling the planner. It is not built in ClaudeWatch yet.
- **Watch writes are proposals only.** A Watch capture goes through `tool.propose` to an unapproved draft and then app-owned review on the phone. A Gemini call or a spoken "yes" is never trusted approval. The Watch's direct read token cannot unlock writes. The first reviewed writes (create, and completing non-recurring tasks) arrive in later batches through the phone.
