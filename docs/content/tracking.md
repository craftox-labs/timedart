---
title: Tracking time
group: Tracking
order: 20
summary: Clients, projects, tasks, rates, and the timer in depth.
---

# Tracking time

## The hierarchy

timedart organises billable work into three levels, each owned by the one above:

- **Client:** a person or organisation you bill. Owns projects and a default hourly rate.
- **Project:** a body of work for one client. Carries an optional rate override and a reference code.
- **Task:** a named unit of work inside a project. This is what you actually start a timer against.

A **time entry** is the atom underneath all of this: a single tracked interval against a task — a start, a duration, and an optional note.

## Rates

A rate can be set at three levels: the client's default, a project's override, or a task's own rate.

> **Note:** A rate set lower down wins — a task uses its own rate if it has one, otherwise its project's, otherwise its client's default.

This lets you set one sensible default per client and only override it where a specific project or task is billed differently.

## The timer

Select a task and press **Start** to begin timing it. The timer can be paused and resumed, and **Finish** stops it and saves the tracked interval as a time entry.

A task's project is bound the moment you start the timer on it — switching your selection elsewhere mid-session doesn't move or lose the time already being tracked.

> **Note:** A running timer is saved as you go, not just held in memory — it survives quitting and reopening the app, resuming exactly where you left off. You never lose in-progress time to a restart.

## Time entries

Each finished session becomes a time entry: a start time, a duration, and an optional note. Time entries are what an invoice's line items are built from — no time entry, nothing to bill.
