# Week digest contract (Watch side)

Status: implemented 2026-11-14. The digest itself comes from the Todoist-Apple-Calendar repo (`--week-digest`); its README has the full v1 shape.

## Fields the Watch reads

| Field | Use |
| --- | --- |
| `v` | Must be `1`; anything else is "format not supported" |
| `generatedAt` | Shown in the footer in the Watch's zone; older than 3 h means stale |
| `tz`, `hours` | Context line |
| `overdue[]`, `overdueMore` | `t`, `p`, `due` |
| `days[]` | `date`, `tasks[]` (`t`, `p`, `at?`, `min?`, `rec?`), `busy[[HH:MM, HH:MM]]`, `freeMin`, `more?` |
| `busySources` | Calendars that answered |
| `busyExpected?`, `complete?`, `caveats?` | Optional and decoded leniently. `busyExpected > busySources` means "N calendar(s) could not be read", so the Watch says "busy time unknown", never "no meetings". `complete == false` is stale. |

## Statuses

| Situation | What the owner sees |
| --- | --- |
| 200, v1, fresh | The answer, with the footer `Week digest · N tasks · K calendars · built HH:mm` |
| 200 but stale (> 3 h old) or `complete: false` | The answer; footer adds `· stale`; the prompt says calendar data may be out of date |
| 401 / 403 | Falls back to Todoist; footer note `week digest secret rejected` |
| Other HTTP status, network error, host mismatch | Falls back to Todoist; `week digest unavailable` |
| `v != 1`, undecodable, over 32 KiB | Falls back to Todoist; `week digest format not supported` |
| Cancelled | The briefing is cancelled; no fallback read |

## Bounds and privacy

- GET only: 8 s timeout, at most 32 KiB, HTTPS only, no redirects. The bearer secret is sent only to the configured host.
- The host and secret live only in the Watch Keychain. They never appear in UserDefaults, logs, prompts or footers.
- Gemini only: the digest is task and calendar data. Calendar **event titles are never in it** (free/busy only); task titles are, and the prompt says they are data, not instructions.
- Exactly one model call per question, in every branch (week or day, with or without the digest). Harness tests check this.
