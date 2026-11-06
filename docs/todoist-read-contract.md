# ClaudeWatch Todoist read contract (frozen 2026-11-06)

This is the deliberately small Week 1 read contract used by the Week 3 day briefing. It is a read boundary, not a task-planning or mutation design.

## Authority and credential boundary

- The first vertical slice uses a direct Watch → Todoist API v1 read adapter. It does not depend on phone reachability or a phone cache.
- A Todoist credential is explicitly entered or replaced in ClaudeWatch Settings and stored in this app's Keychain account `todoist-read-token`. It is never copied from TodoistToday, prompts, conversation history, logs, or tool arguments.
- The UI has separate replace/account-switch and remove controls. Removing the credential disables the briefing and does not remove the Gemini/Anthropic keys.
- Todoist's current OAuth documentation defines `data:read` as read-only access to tasks, projects, labels, and filters. This app accepts a separately provisioned access/personal token but does not implement an OAuth browser flow in this slice; setup tells the user to grant the narrowest available scope.
- A broad/personal token can technically authorize writes even though ClaudeWatch exposes only GET requests. The app discloses that client-side read-only behavior does not narrow server-side token scope. No mutation endpoint, Sync command, or write capability is present.

References: [Todoist API v1](https://developer.todoist.com/api/v1/) and [Gemini function calling](https://ai.google.dev/gemini-api/docs/function-calling).

## Normalized read DTO

The adapter's public result is intentionally provider-shaped only at the edge:

```text
FindTasksByDateRequest {
  date: YYYY-MM-DD                 // Watch-local today; validated against request date
  timeZone: IANA time-zone ID      // Watch-local timezone, validated by TimeZone(identifier:)
  includeOverdue: Bool             // bounded to today + overdue in this slice
  pageCursor: OpaqueCursor?        // adapter-issued continuation only
  limit: 1...25                    // server page and response cap
}

TodoistReadTask {
  id: String
  bucket: dueToday | overdue         // adapter filter phase, never inferred by Gemini
  title: String                    // data; never treated as instructions
  projectID: String?
  priority: 1...4?
  due: { dateTime: String?, date: String?, timeZone: String?, isRecurring: Bool? }?
  deadline: { date: YYYY-MM-DD }?  // date-only hard deadline, not a timed due
  durationMinutes: Int?             // absent means unknown, never zero
}

FindTasksByDateResult {
  tasks: [TodoistReadTask]          // at most 25 per invocation
  fetchedAt: RFC3339 instant
  source: "todoist-v1-live"
  status: success | partial | permissionDenied | unavailable | invalidArguments
  message: String?
  caveats: [String]                // account timezone and deadline-only coverage
  complete: Bool
  nextCursor: OpaqueCursor?
  workload: {
    taskCount: Int
    highPriorityCount: Int
    timedDueCount: Int
    deadlineCount: Int
    knownDurationMinutes: Int
    unknownDurationCount: Int
  }
}
```

Todoist v1 `GET /tasks/filter?query=today` supplies tasks due on the requested local day; `GET /tasks/filter?query=overdue` supplies overdue due dates. The adapter may issue one request for each phase, merges only by stable task ID, and returns an adapter-issued cursor if either phase is truncated. Since the API does not support multiple filter queries in one request, a continuation cursor carries both phase cursors. A deadline is retained as a separate date-only field and is never silently converted into a due time. Deadline-only tasks are not asserted to be covered by Todoist's `today`/`overdue` due filters; the briefing reports this coverage limitation when relevant.

The adapter caps each server request and never claims that one page is the entire backlog. This direct transport has no stale cache: fetchedAt identifies the live response; empty results are distinct from partial/unavailable/permission-denied results. Task titles are length-bounded and descriptions/comments are not sent to Gemini.

## Gemini tool boundary

Only Gemini may use the tool loop. The locally versioned allowlist contains one tool, `tasks.findByDate`, with exactly the request fields above; unknown fields, malformed dates/time zones, out-of-range limits, oversized cursors, and non-allowlisted IDs are rejected before any network read. The model's requested call is not evidence that a task operation happened.

Each Gemini request preserves the model `functionCall` part and its optional provider call ID, then returns a matching `functionResponse` with the same name and ID. Tool results are structured status/data, not free-form instructions. Task data is explicitly untrusted data in the system instruction.

Initial bounds are three Gemini rounds, six total tool calls, 25 tasks per read, 16 KiB serialized tool-result budget, and one read at a time. Cancellation stops pending/future work; request IDs prevent stale callbacks from updating a newer Watch screen/request.

The app-owned final audit envelope always adds live fetch time, complete/partial coverage, status messages, unknown-duration language, provider caveats, and the no-calendar/no-feasibility boundary. If no Todoist read completes, the app returns a deterministic no-results fallback instead of displaying model-authored task claims.

The briefing is behind a persisted feature flag, default `off`, and is routed only for Gemini. Existing independent Q&A, provider selection, keys, one-tap record/second-tap send UX, accessibility, Read aloud, and lifecycle cancellation remain outside this tool boundary.

## Honest workload language

The tool may count tasks, priorities, timed dues, deadlines, known minutes, and unknown durations. Unknown duration is never treated as zero. With no Calendar/EventKit or availability input in this slice, Gemini may describe workload signals (counts, concentration, missing estimates, due/deadline distinctions, freshness, pagination) but must not claim that work fits, can be scheduled, or is feasible within the day. It must say when data is incomplete, stale, unavailable, permission-denied, or missing duration estimates.

Out of scope: task creation/completion/edit/delete, health access, calendar access, conversational memory/planning sessions, phone authority, planner rewrite, autonomous rescheduling, and any reuse of TodoistToday credentials.
