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

> **Note:** The CLI ships with an upcoming release. Download links and install
> steps will be added here once it's available — this page describes how it
> works so it's ready when the tool is.

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

## Selecting projects and tasks

`--project` and `--task` accept either the **name** (a project's code or title, a
task's title) or its **UUID**. Names must match exactly and be unique.

> **Tip:** If a name matches more than one project or task, the command stops and
> asks you to disambiguate. Use the UUID (shown by `timedart list …`) when a name
> is ambiguous or when scripting.

## Scripting

Add `--json` to any command for machine-readable output, and every command
returns a meaningful exit code (`0` on success; distinct non-zero codes for
errors like an unknown project or no running timer) so scripts can branch on the
result.

```
timedart timer status --json
```

> **Note:** For the full machine-readable reference — every command's arguments,
> JSON output shapes, and exit-code table — see the agent-usage guide at
> `docs/cli/agent-guide.md`. It's written for automation and LLM/agent use.
