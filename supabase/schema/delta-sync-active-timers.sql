-- ─────────────────────────────────────────────────────────────────────────────
-- Delta-sync — running-timer sync backend addition  (issue #300, schema v19)
-- ADDITIVE follow-up to delta-sync-setup.sql. REVIEW then run in the Supabase SQL
-- editor (postgres/service role). Idempotent (IF NOT EXISTS / DROP..CREATE).
--
-- Brings the live running timer (`active_timers`) into delta sync, so a timer
-- started on one device shows as running on another (same account). The row is
-- written only at state transitions (start/pause/resume/note-edit), NOT every
-- second — elapsed is derived locally from `running_since` — so ordinary
-- row-level LWW is a clean fit, same as every other synced table.
--
-- Identity is the row `id` (random UUIDv7 per timer start), so two devices timing
-- DIFFERENT work produce two distinct rows that COEXIST (neither clobbered); only
-- the SAME timer touched on both devices resolves by LWW.
--
-- No secrets here (pure DDL). Server has no FK constraints (integrity is the
-- local DB's job) — mirrors the four content tables.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. The table. Column shapes mirror the app's drift `ActiveTimers`: ids are
--    text UUIDv7; DateTimes are epoch-ms bigints; project_id/task_id are nullable
--    (a timer is unbound until first start). accumulated_seconds is a bigint.
create table if not exists public.active_timers (
  id text primary key,
  org_id text,
  project_id text,
  task_id text,
  description text,
  started_at bigint,
  accumulated_seconds bigint not null default 0,
  running_since bigint,               -- null = paused
  created_at bigint, updated_at bigint, deleted_at bigint,
  server_seq bigint
);

alter table public.active_timers enable row level security;

-- 2. server_seq ordering key + stamp trigger + org/seq index + org-scoped RLS.
--    Reuses public.sync_seq and public.stamp_server_seq / public.is_org_member
--    from delta-sync-setup.sql (must have been run first). No DELETE policy —
--    deletes are soft (deleted_at tombstone = an UPDATE).
alter table public.active_timers add column if not exists server_seq bigint;

drop trigger if exists stamp_seq on public.active_timers;
create trigger stamp_seq before insert or update on public.active_timers
  for each row execute function public.stamp_server_seq();

create index if not exists active_timers_org_seq_idx
  on public.active_timers (org_id, server_seq);

drop policy if exists active_timers_sel on public.active_timers;
create policy active_timers_sel on public.active_timers
  for select using (public.is_org_member(org_id));

drop policy if exists active_timers_ins on public.active_timers;
create policy active_timers_ins on public.active_timers
  for insert with check (public.is_org_member(org_id));

drop policy if exists active_timers_upd on public.active_timers;
create policy active_timers_upd on public.active_timers
  for update using (public.is_org_member(org_id))
  with check (public.is_org_member(org_id));
