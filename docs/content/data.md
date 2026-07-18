---
title: Your data
group: Data
order: 40
summary: Export, import, backup, and archiving vs. deleting.
---

# Your data

timedart is local-first — everything lives on your device. Settings gives you two related but different tools for moving that data around, plus two ways to remove an item you no longer need.

## Export and import

**Export data** writes your entire database — clients, projects, tasks, time entries, invoice templates, and profiles — to a single portable backup file. **Import data** reads a backup file back in.

> **Warning:** Importing a backup *replaces all existing data* in the app. It isn't merged in alongside what's already there — the current database is wiped and rebuilt from the file. You'll be asked to confirm before this happens.

A backup file is forward-compatible: it carries a version tag, so a file exported by an older version of timedart can still be restored into a newer one.

> **Warning:** Export your data before a major app upgrade, and before importing a backup you're not certain about — a replace-all import can't be undone once confirmed.

## Archive vs. delete

Every client, project, and task can be **archived** or **deleted** — these are not the same thing:

- **Archive** hides an item (and, for a client, its projects) from the active list. It's fully reversible — restore it anytime with "Show archived" at the bottom of the list.
- **Delete** removes an item permanently. This can't be undone.

If you try to delete a client, project, or task that still has dependents underneath it (a client with projects, a project with tasks, a task with time entries), timedart blocks the plain delete and instead offers **Delete everything** — an explicit, count-warned cascade that removes the item and everything beneath it in one step.

> **Warning:** A cascading "Delete everything" removes every dependent along with the parent, and none of it can be undone.

Both archiving and deleting are blocked while a timer is currently running on that item or anything beneath it — stop the timer first, then archive or delete.

## Removing timedart from your device

timedart is portable and self-contained — there's no installer, and nothing is scattered across your system. Removing it completely is two steps: delete the app, then delete its data folder.

> **Note:** Want to keep your data? Use **Export data** (above) *before* you remove anything. The backup file is yours to keep and can be re-imported into any future install. Once the data folder is gone it can't be recovered.

**1. Remove the app**

- **Linux:** delete the `AppImage`, or the folder you extracted the `tar.gz` into. Nothing was installed system-wide.
- **Windows:** delete the folder you extracted the `.zip` into. It's portable — there's no entry in *Add or remove programs*.
- **macOS:** drag timedart to the Trash.
- **Android:** uninstall it like any app (long-press the icon → **Uninstall**, or **Settings → Apps → timedart → Uninstall**).

**2. Remove your data**

Everything timedart stores — your database, settings, and saved logo — lives in a single folder. Delete that folder and timedart is gone without a trace.

| Platform | Data folder |
|---|---|
| **Linux** | `~/.local/share/timedart/` |
| **macOS** | `~/Library/Application Support/timedart/` |
| **Windows** | `%APPDATA%\timedart\` — paste that into the File Explorer address bar |
| **Android** | *Nothing to do* — Android erases all of an app's data automatically when you uninstall it. |

> **Note:** Any invoice PDFs or backup files you exported are saved wherever you chose to put them at the time (for example your Downloads or Documents folder) — they live outside the app's data folder, so delete those separately if you want them gone too.
