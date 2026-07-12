# Reclaim Desktop

A native macOS app for [Reclaim.ai](https://reclaim.ai) built for **fast bulk task management**. It's a quick, keyboard-friendly window over your Reclaim tasks with the controls the web app offers — optimized for selecting many tasks and completing, deleting, reprioritizing, or rescheduling them in one action.

Built with SwiftUI (macOS 14+), talking directly to the Reclaim REST API.

> [!IMPORTANT]
> **Unofficial project.** Not affiliated with, endorsed by, or supported by
> Reclaim.ai. It uses Reclaim's **undocumented** private API (`api.app.reclaim.ai`),
> which can change or break at any time without notice. Use at your own risk.
> "Reclaim.ai" and its logos are trademarks of their respective owner; this repo
> ships a neutral placeholder icon, not Reclaim's mark. Provided under the MIT
> license with no warranty — see [LICENSE](LICENSE).

## Features

- **Multi-select task table** with Active / Overdue / Completed / All filters, live search, and **click-to-sort columns** (title, priority, due, duration, status).
- **Bulk operations** on any selection:
  - Mark complete (archives the tasks)
  - Delete (permanent, with confirmation)
  - Set priority (P1–P4)
  - Reschedule (set/clear due date)
  - Snooze / defer (Tomorrow, In 2 days, Next week, or a custom date; or clear)
  - Move to / remove from **Up Next** (Reclaim's `onDeck`)
- **Up Next section** — tasks marked Up Next are grouped at the top of the list, like the Reclaim web app, with a ⚡︎ marker.
- **Optimistic updates** — completing/deleting removes rows instantly (no waiting on Reclaim's eventually-consistent archive), reverting if the call fails.
- **Single-task edit** sheet (title, notes, priority, due date, duration) — double-click a row or use the context menu.
- **Right-click context menu** mirroring the bulk actions.
- **Secure key storage** — your Reclaim API key lives in the macOS Keychain, never in a plaintext file.
- **Siri, Spotlight & Shortcuts** — add tasks by voice ("Hey Siri, add a task to Reclaim Desktop" → it asks what), from Spotlight, or in the Shortcuts app, via an App Intent (`AddReclaimTaskIntent`) with optional priority / duration / due date.

## Getting your API key

1. Go to [reclaim.ai](https://reclaim.ai) → **Settings → Developer** (or `app.reclaim.ai/settings/developer`).
2. Create/copy an API key.
3. Launch Reclaim Desktop and paste it into the onboarding screen. You can change it later in **Settings (⌘,)**.

## Building & running

Requires Xcode 16+ (developed against Xcode 26, macOS 14+ deployment target).

```bash
open ReclaimDesktop.xcodeproj
```

Then press **⌘R**. If prompted about code signing, select your team under
**Signing & Capabilities**, or choose *"Sign to Run Locally"* — no paid
developer account is required for local use. The app is sandboxed with only the
**outgoing network** entitlement.

### Command-line build

```bash
# Compile check (no signing)
xcodebuild -project ReclaimDesktop.xcodeproj -target ReclaimDesktop \
  -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

## Siri & Shortcuts

The app registers an **App Intent** (`AddReclaimTaskIntent`) via `AppShortcutsProvider`,
so after launching the app once you can:

- **Siri:** "Hey Siri, add a task to Reclaim Desktop" → Siri asks "What's the task?"
  → dictate it. (Free-form titles can't be captured inline in one phrase — that's
  an App Shortcuts limitation, not a bug — so Siri prompts for the text.)
- **Spotlight:** type "Add Reclaim Task".
- **Shortcuts app:** find "Add Reclaim Task" under the app to build automations,
  set custom phrases, or pass dictated text for a one-shot voice command.

No Siri entitlement or paid developer account is required — App Intents expose to
Siri/Spotlight automatically. The intent reads your key from the Keychain, so the
app must be connected first.

## Testing the API (reclaim-probe)

A command-line tool exercises the Reclaim API with a live key **without** the
GUI — useful for verifying endpoints and debugging responses (real stdout, raw
JSON, exact errors). It shares the app's networking code via the `ReclaimKit`
Swift package, so it tests the same code path the app runs.

```bash
echo 'your-reclaim-key' > .reclaim-token     # gitignored (or: export RECLAIM_TOKEN=...)

swift run reclaim-probe whoami               # verify auth, show user id
swift run reclaim-probe list active          # list tasks (active|overdue|completed|all)
swift run reclaim-probe dump-tasks           # raw JSON of the task-list request
swift run reclaim-probe dump-user            # raw JSON of /api/users/current
```

Mutating commands are gated behind `RECLAIM_PROBE_ALLOW_WRITES=1`:

```bash
RECLAIM_PROBE_ALLOW_WRITES=1 swift run reclaim-probe complete 12345 12346
RECLAIM_PROBE_ALLOW_WRITES=1 swift run reclaim-probe priority P1 12345
RECLAIM_PROBE_ALLOW_WRITES=1 swift run reclaim-probe delete 12345
```

## Building a release (.dmg)

```bash
./scripts/make-dmg.sh              # local build -> dist/ReclaimDesktop-<version>.dmg
NOTARIZE=1 ./scripts/make-dmg.sh   # signed + notarized, runs cleanly on any Mac
```

The plain build signs with whatever identity is available and runs on your own
Mac, but other Macs will show a Gatekeeper warning. For distribution, use
`NOTARIZE=1`, which requires (one-time):

1. A **Developer ID Application** certificate — Xcode → Settings → Accounts →
   Manage Certificates → + → *Developer ID Application*.
2. A stored notary credential profile named `reclaim-notary`:
   ```bash
   xcrun notarytool store-credentials       # interactive; name it "reclaim-notary"
   ```
   (Use an App Store Connect API key, or your Apple ID + app-specific password +
   team id.) Override the name with `NOTARY_PROFILE=<name>`.

`NOTARIZE=1` then signs (hardened runtime + timestamp), submits to Apple, waits,
staples the ticket, and validates.

## Architecture

```
Package.swift                    SwiftPM: ReclaimKit lib + reclaim-probe CLI
Sources/reclaim-probe/           Command-line API tester (see above)
ReclaimDesktop/
├── ReclaimDesktopApp.swift      App entry (WindowGroup + Settings scene)
├── Models/
│   ├── ReclaimTask.swift        Task model + derived state (overdue, duration…)
│   ├── User.swift               Current-user model
│   └── Enums.swift              Priority / TaskStatus / EventCategory
├── Services/
│   ├── KeychainStore.swift      Token storage in the macOS Keychain
│   └── ReclaimAPIClient.swift   Async REST client (incl. batch endpoints)
├── ViewModels/
│   └── TaskListViewModel.swift  @Observable app state + all operations
└── Views/
    ├── ContentView.swift        Routes onboarding vs. task list
    ├── OnboardingView.swift     First-run API-key entry
    ├── TaskListView.swift       Filter bar, table, status bar, toolbar
    ├── BulkActionBar.swift      The bulk-operations toolbar
    ├── TaskEditView.swift       Single-task edit sheet
    ├── SettingsView.swift       Manage key / account
    └── Formatting.swift         Date & duration formatters
```

### API surface used

Base URL `https://api.app.reclaim.ai`, `Authorization: Bearer <key>`.

| Operation | Endpoint |
|---|---|
| Current user | `GET /api/users/current` |
| List tasks | `GET /api/tasks?user={id}` |
| Bulk complete | `PATCH /api/tasks/batch/archive` |
| Bulk delete | `DELETE /api/tasks/batch` |
| Bulk patch (priority/due/snooze) | `PATCH /api/tasks/batch` |
| Edit one task | `PATCH /api/tasks/{id}` |
| Complete / reopen one | `POST /api/planner/done\|unarchive/task/{id}` |

Batch endpoints take a body of `[{ "taskId": <int>, "patch": { … } }]`.
Durations are stored as 15-minute "chunks" (`timeChunksRequired = hours × 4`).

The API shape was derived from the community
[`reclaim-sdk`](https://github.com/labiso-gmbh/reclaim-sdk) Python library.

## Notes & limitations

- Reclaim does not publish an official public API; endpoints may change.
- "Complete" archives a task (Reclaim's notion of truly done). Reopen via the
  row context menu on the **Completed** filter.
- Time schemes, task splitting (min/max chunks), categories, and colors are read
  but not yet editable in the UI — see [AGENTS.md](AGENTS.md) for the backlog.
