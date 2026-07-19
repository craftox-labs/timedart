---
title: Command-line interface
group: Reference
order: 60
summary: Drive timedart from the terminal — a peer of the app on the same database.
---

# Command-line interface

The `timedart` command-line tool lets you track time from a terminal. It's a
**peer of the desktop app**, not a separate tool: it reads and writes the *same*
local database. A timer you start in the CLI appears in the open app within about
a second (and instantly when you focus its window), and a timer you start in the
app can be stopped from the CLI. Every CLI command reads the current state fresh,
so the two never drift apart.

## Installing

The CLI ships as a self-contained download with each timedart release — there's
no separate runtime to install. Grab the archive for your platform from the
[latest release](https://github.com/craftox-labs/timedart/releases/latest):

| Platform | Download |
| --- | --- |
| Linux | `timedart-cli-linux-x86_64.tar.gz` |
| macOS (Apple silicon) | `timedart-cli-macos-arm64.zip` |
| Windows | `timedart-cli-windows-x64.zip` |

Each archive contains a `bin/` (the `timedart` program) and a `lib/` (a small
library it needs) — **keep the two together**; the program looks for its `lib/`
right beside it.

On Linux or macOS, unpack it somewhere permanent and link the program onto your
PATH — for example, on Linux:

```
mkdir -p ~/.local/opt/timedart-cli
tar -xzf timedart-cli-linux-x86_64.tar.gz -C ~/.local/opt/timedart-cli
ln -sf ~/.local/opt/timedart-cli/bin/timedart ~/.local/bin/timedart
```

On macOS, `unzip timedart-cli-macos-arm64.zip -d ~/.local/opt/timedart-cli`
instead of the `tar` step. On Windows, extract the zip to a folder you'll keep
and add that folder's `bin` to your PATH.

Check it's working:

```
timedart --version
```

The CLI reads the **same database as the app**, so once you've run the desktop
app at least once, it works against your real data straight away — no setup, no
config.

> **Note:** The builds are unsigned before 1.0, so macOS or Windows may warn the
> first time you run the CLI; allow it to continue.

**Driving timedart from an AI agent?** It's built for that — the binary carries
its own instructions, so an agent can learn the whole tool by running `timedart
guide` (see **Scripting and agents**, below). No need to hand it this page.

## The timer

Show what's running, with live elapsed time:

```
timedart timer status
```

```
Running — ACME Acme Website / Design
  hero section
  Elapsed: 1m 5s
```

Start a timer against a project and task. **A task is required** — all time in
timedart is tracked against a task, just like in the app:

```
timedart timer start --project "Acme Website" --task Design --description "hero section"
```

Stop it and record the time as an entry:

```
timedart timer stop
```

```
Stopped. Recorded 1m 5s on ACME Acme Website / Design.
```

You can also pause and resume the running timer:

```
timedart timer pause
timedart timer resume
```

Change a running timer's note, or move it to a different task, without stopping
it — and if you started one by mistake, **discard** it to throw it away with no
entry recorded:

```
timedart timer edit --description "revised note"
timedart timer edit --task "Code review"
timedart timer discard
```

## Listing your work

Find the clients, projects and tasks to track against:

```
timedart list clients
timedart list projects
timedart list tasks --project "Acme Website"
```

```
ACME  Acme Website  (Acme Co)
  019f…c9
```

## Managing clients, projects and tasks

You can set up and maintain your whole client → project → task structure from the
terminal — the same actions the app offers, on the same database.

Create a client, a project under it, and a task under that:

```
timedart client add --name "Acme Co" --rate 150
timedart project add --client "Acme Co" --code ACME --title "Acme Website"
timedart task add --project ACME --title Design
```

A client's rate is the default its projects inherit; a project or task can set
its own `--rate` to override it, or use `--rate inherit` to clear it back to the
default.

Edit any of them — only the fields you pass change:

```
timedart project edit ACME --title "Acme Marketing Site"
timedart client edit "Acme Co" --email accounts@acme.example
```

**Archive** a client or project to hide it from your active lists without losing
its history (it stays available for invoices); unarchive to bring it back:

```
timedart client archive "Acme Co"
timedart client unarchive "Acme Co"
```

**Delete** removes an entity for good, along with everything under it (a
project's tasks and time entries, a client's whole tree). Because that can't be
undone, delete needs `--force` — without it, the command just shows you what
*would* be removed:

```
timedart project delete ACME            # shows the impact, deletes nothing
timedart project delete ACME --force    # actually deletes it and everything under it
```

## Logging past work

Record time you didn't track live — for example 1½ hours of design work:

```
timedart log --project "Acme Website" --task Design --duration 1h30m --description "spec review"
```

Durations can be written as `1h30m`, `90m`, `1.5h`, `45s`, or a plain number of
seconds. By default the entry ends now and starts `--duration` earlier; pass
`--at <iso>` (e.g. `--at 2026-07-18T09:00`) to set an explicit start time.

List recorded entries, then fix or remove one — handy when a duration was mistyped
or an entry landed on the wrong task:

```
timedart list entries --project "Acme Website"
timedart entry edit <id> --duration 45m --description "spec review"
timedart entry delete <id> --force
```

Filter the list with `--task`, `--project`, and a date window (`--since` /
`--until`). Entries are identified by the UUID shown in the list.

## Reports

Total up your tracked time over a period, grouped how you like:

```
timedart report
timedart report --project "Acme Website" --since 2026-07-01 --by day
```

```
ACME Acme Website   6h 30m   5 entries   $780.00
TOTAL               6h 30m   5 entries   $780.00
```

Scope with `--client` / `--project` / `--task` and a `--since` / `--until`
window (it defaults to the current week), and group with `--by project|task|client|day`.
Where a rate is set, each row shows the amount too.

## Selecting projects and tasks

`--project` and `--task` accept either the **name** (a project's code or title, a
task's title) or its **UUID**. Names must match exactly and be unique.

> **Tip:** If a name matches more than one project or task, the command stops and
> asks you to disambiguate. Use the UUID (shown by `timedart list …`) when a name
> is ambiguous or when scripting.

Most flags have a short form, so common commands stay compact — `-p` project,
`-t` task, `-d` description, `-D` duration, `-j` json, and so on (see any
command's `--help`):

```
timedart log -p "Acme Website" -t Design -D 1h30m -d "spec review"
```

## Scripting and agents

Add `--json` (`-j`) to any command for machine-readable output, and every command
returns a meaningful exit code (`0` on success; distinct non-zero codes for
errors like an unknown project or no running timer) so scripts can branch on the
result. In `--json` mode, errors come back as JSON too.

```
timedart timer status --json
```

The CLI is built to be driven by an AI agent as well as by you. It carries its
own instructions, so an agent can learn the whole tool from the binary — no need
to hunt down a manual:

```
timedart guide          # the full usage guide, written for agents
timedart help --json    # a machine-readable map of every command and exit code
```

> **Tip:** `timedart guide` prints the complete reference — every command's
> arguments, JSON output shapes, and the exit-code table. It's the same guide an
> agent reads to drive timedart from the terminal.
