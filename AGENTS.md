# AGENTS.md — Reclaim Desktop

Context file for AI agents working on this repo. Keep it current as work progresses.

## What this is

Native **SwiftUI macOS** app (macOS 14+) over the **Reclaim.ai** REST API, built
to make **bulk task operations** fast. Single window, multi-select table, bulk
action bar. See `README.md` for the user-facing overview.

## Project status

- **v1 complete and building.** `xcodebuild ... CODE_SIGNING_ALLOWED=NO` succeeds;
  app launches (ad-hoc signed) to the onboarding screen without a stored key.
- **`reclaim-probe` CLI** added for live API testing outside the GUI (see below).
  Networking/models extracted into a `ReclaimKit` SwiftPM library that both the
  app and the probe use — so the probe exercises the exact code the app runs.
- Live end-to-end verification is done via the probe; capture real responses
  there before trusting payload assumptions carried over from `reclaim-sdk`.

## Testing the API live (reclaim-probe)

The probe hits the real API with a live key, **not** sandboxed, so you get
stdout, raw JSON, and precise decode errors — the fast debug loop the GUI can't
give you.

```bash
echo 'your-reclaim-key' > .reclaim-token   # gitignored; or export RECLAIM_TOKEN=...
swift run reclaim-probe whoami             # auth check + user id
swift run reclaim-probe dump-user          # raw JSON of /api/users/current
swift run reclaim-probe dump-tasks         # raw JSON of the task-list request
swift run reclaim-probe list active        # decoded, formatted list
swift run reclaim-probe raw /api/some/path # arbitrary GET
```

Mutating commands require `RECLAIM_PROBE_ALLOW_WRITES=1`:
`complete <ids>`, `priority <P#> <ids>`, `upnext <on|off> <ids>`, `delete <ids>`,
and `req <METHOD> <path> [jsonBody]` (generic — use to probe new endpoints, e.g.
`req PATCH /api/tasks/123 '{"onDeck":true}'`).

**Debugging flow:** if the app errors, reproduce with `dump-user` / `dump-tasks`
to see the raw response and HTTP status; a `.decoding(...)` error means the JSON
shape differs from `ReclaimTask`/`ReclaimUser` — adjust the model to match.

## Conventions

- **No third-party dependencies.** Pure SwiftUI + Foundation + Security. Keep it
  that way unless there's a strong reason.
- **State** lives in `TaskListViewModel` (`@MainActor @Observable`). Views are
  thin; all mutations go through the view model, which reloads after each write.
- **Selection** (`Set<Int>` of task IDs) is owned by `TaskListView`, not the VM.
- **API client** is stateless per token; all methods `async throws`, errors are
  `ReclaimAPIError` (LocalizedError). Batch body = `[{taskId, patch}]`.
- **Enums as raw strings on the model**: `ReclaimTask` stores `priority`/`status`/
  `eventCategory` as `String?` and exposes `*Enum` accessors so an unknown server
  value never breaks list decoding.
- **Durations**: Reclaim uses 15-min chunks. `hours = timeChunksRequired / 4`.
- **Dates**: `DateParsing` handles ISO-8601 with/without fractional seconds and
  date-only. Outgoing dates via `ReclaimAPIClient.isoString`.
- Keychain: service `ai.reclaim.desktop`, account `api-token`.

## Build / verify

```bash
# compile check
xcodebuild -project ReclaimDesktop.xcodeproj -target ReclaimDesktop \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO

# run locally: open in Xcode (⌘R) and pick a team / "Sign to Run Locally",
# or ad-hoc sign the built .app:
codesign --force --sign - \
  --entitlements ReclaimDesktop/ReclaimDesktop.entitlements \
  build/Debug/ReclaimDesktop.app
```

### Install to /Applications + Dock

Not automated in the project; done ad hoc:

```bash
xcodebuild -project ReclaimDesktop.xcodeproj -target ReclaimDesktop \
  -configuration Release build CODE_SIGNING_ALLOWED=NO
rm -rf /Applications/ReclaimDesktop.app
cp -R build/Release/ReclaimDesktop.app /Applications/
codesign --force --deep --sign - \
  --entitlements ReclaimDesktop/ReclaimDesktop.entitlements /Applications/ReclaimDesktop.app
# add to Dock (skip if already present), then: killall Dock
```

Ad-hoc signed (`Signature=adhoc`, no team) — fine for personal local use.

The `.xcodeproj` uses a **file-system-synchronized group** (`objectVersion 77`),
so new files added under `ReclaimDesktop/` are picked up automatically — no
`project.pbxproj` edits needed to add sources.

**Shared code / two build systems:** `Package.swift` defines a `ReclaimKit`
target whose `sources` point at `ReclaimDesktop/Models` +
`Services/ReclaimAPIClient.swift`. Those same files are also compiled into the
app target by the synchronized group. One copy of the source, two builds
(`swift build` for the probe, `xcodebuild` for the app). Consequence: shared
types are `public` (for the probe's module boundary); keep app-only concerns
(SwiftUI, Keychain) out of `Models/` + `ReclaimAPIClient.swift`, and if you add
a shared source file, add it to both the synchronized group (automatic) and the
`ReclaimKit` target's `sources` list in `Package.swift` (manual). App-only files
in that tree are listed in the target's `exclude`.

## Verified API facts (from live probing)

- **User `id` is a UUID string**, not numeric (`ReclaimUser.id: String`). It is
  the value passed as the `user` query param on `GET /api/tasks`. Task `id` *is*
  a numeric Int.
- **The `/api/tasks/batch` endpoint whitelists fields**: `priority`, `due`,
  `snoozeUntil` work; **`onDeck` is silently ignored** (returns 200, no change).
  So **Up Next** (`onDeck`) is set via single-task `PATCH /api/tasks/{id}` —
  `bulkSetUpNext` fans those out concurrently. If adding new bulk fields, verify
  with the probe whether batch honors them before wiring UI.
- Archive (complete) and delete are **eventually-consistent**: an immediate
  refetch returns stale rows. The VM therefore applies complete/delete
  optimistically and skips the auto-refetch for those two (`mutate(reload:)`);
  other mutations optimistic-update then refetch to reconcile.

## Known issues / risks

- **Unofficial API.** `api.app.reclaim.ai` is not a documented public API.
  Endpoints/fields may drift. `fetchTasks` requests all statuses + `instances=false`;
  if the **Completed** tab is empty against a live account, the status-filter
  query params likely need adjusting (verify against a real response first).
- Batch endpoints' success responses are ignored (we refetch). If Reclaim returns
  per-item partial failures in the body, we currently don't surface them.
- No pagination — assumes the task list fits in one response (true for typical
  personal use; revisit if a user has thousands of tasks).
- No app icon asset (`AppIcon` referenced but no asset catalog) — falls back to
  the generic icon. Add an `Assets.xcassets` with an `AppIcon` set.

## Backlog (not yet built)

- Editable **time scheme**, **category**, **color**, and **task splitting**
  (min/max chunk) in `TaskEditView` — model already carries these fields.
- **Menu-bar quick view** popover (v1 chose standard window; the VM is reusable).
- Live **end-to-end verification** against a real account (use `reclaim-probe
  dump-tasks`) to pin down the exact status-filter behavior and confirm the
  `ReclaimTask` fields match real responses.
- Partial-failure reporting for batch operations.
- **App icon** is a neutral placeholder (blue squircle + checkmark) rendered by
  `scripts/make_icon.swift` (AppKit) into `Assets.xcassets/AppIcon.appiconset` via
  `sips`. Deliberately NOT Reclaim's logo (trademark). To change it, edit the
  script (or drop a 1024×1024 PNG) and regenerate the set with `sips`.

## Reference

- API shape derived from `reclaim-sdk` (Python):
  https://github.com/labiso-gmbh/reclaim-sdk
- Key files there: `reclaim_sdk/client.py`, `resources/base.py`,
  `resources/task.py` (batch + planner endpoints), `enums.py`.
