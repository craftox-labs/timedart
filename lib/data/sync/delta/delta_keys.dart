/// Phase 5a delta-sync (#294) — the `app_settings` keys the sync layer owns.
/// Namespaced under `sync.` so they never collide with app/onboarding settings.
/// These live in the device-local `app_settings` table (never synced), so each
/// device keeps its own org cache, push watermark, and pull cursor.
library;

/// Cached org_id for the signed-in account (from `memberships`). Stamped onto
/// local rows during adoption and supplied as `org_id` on push.
const String kSyncOrgId = 'sync.orgId';

/// The opt-in switch (Phase 5d, #294): whether the maintainer has turned delta
/// sync ON for this device. `'1'` = on, anything else (incl. absent) = off. Off
/// is the default — local-only, no sign-in, no network. Device-local so each
/// device opts in independently; kept in `app_settings` because delta sync runs
/// on the one local drift store — there's no second store to split-brain, so no
/// on-disk activation file is needed.
const String kSyncEnabled = 'sync.delta.enabled';

/// The four synced content-table names (== each drift table's `actualTableName`
/// and its `public.<name>` Postgres table). The single source the outbox,
/// transport, and cursor keys all agree on — a typo here would be a silent sync
/// hole, so it's named once. Sync applies them parent-first (FK-safe on local
/// apply); the backend has no FKs.
const String kTableClients = 'clients';
const String kTableProjects = 'projects';
const String kTableTasks = 'tasks';
const String kTableTimeEntries = 'time_entries';

/// The live running timer (issue #300). Synced like the content tables but
/// applied LAST on pull (it FK-references projects/tasks locally, so its parents
/// must land first). A normal LWW row keyed by `id`.
const String kTableActiveTimers = 'active_timers';

/// Invoice branding (issue #320): the visual `templates` and the business
/// `profiles`. Synced like the content tables; `profiles` is applied AFTER
/// `templates` (its `templateId` FK-references one locally). The profile logo
/// BLOB itself doesn't sync as a column — it goes to Supabase Storage and the
/// row carries only `logo_path`.
const String kTableTemplates = 'templates';
const String kTableProfiles = 'profiles';

/// Pull cursor for a table: the max server-authored `server_seq` already
/// applied. Next pull requests rows with `server_seq` strictly greater. Keyed
/// per table so each advances independently. (Phase 5b replaced the 5a push
/// *watermark* with the [SyncOutbox] dirty-tracker, so there is no lastPushed
/// key any more — the outbox IS the push set.)
String syncCursorKey(String table) => 'sync.cursor.$table';
