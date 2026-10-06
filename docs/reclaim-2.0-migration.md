# Reclaim 1.0 → 2.0: contract, sync, and app mode toggle

Planning doc for moving the desktop and iOS apps off the legacy `/api/tasks`
surface and onto Reclaim's current `/api/reclaim-tasks` ("2.0") surface, with a
one-time migration, an optional ongoing sync, and a per-app mode toggle.

## Why this exists

Reclaim migrated this account to a new task backend around July 2026. The website,
scheduler, and Reclaim's own MCP tools now read `/api/reclaim-tasks`; the apps still
read and write `/api/tasks`. The two stores have disjoint numeric id spaces and have
fully diverged: of 97 active tasks in 1.0 (updated through today), 96 have no 2.0
counterpart, and the 43 tasks the website shows are a frozen July–September snapshot.
So everything the apps have captured since the cutover went to a store Reclaim's
product no longer reads. That is the out-of-sync.

Good news on groundwork: Reclaim publishes a full OpenAPI 3.0.1 spec at
`GET https://api.app.reclaim.ai/swagger/reclaim-api-0.1.yml` (reachable with the
personal Bearer key, 553 paths), and it documents both task systems. "0.1" is
Reclaim's version string for the whole API, not our 1.0/2.0 split. Everything below
is pulled from that spec and confirmed against live read probes.

## The 2.0 task contract (from the spec)

Base URL `https://api.app.reclaim.ai`, same Bearer key the apps already use. The key
authenticates against `/api/reclaim-tasks` (verified: GET and POST return 200).

Endpoints:

| Method | Path | Request | Response |
|---|---|---|---|
| GET | `/api/reclaim-tasks` | query params `query`, `completed` | `ReclaimTask[]` |
| POST | `/api/reclaim-tasks` | `CreateReclaimTaskRequest` | `ReclaimTask` |
| GET | `/api/reclaim-tasks/page` | `query, sort, relativeDue, completed, dueBefore, dueAfter, overdue, hasDuration, after` (cursor), `order, count` | `Page_ReclaimTaskView_` |
| GET | `/api/reclaim-tasks/{id}` | path `id` is the **integer** (the numeric part of `RECLAIM:<n>`) | `ReclaimTask` |
| PATCH | `/api/reclaim-tasks/{id}` | `UpdateReclaimTaskRequest` | `ReclaimTask` |
| DELETE | `/api/reclaim-tasks/{id}` | — | — |
| PATCH | `/api/reclaim-tasks/{id}/reindex` | reorder via `sortOrder` | — |

Schemas:

- `CreateReclaimTaskRequest` — `title` (required), `description?`, `dueDate?` (date `yyyy-MM-dd`), `startDate?` (date), `estimateMinutes?` (int), `priority?` (`PriorityLevel`). No `extendedProperties`.
- `UpdateReclaimTaskRequest` — all optional: `title?`, `description?`, `dueDate?`, `startDate?`, `completed?` (bool), `estimateMinutes?`, `priority?`. Partial patch. `completed` is how you mark done / reopen. No `extendedProperties`.
- `ReclaimTask` (response) — `id` (`"RECLAIM:<n>"`), `title`, `description?`, `priority?`, `status?` (`open`/`completed`), `link?`, `due?` (date-time), `start?` (date-time), `completed` (bool), `estimateMinutes?` (int), `extendedProperties` (object, read-only arbitrary keys; currently only `{"eventType":"WORK"}`), `sortOrder` (double), `type`.
- `PriorityLevel` enum — `P1, P2, P3, P4, PRIORITIZE, DEFAULT`.
- `Page_ReclaimTaskView_` — `{ first, last, order, count, hasNextPage, items: ReclaimTask[], totalCount }`.

Request dates are date-only (`yyyy-MM-dd`); responses are full date-time. The spec's
own notes and the DevTools capture both warn of a one-day due drift when echoing a
server `due` back into a request, so always send a fresh local-noon value for the
intended calendar date rather than round-tripping the server timestamp.

Related surfaces the spec documents and we may need later:

- `GET /api/interactions/task/{compoundKey}` — returns the task as a `GtdTask` addressed by `RECLAIM:<n>`. Verified 200. This is the GTD/planner view of a 2.0 task.
- `GET /api/recommended-tasks`, `/groups`, `/count`, `PATCH /api/recommended-tasks/{id}/status` — the proactive engine (`RecommendedTask`: meeting-sourced suggestions with `transcriptSnippet`). Backs "suggested tasks". Not the same as a per-task at-risk flag.
- `GET /api/changelog/tasks?taskIds=...` — per-task change history (`ChangeLogEntryView`). Takes explicit ids; it is **not** a global "what changed since" feed. Returned 400 without `taskIds`.

## 1.0 ↔ 2.0 field mapping

The `Task` (1.0) schema carries `onDeck, snoozeUntil, priority, index, timeChunksRequired, atRisk, eventCategory, eventColor, timeSchemeId`. The 2.0 `ReclaimTask` is flatter. The mapping:

| Concept | 1.0 `Task` | 2.0 `ReclaimTask` | Notes |
|---|---|---|---|
| id | `Int` | `"RECLAIM:<Int>"` | **disjoint id spaces**; needs a local map |
| title | `title` | `title` | 1:1 |
| notes | `notes` | `description` | rename |
| duration | `timeChunksRequired` × 15 min | `estimateMinutes` | `minutes = chunks × 15`; no chunk-splitting in 2.0 |
| priority | `priority` (P1–P4) | `priority` (P1–P4) | 1:1 for the four levels |
| Up Next | `onDeck` (bool) | `priority = PRIORITIZE` | **lossy, confirmed**: PRIORITIZE replaces the P-level (mutually exclusive) |
| due | `due` (date-time) | `due` / set via `dueDate` (date) | date-only on write |
| snooze | `snoozeUntil` (date-time) | `startDate` → `start` ("don't start before") | confirmed: sets `start`; functional stand-in, not a true snooze |
| done | `status` enum + `finished` | `completed` (bool) + `status` `open`/`completed` | |
| ordering | `index` | `sortOrder` | |
| at-risk | `atRisk` (bool) | not on the task | drop in 2.0 mode, or source from a separate engine call |
| category/color/scheme | `eventCategory`/`eventColor`/`timeSchemeId` | `extendedProperties.eventType` only | mostly not representable |

Two cells are lossy enough to call out in the UI: Up Next collapses into the priority
field, and snooze has no real home. Category, color, time scheme, chunk splitting, and
the at-risk flag have no 2.0 task-level equivalent.

## Resolved by live probe

Verified against a disposable task (created, probed, deleted; final GET returned 404):

1. `PATCH priority: PRIORITIZE` **overwrites** the P-level. A task set to PRIORITIZE reads back `priority: "PRIORITIZE"`, not its prior P2. Up Next and a P1–P4 level are mutually exclusive in 2.0, so switching a task to Up Next loses its priority level and vice-versa. The UI must treat them as one control.
2. The 1.0 planner actions are **1.0-only**. `POST /api/planner/prioritize|start|stop/task/{id}` with a 2.0 numeric id all return 404. 2.0 task lifecycle is CRUD on `/api/reclaim-tasks` plus the `/api/interactions` layer; the `/api/planner/*` routes do not apply.
3. There is no simple timer start/stop for 2.0 tasks. Because the planner routes 404, Start/Stop Working must go through `/api/interactions` (`StartTaskRequest`, needs session `notificationKey`/`viewId` per the DevTools capture). Heavier; out of scope for a first 2.0 mode.
4. `startDate` works as the snooze stand-in. `PATCH startDate: 2026-10-20` set `start` to `2026-10-20T00:00:00-07:00` (local midnight). It defers "don't start before", which is close enough to snooze to relabel.

## Part A — Unidirectional migration (fixes today's pain, standalone)

Goal: get the account's real current tasks (the ~96 active-1.0-only tasks) into Reclaim
2.0 so the website and scheduler have them. This is a scripted one-shot, not app work,
and does not depend on the open probes.

Steps:

1. Pull 1.0 active tasks (`status in {NEW, SCHEDULED, IN_PROGRESS}`) via the existing probe/client.
2. Pull the full 2.0 set (`/api/reclaim-tasks/page`, walk the cursor).
3. Compute the orphan set: 1.0 active tasks with no 2.0 title match. Keep the match loose (normalized title) and review it by hand; this is a one-time human-checked list, not an automated merge.
4. Emit a dry-run: for each orphan, the `CreateReclaimTaskRequest` that would be sent (title, description from notes, priority, `estimateMinutes = chunks × 15`, `dueDate` as local-noon of the intended date, `startDate` from `snoozeUntil` if set). Present it; create nothing yet.
5. On explicit confirmation, `POST /api/reclaim-tasks` each one. Record `(v1Id → v2Id)` in a local map file as you go, so a re-run is idempotent and so Part B can start from a known mapping.
6. Do **not** delete or archive anything in 1.0. It is currently the only copy of those 96 tasks until the user confirms 2.0 looks right.

Deliverable: a `migrate` subcommand on `reclaim-probe` (it already has create/list and
the token plumbing), with `--dry-run` default and an explicit `--apply`.

## Part B — Bidirectional sync (larger, depends on probes)

Only needed if the user wants to keep using the apps on 1.0 while the website stays on
2.0, rather than switching the apps over. Constraints discovered:

- No `updatedAt` on `ReclaimTask` and no global change feed, so change detection on the 2.0 side is **snapshot diff** against a last-seen copy. A diff detects add / remove / field change; it cannot order two conflicting edits.
- Conflict policy must therefore be a fixed rule, not a timestamp merge. Default proposal: last-writer by poll is impossible, so pick a side — "2.0 wins" (treat Reclaim's product as source of truth) is the least surprising, with 1.0-only changes pushed up and 2.0 changes pulled down, and a logged conflict when the same mapped task changed on both sides since last sync.
- Identity map must be local and durable. `extendedProperties` is read-only on 2.0, so we cannot stash `v1Id` on the 2.0 task. Keep a `{v1Id, v2Id, lastSyncedHash}` table. It is per-device (App Group does not cross devices); either accept per-device maps and reconcile by content once, or put the map in iCloud key-value / CloudKit so desktop and iOS share it.
- Lossy fields do not survive a round trip: onDeck↔PRIORITIZE, snooze↔startDate, category/color/scheme, chunk splitting, at-risk. Sync only the fields that map cleanly (title, notes/description, priority P1–P4, due, duration, completed) and leave the lossy ones one-directional or out of scope.

This is weeks of work and should not block Parts A and C. Recommend deferring until
after the toggle ships and we see whether the user even wants to keep 1.0 alive.

## Part C — 1.0 / 2.0 mode toggle (desktop + iOS)

A setting that points the app at either task surface. Design:

- **Adapter, not dual models.** Keep the existing `ReclaimTask` (Int id) view model and UI. Add a 2.0 client that maps `ReclaimTask` (2.0) → the existing model: parse the numeric id out of `RECLAIM:<n>`, `estimateMinutes → timeChunksRequired/4`, `description → notes`, `completed/status` → status, `priority == PRIORITIZE → onDeck = true` (and show the underlying level per the probe result). The UI stays unchanged; only the client swaps.
- **Where the mode lives.** A `ReclaimMode` (`.v1` / `.v2`) on the client in `ReclaimKit`, selected by an `@AppStorage("reclaimMode")` setting. The client chooses base paths and the encode/decode adapter from the mode. Both apps share `ReclaimKit`, so this is written once.
- **Feature degradation in 2.0 mode, surfaced honestly in the UI:**
  - Up Next: write `priority: PRIORITIZE`; the `N` shortcut and the bulk bar map to it. It **replaces** the P-level (confirmed), so the priority picker and the Up Next toggle become one control: show PRIORITIZE as a fifth priority option, and warn that toggling Up Next clears P1–P4.
  - Snooze: becomes "set start date" (`startDate` → `start`, confirmed). Relabel the snooze action as "Start no earlier than".
  - Start / Stop Working (timers): hidden in 2.0 mode. The 1.0 planner routes 404 on 2.0 ids; real timers need the `/api/interactions` session flow, which is a later project.
  - At-risk indicator: hidden in 2.0 mode (no task field), unless we add a background `recommended-tasks` / at-risk fetch later.
  - Category / color / time scheme / chunk splitting: hidden in 2.0 mode.
  - Complete / reopen: `PATCH completed`. Create: `POST /api/reclaim-tasks`. Delete: `DELETE`. Bulk ops: fan out single-task calls (no batch endpoint on 2.0; same pattern we already use for onDeck on 1.0).
- **Per-account vs per-install hazard.** The mode is per app install, but the underlying data question is per account. If desktop flips to 2.0 and iOS stays on 1.0, we recreate today's split across our own two apps. The toggle should move both apps together (store the mode where both read it, e.g. iCloud KVS), or Part B's sync must run regardless of mode. Decide before shipping the toggle; leaning toward "shared setting, both apps switch together."

## Recommended sequencing

1. ~~Run the write-probes to finalize the mapping.~~ Done (see "Resolved by live probe").
2. Ship Part A migration as a probe subcommand; dry-run, user-reviews, apply. This re-syncs the website today.
3. Ship Part C toggle in 2.0 mode as the forward fix, so the apps stop writing to the dead store. Default the setting to move both apps together.
4. Revisit Part B only if the user wants to keep 1.0 alive alongside 2.0.

---
<sub>Created by Claude Code session `8d4b10ef-43df-449a-acac-9604ded2a199` · Last updated by session `8d4b10ef-43df-449a-acac-9604ded2a199`</sub>
