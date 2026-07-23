/// Phase 5a delta-sync (#294) — the `app_settings` keys the sync layer owns.
/// Namespaced under `sync.` so they never collide with app/onboarding settings.
/// These live in the device-local `app_settings` table (never synced), so each
/// device keeps its own org cache, push watermark, and pull cursor.
library;

/// Cached org_id for the signed-in account (from `memberships`). Stamped onto
/// local rows during adoption and supplied as `org_id` on push.
const String kSyncOrgId = 'sync.orgId';

/// Push watermark for `clients`: the max `updatedAt` (epoch-ms) already pushed.
/// Next push sends rows strictly newer than this.
const String kSyncLastPushedClients = 'sync.lastPushed.clients';

/// Pull cursor for `clients`: the max server-authored `server_seq` already
/// applied. Next pull requests rows with `server_seq` strictly greater.
const String kSyncCursorClients = 'sync.cursor.clients';
