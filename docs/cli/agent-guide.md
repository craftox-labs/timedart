# timedart CLI — agent usage guide

A command-line **peer of the timedart desktop app**: it operates on the *same*
local SQLite database, so a timer started in the GUI can be stopped from the
CLI and vice-versa. Designed to be driven by an LLM/agent — every command has a
`--json` mode with a stable shape and a documented exit code.

- **Binary:** `timedart` (see [Build](#build)). Invoke as `timedart <command> …`.
- **Read model:** every invocation opens its own DB connection, so **CLI reads
  are always fresh**. All writes go through the app's data layer (never raw
  tables), so business rules match the GUI exactly.
- **Schema lock:** the binary speaks one DB schema version and **refuses** a DB
  at any other version (it never migrates). Check with `timedart --version`.
- **Self-onboarding:** this guide is bundled into the binary itself — no
  external doc path to locate, and it can't drift out of version with the CLI
  you're holding. An agent's entire bootstrap is one of:
  - `timedart guide` — prints this exact file to stdout (prose, for a human or
    an agent that reads markdown).
  - `timedart help --json` — a machine-readable manifest of every command, its
    options and the exit-code table, walked live from the CLI's own argument
    parser (for an agent doing programmatic capability introspection).
  Both work with no database present.

## Global flags

| Flag | Meaning |
| --- | --- |
| `-j, --json` | Emit machine-readable JSON instead of human text. Put it before or after the verb. |
| `--db <path>` | Use this database. A file path, or a directory (→ `<dir>/timedart.sqlite`). Overrides `TIMEDART_DB` and the default. |
| `--version` | Print CLI version, DB schema version, sync-awareness. Exit 0. |
| `-h`, `--help` | Usage. Also `timedart <command> --help`. |

**Abbreviations (CLI-wide).** One reserved single-char abbreviation per concept,
applied consistently on every verb that carries the flag: `--json`→`-j`
(global), `--project`→`-p`, `--client`→`-c`, `--task`→`-t`, `--name`→`-n`,
`--rate`→`-r`, `--description`→`-d`, `--duration`→`-D`, `--force`→`-f`,
`--title`→`-T`, `--code`→`-C`. Where a fundamental flag and a related one share
an initial, the fundamental one stays lowercase and its partner takes the
capital (`-c` client / `-C` code, `-t` task / `-T` title, `-d` description /
`-D` duration). Client detail flags (`--contact --email --phone --address
--abn`) stay long-form only — low-frequency enough that single letters would
be cryptic. `timedart <verb> --help` shows each verb's abbreviations and a
worked example; `timedart --help` carries this exit-code/selector/duration
summary as its footer.

**DB location (when `--db` / `TIMEDART_DB` are unset)** — the same file the GUI
uses:

| OS | Path |
| --- | --- |
| Linux | `$XDG_DATA_HOME/timedart/timedart.sqlite` (default `~/.local/share/timedart/timedart.sqlite`) |
| macOS | `~/Library/Application Support/timedart/timedart.sqlite` |
| Windows | `%APPDATA%\timedart\timedart.sqlite` |

**Selectors (id-or-name).** `--project` / `--task` accept either a stable UUID
or an exact human name:

- project → matches a UUID, then the exact project **code**, then the exact
  **title**.
- task → matches a UUID, then the exact **title**, scoped to the chosen project.
- client → matches a UUID, then the exact **name** (clients have no code).
- Only **live** (non-deleted) entities are selectable. No match → exit `5`
  (unknownEntity); more than one name match → exit `6` (ambiguousEntity). For
  unambiguous scripting, prefer UUIDs (get them from `list`).

The **mutate verbs** (`client`/`project`/`task` — see [Managing
entities](#managing-entities)) take the target as a **positional** `<id|name>`
argument (`timedart project edit ACME --title …`); quote names containing
spaces. `--json` works on every verb.

## Exit codes

| Code | Name | Meaning |
| --- | --- | --- |
| 0 | success | Command completed. |
| 2 | usage | Bad command line: unknown verb/flag, missing required arg, unparseable `--duration`/`--at`. |
| 3 | schemaMismatch | DB schema version ≠ this binary's. It will not migrate. |
| 4 | dbNotFound | No database file at the resolved/`--db` path. |
| 5 | unknownEntity | A `--project`/`--task` selector matched nothing live. |
| 6 | ambiguousEntity | A name matched more than one live entity — disambiguate with a UUID. |
| 7 | noTimerRunning | `stop`/`pause`/`resume` with no active timer. |
| 8 | timerAlreadyRunning | `start` while a timer is active, `resume` while already running, or a `delete` targeting the entity the running timer is bound to. |
| 9 | timerAlreadyPaused | `pause` while already paused. |
| 10 | confirmationRequired | A cascade `delete` was run without `--force`. The impact count was printed; nothing changed. |
| 11 | constraintViolation | A create/edit was rejected by a DB constraint (e.g. a project `code` already in use). |

Human-readable errors go to **stderr**; JSON/data goes to **stdout**.

## Errors

Every failure routed through the dispatcher (a `CliException` — e.g.
`unknownEntity`, `constraintViolation` — or a usage error from the arg
parser) is rendered by one shared function, so the shape below is guaranteed
regardless of which verb failed.

**Without `--json`**: unchanged plain text on stderr — `error: <message>`
(usage errors additionally print the command's usage block).

**With `--json`**: a single JSON object on **stderr** (stdout is never
touched on failure — it carries only success data):

```json
{ "error": { "code": 5, "name": "unknownEntity", "message": "No live project matches \"Ghost\"." } }
```

- `code` — the process exit code (matches the [Exit codes](#exit-codes)
  table above).
- `name` — the `CliExit` symbol for that code (`"success"`, `"usage"`,
  `"unknownEntity"`, …).
- `message` — the same human-readable text the non-JSON path prints.

A usage error (unknown verb/flag, missing required arg) follows the same
contract — `code: 2, name: "usage"` — as long as `--json`/`-j` appears
anywhere on the command line, even if the rest of it fails to parse.

## Commands

### `timer status`
Show the currently-running (or paused) timer with live-derived elapsed time.
Read-only.

```
timedart timer status
timedart timer status --json --db /tmp/scratch.sqlite
```

JSON — running (`status`: `"running"` | `"paused"` | `"idle"`):

```json
{
  "status": "running",
  "running": true,
  "elapsedSeconds": 3,
  "project": { "id": "019f…c9", "code": "ACME", "title": "Acme Website" },
  "task": { "id": "019f…6d", "title": "Design" },
  "description": "hero",
  "startedAt": "2026-07-18T19:16:23.000"
}
```

JSON — idle:

```json
{
  "status": "idle",
  "running": false,
  "elapsedSeconds": 0,
  "project": null,
  "task": null,
  "description": null,
  "startedAt": null
}
```

### `timer start`
Start a timer against a project and task. Fails (`8`) if a timer is already
active. **All time in timedart is task-level** (matching the GUI and `log`) —
project-only timing is unsupported, so `--task` is required.

| Arg | Req | Notes |
| --- | --- | --- |
| `-p, --project <id\|name>` | yes | Project to track. |
| `-t, --task <id\|name>` | **yes** | Task within that project. |
| `-d, --description <text>` | no | Session note; becomes the recorded entry's description on `stop`. |

```
timedart timer start -p ACME -t Design -d "hero section"
```

Output shape is the same as `timer status` (the now-running timer).

### `timer stop`
Finish the running timer and record a `TimeEntry`. Fails (`7`) if none running.

```
timedart timer stop --json
```

```json
{
  "stopped": true,
  "recorded": true,
  "entry": {
    "seconds": 6,
    "project": { "id": "019f…c9", "code": "ACME", "title": "Acme Website" },
    "task": { "id": "019f…6d", "title": "Design" },
    "description": "hero",
    "startedAt": "2026-07-18T19:16:23.000",
    "endedAt": "2026-07-18T19:16:29.779"
  }
}
```

`recorded` is `false` (and `entry` is `null`) only on the zero-elapsed edge case
(a task is always bound). The timer is cleared either way.

### `timer discard`
Abandon the running (or paused) timer **without recording an entry** — the
elapsed time is thrown away. Use it for a mistaken session. Fails (`7`) if none
running. Output is the resulting idle `timer status`.

```
timedart timer discard --json
```

### `timer edit`
Change the **live** timer in place — its session note and/or its project/task
binding — without recording an entry or resetting the elapsed clock. Only the
flags you pass change; fails (`7`) if none running. Output shape matches
`timer status`.

- `-d, --description` — new note; pass `-d ""` to clear it.
- `-t, --task` — rebind to another task (a UUID or exact title, scoped by
  `-p`). The project is set to that task's project — rebinding is task-level.
- `-p, --project` — scopes `--task` resolution; only meaningful with `--task`.

Editing must ask for something to change (a `--description` and/or `--task`),
else it fails `2` (usage) rather than silently re-stamping the row.

```
timedart timer edit -d "hero section, take 2"
timedart timer edit -t "Design" -p ACME --json
```

### `timer pause` / `timer resume`
Pause freezes elapsed; resume continues it. `pause` fails `7` (none) / `9`
(already paused); `resume` fails `7` (none) / `8` (already running). Output
shape matches `timer status`.

```
timedart timer pause
timedart timer resume
```

### `list clients`
All live clients, name-ordered, each with the default rate its projects inherit.

```
timedart list clients --json
```

```json
[
  {
    "id": "019f…a6",
    "name": "Acme Co",
    "defaultRate": 100,
    "contactName": null,
    "email": null,
    "phone": null,
    "address": null,
    "abn": null,
    "archived": false
  }
]
```

### `list projects`
All live projects, title-ordered.

```
timedart list projects --json
```

```json
[
  {
    "id": "019f…c9",
    "code": "ACME",
    "title": "Acme Website",
    "clientId": "019f…a6",
    "clientName": "Acme Co",
    "rate": null,
    "archived": false
  }
]
```

### `list tasks`
Live tasks, title-ordered. Optionally scope to one project.

| Arg | Req | Notes |
| --- | --- | --- |
| `-p, --project <id\|name>` | no | Only tasks under this project. Omit for all tasks. |

```
timedart list tasks
timedart list tasks --project "Acme Website" --json
```

```json
[
  {
    "id": "019f…6d",
    "title": "Design",
    "projectId": "019f…c9",
    "projectCode": "ACME",
    "projectTitle": "Acme Website",
    "rate": null
  }
]
```

`rate` is the task's own rate, or `null` when it inherits the project's.

### `log`
Record a completed `TimeEntry` directly (for work that wasn't live-tracked).

| Arg | Req | Notes |
| --- | --- | --- |
| `-p, --project <id\|name>` | yes | Project. |
| `-t, --task <id\|name>` | **yes** | Task within the project. Every entry belongs to a task (matches how the GUI stores time). |
| `-D, --duration <dur>` | yes | See duration formats below. |
| `-d, --description <text>` | no | Entry note. |
| `--at <iso>` | no | ISO-8601 **start** time. Omitted → the entry **ends now** and starts `duration` earlier. |

**Duration formats:** unit tokens combined in any order (`1h30m`, `90m`, `45s`,
`1h 30m`), a single decimal-with-unit (`1.5h`, `0.5m`), or a bare number =
seconds (`5400`). Anything else → exit `2`.

**`--at` formats:** `2026-07-18`, `2026-07-18T09:30`, `2026-07-18T09:30:00`.

```
timedart log -p ACME -t Design -D 1h30m -d "spec review" --at 2026-07-10T09:00 --json
```

```json
{
  "logged": true,
  "entry": {
    "seconds": 5400,
    "project": { "id": "019f…c9", "code": "ACME", "title": "Acme Website" },
    "task": { "id": "019f…6d", "title": "Design" },
    "description": "spec review",
    "startedAt": "2026-07-10T09:00:00.000",
    "endedAt": "2026-07-10T10:30:00.000"
  }
}
```

## Managing entities

Create, edit, archive and delete the **client → project → task** graph. Every
verb reuses the app's data layer, so business rules match the GUI: projects
inherit their client's rate unless given their own, project `code` is unique,
and delete is a cascading soft-delete (sync-safe tombstone). Each verb supports
`--json`; a create/edit/archive prints `{ "action": "created"|"updated"|
"archived"|"unarchived", "<kind>": { … } }` (the entity in the same shape `list`
uses); `delete` prints an impact object (below).

The target of `edit`/`archive`/`unarchive`/`delete` is a **positional**
`<id|name>`; field values are options. On `edit`, **only the options you pass
change**; pass an empty value (`--phone ""`) to clear an optional text field.

### `client add` / `client edit`

| Arg | add | edit | Notes |
| --- | --- | --- | --- |
| `<id\|name>` (positional) | — | yes | The client to edit. |
| `-n, --name` | **yes** | opt | Client name. |
| `-r, --rate` | **yes** | opt | Default hourly rate its projects inherit (a number). |
| `--contact` `--email` `--phone` `--address` `--abn` | opt | opt | Optional details (`""` clears on edit; long-form only, no abbr). |

```
timedart client add -n "Globex" -r 150 --email ops@globex.test -j
timedart client edit "Globex" --phone "+61 400 000 000"
```

### `project add` / `project edit`

| Arg | add | edit | Notes |
| --- | --- | --- | --- |
| `<id\|name>` (positional) | — | yes | The project to edit. |
| `-c, --client <id\|name>` | **yes** | opt | Owning client; on edit, reassigns it. |
| `-C, --code` | **yes** | opt | Unique project code. |
| `-T, --title` | **yes** | opt | Title. |
| `-r, --rate` | opt | opt | A number to set. Omit on add → inherit the client's default. On edit, `--rate inherit` (or `""`) clears it back to inherited. |

```
timedart project add -c "Globex" -C GLOB -T "Globex Site" -j
timedart project edit GLOB -r 175
timedart project edit GLOB -r inherit          # back to the client default
```

### `task add` / `task edit`

| Arg | add | edit | Notes |
| --- | --- | --- | --- |
| `<id\|name>` (positional) | — | yes | The task to edit. |
| `-p, --project <id\|name>` | **yes** | opt | add: owning project. edit: scope the `<id\|name>` lookup (needed only if the title isn't unique across projects). |
| `-T, --title` | **yes** | opt | Title. |
| `-r, --rate` | opt | opt | Like project rate: a number sets it; `inherit`/`""` clears to inherit the project's. |

```
timedart task add -p GLOB -T "Build" -j
timedart task edit "Build" -p GLOB -T "Build v2"
```

### `client archive` / `client unarchive`, `project archive` / `project unarchive`

Archive is a **reversible hide-from-active-lists** — the entity stays live and
fully invoiceable, distinct from delete. **Tasks are not archivable** (the app
has no task archive); use `task delete` to remove one.

```
timedart client archive "Globex"
timedart project unarchive GLOB
```

### `client delete` / `project delete` / `task delete`

Destructive and **cascading** — deleting a client removes its projects, their
tasks and all their time entries. Guarded:

- **`-f`/`--force` is required.** Without it the command **changes nothing**,
  prints the cascade impact, and exits `10` (confirmationRequired).
- If the running timer is bound to the target (or something under it), it exits
  `8` — stop the timer first.

```
timedart project delete GLOB -j         # preview only → exit 10
timedart project delete GLOB -f -j      # actually delete → exit 0
```

Impact shape (same whether refused or done — `deleted` distinguishes them):

```json
{
  "deleted": false,
  "kind": "project",
  "id": "019f…c9",
  "label": "GLOB Globex Site",
  "impact": { "projects": 0, "tasks": 1, "entries": 0, "total": 1 }
}
```

## Live-update contract (CLI ↔ GUI)

The CLI and a running GUI share one database:

- After a CLI **write** (`start`/`stop`/`pause`/`resume`/`log`), an **open,
  foregrounded GUI reflects it within ~1s** — and **instantly on window focus**
  — with no manual refresh (the GUI polls SQLite's `data_version`).
- A **backgrounded** GUI updates on its **next focus** (it stops polling while
  backgrounded).
- The reverse also holds: a timer started/stopped in the GUI is visible to the
  next CLI invocation immediately (CLI reads open a fresh connection every time).
- `active_timer` is **device-local** — there is at most one running timer per
  machine, shared by GUI and CLI on that machine.

## A typical agent flow

```
# set up a client → project → task graph from scratch
timedart client add --name "Globex" --rate 150 --json
timedart project add --client "Globex" --code GLOB --title "Globex Site" --json
timedart task add --project GLOB --title "Build" --json

timedart list projects --json                 # discover ids/names
timedart timer start -p <projectId> -t <taskId> --json
timedart timer status --json                  # confirm running
timedart timer stop --json                    # record the entry
# or, for after-the-fact work:
timedart log -p <projectId> -t <taskId> -D 45m -d "code review" --json
```

Branch on exit codes, parse stdout as JSON, read human errors from stderr.

## Build

`dart compile exe` is **not** usable here — the `sqlite3` dependency ships a
native-asset build hook, which `dart compile exe` rejects. Use **`dart build
cli`**, which bundles the native library alongside the binary:

```
dart build cli
```

Produces a self-contained bundle (no Dart/Flutter runtime required on the
target):

```
build/cli/<os>_<arch>/bundle/
  bin/timedart          # the executable
  lib/libsqlite3.so     # bundled native sqlite (.dylib / .dll per platform)
```

Run it from anywhere (it finds its bundled `lib/` relative to the binary):

```
build/cli/linux_x64/bundle/bin/timedart --version
build/cli/linux_x64/bundle/bin/timedart timer status
```

Ship the whole `bundle/` directory (binary + `lib/`) as the unit — the binary
depends on the co-located native library, so `bin/timedart` alone is not
portable.
