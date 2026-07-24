-- ─────────────────────────────────────────────────────────────────────────────
-- Delta-sync — backend setup for Supabase  (PRD #189 / #294)
-- The from-zero backend for the app's sync layer. REVIEW then run in the Supabase
-- SQL editor (as the postgres/service role). Idempotent-ish (IF NOT EXISTS /
-- CREATE OR REPLACE) where practical, but read it before running — it adds RLS
-- policies that gate the four content tables to org members.
--
-- Runs FROM ZERO on a fresh Supabase project: section 0 creates the four content
-- tables (clients/projects/tasks/time_entries), then tenancy (orgs + memberships
-- + the personal-org trigger), the RLS policies, and the pull-cursor sequence.
--
-- Manual dashboard steps this SQL can't do: enable ANONYMOUS sign-ins
-- (Authentication → Providers → Anonymous); after your first sign-in, unlock the
-- entitlement gate on your own org (see the bottom of section 6).
--
-- No secrets live here (pure DDL — no keys, project ref, or connection strings;
-- the app's URL + anon key are dart-defines).
-- ─────────────────────────────────────────────────────────────────────────────

-- 0. Content tables (the FOUR synced tracking tables only — templates/profiles
--    are device-local BLOBs and never sync; server needs neither). Column shapes
--    mirror the app's drift schema: ids are text UUIDv7; DateTimes are epoch-ms
--    bigints; bools are 0/1 ints; rates are double precision; org_id is the text
--    tenancy key. NO server-side FK constraints — referential integrity is the
--    LOCAL DB's job; enforcing FKs here would force a push ORDER (parents before
--    children) and make partial syncs brittle. `server_seq` (section 5) is added
--    inline. NOT NULL columns must all appear in the app's upsert payload (the
--    app supplies them — createdAt/status stamped by the #299 fix).
create table if not exists public.clients (
  id text primary key,
  org_id text,
  name text not null,
  contact_name text, email text, phone text, address text, abn text,
  default_rate double precision not null,
  archived_at bigint, created_at bigint, updated_at bigint, deleted_at bigint,
  server_seq bigint
);
create table if not exists public.projects (
  id text primary key,
  org_id text,
  client_id text not null,
  code text, -- optional (#331); NULL for code-less projects
  title text not null,
  rate double precision,
  status text not null,
  archived_at bigint, created_at bigint not null, updated_at bigint, deleted_at bigint,
  server_seq bigint
);
-- #331: project code is optional. Idempotent for an already-deployed projects
-- table (create table if not exists above won't alter an existing column).
alter table public.projects alter column code drop not null;
create table if not exists public.tasks (
  id text primary key,
  org_id text,
  project_id text not null,
  title text not null,
  rate double precision,
  status text not null,
  created_at bigint not null, updated_at bigint, deleted_at bigint,
  server_seq bigint
);
create table if not exists public.time_entries (
  id text primary key,
  org_id text,
  project_id text not null,
  task_id text,
  description text,
  started_at bigint not null, ended_at bigint not null,
  seconds bigint not null,
  created_at bigint, updated_at bigint, deleted_at bigint,
  server_seq bigint
);

alter table public.clients      enable row level security;
alter table public.projects     enable row level security;
alter table public.tasks        enable row level security;
alter table public.time_entries enable row level security;
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Tenancy tables ───────────────────────────────────────────────────────────
-- An org is the sync scope. Solo user = a personal org-of-one (created at
-- signup). Teams later = add membership rows pointing users at a shared org —
-- zero data re-key, because every content row already scopes on org_id.

create table if not exists public.orgs (
  id         uuid primary key default gen_random_uuid(),
  name       text not null default 'Personal',
  owner_id   uuid references auth.users (id) on delete set null,
  -- entitlement: 'free' = local-only (client simply won't sync); a paid plan
  -- unlocks sync. Enforced app-side for now; can be RLS-enforced later.
  plan       text not null default 'free',
  created_at timestamptz not null default now()
);

create table if not exists public.memberships (
  user_id  uuid not null references auth.users (id) on delete cascade,
  org_id   uuid not null references public.orgs (id) on delete cascade,
  role     text not null default 'owner',
  primary key (user_id, org_id)
);

alter table public.orgs        enable row level security;
alter table public.memberships enable row level security;

-- 2. Membership helper (SECURITY DEFINER → bypasses RLS inside, avoids the
--    content-policy → memberships-policy recursion trap). Returns true if the
--    current auth user belongs to the given org (org_id is stored as text on the
--    content tables, so compare as text).
create or replace function public.is_org_member(target_org text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.memberships m
    where m.user_id = auth.uid()
      and m.org_id::text = target_org
  );
$$;

-- 3. Personal org at signup — fires for EVERY new auth user, incl. anonymous.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_org uuid;
begin
  insert into public.orgs (name, owner_id)
    values ('Personal', new.id)
    returning id into new_org;
  insert into public.memberships (user_id, org_id, role)
    values (new.id, new_org, 'owner');
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 4. RLS: a user sees/edits only their own orgs + memberships.
drop policy if exists orgs_select on public.orgs;
create policy orgs_select on public.orgs
  for select using (public.is_org_member(id::text));

drop policy if exists memberships_select on public.memberships;
create policy memberships_select on public.memberships
  for select using (user_id = auth.uid());

-- 5. Monotonic server-side ordering key for the PULL cursor.
--    A shared sequence stamped by trigger on every write gives each row a
--    strictly increasing `server_seq` on the SERVER clock — so pull ordering is
--    server-authoritative (immune to device clock skew) and exactly resumable
--    (`where server_seq > cursor order by server_seq`), no timestamp-tie gaps.
--    ⚠️ Concurrency caveat (teams, not solo): a seq can be assigned before its
--    txn commits, so a concurrent reader could advance past an uncommitted row.
--    Harmless for a single writer (solo, own devices). Revisit for real teams
--    (safety-window / logical decoding).
create sequence if not exists public.sync_seq;

create or replace function public.stamp_server_seq()
returns trigger
language plpgsql
as $$
begin
  new.server_seq := nextval('public.sync_seq');
  return new;
end;
$$;

-- 6. Per-content-table: add server_seq, the stamp trigger, an index, and the
--    org-scoped RLS policies. Applied to all four now (mechanical/cheap); the
--    5a APP tracer only exercises `clients`.
do $$
declare
  t text;
begin
  foreach t in array array['clients','projects','tasks','time_entries'] loop
    -- ordering key
    execute format('alter table public.%I add column if not exists server_seq bigint', t);
    execute format('drop trigger if exists stamp_seq on public.%I', t);
    execute format(
      'create trigger stamp_seq before insert or update on public.%I '
      'for each row execute function public.stamp_server_seq()', t);
    execute format(
      'create index if not exists %I on public.%I (org_id, server_seq)',
      t || '_org_seq_idx', t);

    -- RLS: read/write only within an org you belong to. No DELETE policy —
    -- deletes are soft (deletedAt tombstone = an UPDATE), so tombstones
    -- replicate through the normal update path.
    execute format('drop policy if exists %I on public.%I', t || '_sel', t);
    execute format(
      'create policy %I on public.%I for select using (public.is_org_member(org_id))',
      t || '_sel', t);

    execute format('drop policy if exists %I on public.%I', t || '_ins', t);
    execute format(
      'create policy %I on public.%I for insert with check (public.is_org_member(org_id))',
      t || '_ins', t);

    execute format('drop policy if exists %I on public.%I', t || '_upd', t);
    execute format(
      'create policy %I on public.%I for update using (public.is_org_member(org_id)) '
      'with check (public.is_org_member(org_id))',
      t || '_upd', t);
  end loop;
end $$;

-- Entitlement unlock (run AFTER your first anon sign-in creates your org):
--   update public.orgs set plan = 'pro' where owner_id = auth.uid();
-- Free (plan='free') orgs never sync — the app gates on this, so a free user
-- has zero server footprint.

-- ─────────────────────────────────────────────────────────────────────────────
-- Notes for the app side (see phase5-5a-app-skeleton.md):
--   • After anon sign-in, the client reads its org_id:
--       select org_id from memberships where user_id = auth.uid()  (RLS-scoped)
--     — actually: select org_id from public.memberships limit 1 (RLS already
--     restricts to the caller). Store it; stamp it onto local rows (adoption).
--   • PUSH: upsert the current row state (incl. deletedAt tombstones) into the
--     table; RLS WITH CHECK enforces org membership (anti-spoof). The client
--     supplies org_id (from membership) — server trusts RLS, not the client.
--   • PULL: select * from <t> where server_seq > :cursor order by server_seq
--     (RLS auto-scopes to the caller's org). Apply row-level LWW by updatedAt.
--   • server_seq is server-authored; the client never writes it (it's absent
--     from the app's upsert payload → the trigger fills it).
-- ─────────────────────────────────────────────────────────────────────────────
