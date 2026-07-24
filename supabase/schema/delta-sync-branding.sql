-- ─────────────────────────────────────────────────────────────────────────────
-- Delta-sync — branding (templates + profiles + logo Storage)  (issue #320, v20)
-- ADDITIVE follow-up to delta-sync-setup.sql. REVIEW then run in the Supabase SQL
-- editor (postgres/service role). Idempotent (IF NOT EXISTS / DROP..CREATE).
--
-- Brings invoice branding into delta sync: the visual `templates` and the
-- business `profiles` (both were device-local because the profile logo is a
-- BLOB). The logo bytes go to Supabase Storage (bucket `logos`, org-scoped path);
-- the profile row carries only `logo_path` (text) so it rides the normal delta
-- sync. The local BLOB stays the source of truth; Storage is the shared replica
-- (fetch-on-miss on other devices).
--
-- MANUAL DASHBOARD STEP this SQL can't do: create the Storage bucket named
-- `logos` (Storage → New bucket → name "logos", keep it PRIVATE). Then run
-- section 3 below for its RLS. Column shapes mirror the app's drift schema: ids
-- text UUIDv7; DateTimes epoch-ms bigints; bools 0/1 bigints; colours ARGB
-- bigints; rates/taxRate double precision. NO server-side FKs (the local DB owns
-- integrity). Requires delta-sync-setup.sql (shared sync_seq / stamp_server_seq /
-- is_org_member) to have run first.
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Tables ──────────────────────────────────────────────────────────────────
create table if not exists public.templates (
  id text primary key,
  org_id text,
  name text not null,
  color_background bigint not null,
  color_surface bigint not null,
  color_primary bigint not null,
  color_text bigint not null,
  color_accent bigint not null,
  font_family text not null,
  is_default bigint not null default 0,       -- 0/1
  created_at bigint, updated_at bigint, deleted_at bigint,
  server_seq bigint
);

create table if not exists public.profiles (
  id text primary key,
  org_id text,
  name text not null,
  business_name text not null default '',
  logo_path text,                             -- Storage object path; null = no logo
  logo_mime text,
  email text, phone text, website text, address text, abn text,
  payee_name text, bank_name text, bank_bsb text, bank_account text,
  swift text, payment_link text,
  currency text not null default 'USD',
  tax_label text, tax_rate double precision,
  is_default bigint not null default 0,       -- 0/1
  template_id text,
  region text not null default 'au',
  iban text, sort_code text, routing_number text, payid text,
  institution_number text, transit_number text,
  show_bank bigint not null default 1,
  show_payment_link bigint not null default 1,
  show_tax bigint not null default 1,
  show_rate_column bigint not null default 1,
  show_time_column bigint not null default 1,
  reverse_charge bigint not null default 0,
  created_at bigint, updated_at bigint, deleted_at bigint,
  server_seq bigint
);

alter table public.templates enable row level security;
alter table public.profiles  enable row level security;

-- 2. server_seq + stamp trigger + org/seq index + org-scoped RLS (as section 6
--    of delta-sync-setup.sql, applied to the two branding tables).
do $$
declare
  t text;
begin
  foreach t in array array['templates','profiles'] loop
    execute format('alter table public.%I add column if not exists server_seq bigint', t);
    execute format('drop trigger if exists stamp_seq on public.%I', t);
    execute format(
      'create trigger stamp_seq before insert or update on public.%I '
      'for each row execute function public.stamp_server_seq()', t);
    execute format(
      'create index if not exists %I on public.%I (org_id, server_seq)',
      t || '_org_seq_idx', t);

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

-- 3. Storage RLS for the `logos` bucket (create the bucket in the dashboard
--    first — see header). Logo objects are keyed `<org_id>/<file>`, so the first
--    path segment is the org: gate every op on membership of that segment.
--    storage.foldername(name) splits the object path into a text[]; [1] is the
--    top folder = org_id.
drop policy if exists logos_sel on storage.objects;
create policy logos_sel on storage.objects
  for select using (
    bucket_id = 'logos'
    and public.is_org_member((storage.foldername(name))[1])
  );

drop policy if exists logos_ins on storage.objects;
create policy logos_ins on storage.objects
  for insert with check (
    bucket_id = 'logos'
    and public.is_org_member((storage.foldername(name))[1])
  );

drop policy if exists logos_upd on storage.objects;
create policy logos_upd on storage.objects
  for update using (
    bucket_id = 'logos'
    and public.is_org_member((storage.foldername(name))[1])
  );

drop policy if exists logos_del on storage.objects;
create policy logos_del on storage.objects
  for delete using (
    bucket_id = 'logos'
    and public.is_org_member((storage.foldername(name))[1])
  );
