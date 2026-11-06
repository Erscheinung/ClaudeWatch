# Day briefing manual validation checklist

Validation is intentionally pending for this implementation. Do not treat this checklist as executed evidence.

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
- [ ] Empty results say “none found” while stale/partial, unavailable/network, and permission-denied results remain distinct and honest.
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
