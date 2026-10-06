# Reclaim task API: 1.0 → 2.0 migration guide for agents

For any agent or script that creates or updates Reclaim tasks by calling
`https://api.app.reclaim.ai`. Reclaim moved this account to a new task backend. If
you are still writing to the old `/api/tasks` endpoints, your tasks no longer reach
the Reclaim web app, the scheduler, or Reclaim's assistant. Move your writes to
`/api/reclaim-tasks`.

## Why this matters

There are now two task stores behind the same host and the same key:

- `/api/tasks` (call it 1.0) — the old store. Still responds, but Reclaim's product no longer reads it. Anything you create here is invisible on the website and never gets scheduled.
- `/api/reclaim-tasks` (2.0) — the live store the website, scheduler, and Reclaim MCP use.

They have **disjoint id spaces** and do not sync. A task you create in one does not
appear in the other. So this is not a transparent upgrade; you must change the
endpoint and the request shape.

## Auth (unchanged)

Same personal API key, same header, same host. The 2.0 endpoints accept it.

```
Authorization: Bearer <RECLAIM_API_KEY>
Content-Type: application/json
Host: https://api.app.reclaim.ai
```

## Endpoint mapping

| What you do | 1.0 (stop using) | 2.0 (use this) |
|---|---|---|
| Create a task | `POST /api/tasks` | `POST /api/reclaim-tasks` |
| Get one task | `GET /api/tasks/{id}` | `GET /api/reclaim-tasks/{numericId}` |
| Update a task | `PATCH /api/tasks/{id}` | `PATCH /api/reclaim-tasks/{numericId}` |
| Mark complete | `POST /api/planner/done/task/{id}` | `PATCH /api/reclaim-tasks/{numericId}` with `{"completed": true}` |
| Reopen | `POST /api/planner/unarchive/task/{id}` | `PATCH /api/reclaim-tasks/{numericId}` with `{"completed": false}` |
| Delete | `DELETE /api/tasks/{id}` | `DELETE /api/reclaim-tasks/{numericId}` |
| List open tasks | `GET /api/tasks?...` | `GET /api/reclaim-tasks/page?completed=false&count=200` |
| Search | — | `GET /api/reclaim-tasks?query=<text>&completed=false` |
| Set Up Next | `PATCH .../{id}` `{"onDeck": true}` | `PATCH .../{numericId}` `{"priority": "PRIORITIZE"}` (see gotchas) |
| Snooze / defer | `POST /api/planner/task/{id}/snooze` | `PATCH .../{numericId}` `{"startDate": "YYYY-MM-DD"}` |

The `/api/planner/*` routes return 404 on a 2.0 task. Do not call them for 2.0 ids.

## Task ids

A 2.0 task's `id` in a response body is the compound string `"RECLAIM:<n>"` (e.g.
`"RECLAIM:187908"`). **Path parameters use only the numeric part.** To update task
`"RECLAIM:187908"`, call `PATCH /api/reclaim-tasks/187908`. Strip the `RECLAIM:`
prefix before building the URL.

## Creating a task: field-by-field

Most agents only create tasks. Here is the whole create contract.

`POST /api/reclaim-tasks`, body `CreateReclaimTaskRequest`:

| Field | Type | Notes |
|---|---|---|
| `title` | string | **required** |
| `description` | string? | the notes/body of the task (this replaces 1.0 `notes`) |
| `priority` | string? | `P1` \| `P2` \| `P3` \| `P4` \| `PRIORITIZE` \| `DEFAULT`. Omit or `DEFAULT` to let Reclaim rank it. |
| `estimateMinutes` | int? | duration in **minutes** (not 15-minute chunks) |
| `dueDate` | string? | **date only**, `YYYY-MM-DD` |
| `startDate` | string? | **date only**, `YYYY-MM-DD`; "don't start before" |

Returns `201` with the full task (`id`, `title`, `description`, `priority`,
`status`, `due`, `start`, `completed`, `estimateMinutes`, `extendedProperties`,
`sortOrder`, `type`).

### Field translation from your 1.0 create

| 1.0 field you send today | 2.0 field | Conversion |
|---|---|---|
| `title` | `title` | 1:1 |
| `notes` | `description` | rename |
| `priority` (`P1`–`P4`) | `priority` | 1:1 (Critical=P1, High=P2, Medium=P3, Low=P4) |
| `timeChunksRequired` | `estimateMinutes` | **× 15** (chunks are 15 min; `4 chunks → 60`) |
| `minChunkSize` / `maxChunkSize` | — | drop; 2.0 create has no chunk splitting |
| `due` (ISO datetime) | `dueDate` | take the **calendar date only**, `YYYY-MM-DD` |
| `onDeck: true` | `priority: "PRIORITIZE"` | see gotchas; it replaces the P-level |
| `snoozeUntil` | `startDate` | calendar date only |
| `eventCategory` / `status` | — | drop; not part of the 2.0 create body |

### Example

1.0 request you send now:

```json
POST /api/tasks
{
  "title": "Draft the Q3 board deck",
  "notes": "Pull metrics from the data warehouse first.",
  "eventCategory": "WORK",
  "priority": "P2",
  "status": "NEW",
  "timeChunksRequired": 8,
  "minChunkSize": 2,
  "maxChunkSize": 8
}
```

2.0 equivalent:

```json
POST /api/reclaim-tasks
{
  "title": "Draft the Q3 board deck",
  "description": "Pull metrics from the data warehouse first.",
  "priority": "P2",
  "estimateMinutes": 120
}
```

## Behavior gotchas (verified against the live API)

- **Do not set a due date unless the user actually gave a deadline.** A due date overrides Reclaim's priority-based scheduling. Default to no `dueDate`. Only send one when the source text states a real deadline, and then send the intended calendar date, not "today + N" as a reflex.
- **Up Next is a priority value, and it overwrites the level.** Setting `priority: "PRIORITIZE"` moves the task to Up Next but the task comes back with `priority: "PRIORITIZE"`, not its former `P2`. Up Next and a P1–P4 level are mutually exclusive. Decide which you want; you cannot have both.
- **`dueDate` and `startDate` are date-only on write.** Send `YYYY-MM-DD`. Responses echo a full datetime (`due`, `start`). Do **not** feed a server-returned `due` datetime back into a later `dueDate` field; it has been observed to drift the deadline by a day. Keep your own calendar-date value and resend that.
- **Duration is minutes.** `estimateMinutes: 30`, not chunks. If you were computing chunks, send `chunks * 15`.
- **No batch endpoint.** 2.0 has no `/batch`. To act on many tasks, send one request each (fan out concurrently if you need speed).
- **Complete/reopen is a field patch,** not a planner call: `PATCH .../{numericId}` with `{"completed": true|false}`.
- **No `onDeck`, `atRisk`, `eventCategory`, `eventColor`, `timeSchemeId`, or chunk splitting on the 2.0 task object.** If your flow depends on those, they do not round-trip here.

## Listing and verifying

To list, page through:

```
GET /api/reclaim-tasks/page?completed=false&count=200
```

Response envelope: `{ first, last, count, hasNextPage, items: [ReclaimTask], totalCount }`.
For more than one page, pass the previous `last` value as `after`. Useful filters:
`query`, `overdue=true`, `dueBefore`/`dueAfter` (dates), `hasDuration=true`,
`sort` (e.g. `DUE_DATE`), `order`.

Confirm a write landed in the live store: `GET /api/reclaim-tasks/{numericId}` should
return it, and it should now appear in the Reclaim web app. If you create a task and it
shows up in your script but not on the website, you wrote to 1.0 by mistake.

## Checklist for updating an agent

1. Change the create path from `/api/tasks` to `/api/reclaim-tasks`.
2. Rename `notes → description`; convert `timeChunksRequired → estimateMinutes` (× 15); drop `eventCategory`, `status`, `minChunkSize`, `maxChunkSize`.
3. Keep `priority` as `P1`–`P4`. Map any "Up Next" intent to `priority: "PRIORITIZE"` and accept that it replaces the level.
4. Only send `dueDate` when there is a real deadline, as `YYYY-MM-DD`.
5. For updates/complete/delete, switch to `PATCH`/`DELETE /api/reclaim-tasks/{numericId}` using the numeric id (strip `RECLAIM:`).
6. Drop every `/api/planner/*` and `/api/tasks/batch*` call; they do not apply to 2.0.
7. Verify a created task appears on the Reclaim website before trusting the flow.

---
<sub>Created by Claude Code session `8d4b10ef-43df-449a-acac-9604ded2a199` · Last updated by session `8d4b10ef-43df-449a-acac-9604ded2a199`</sub>
