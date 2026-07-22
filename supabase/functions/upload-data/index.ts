// Supabase Edge Function — the sync write endpoint (PRD #189, Phase 4b / #209).
//
// PowerSync never accepts writes itself and Cloud does not proxy them, so the
// client's local CRUD queue must be applied to the source Postgres out-of-band.
// The app's `uploadData` (lib/data/sync/powersync_connector.dart) POSTs the
// batch here; this function writes it with the `service_role` key.
//
// ── Tenancy (the hard-to-retrofit decision, #207) ────────────────────────────
// `org_id` is derived SERVER-SIDE from the caller's bearer-token `sub` claim and
// is never taken from the request body — a client cannot write into another
// org's scope. For the trial the bearer is a PowerSync **Dev Token** (sub =
// org_id = "timedart", a personal-org-of-one). Phase 5 swaps this for a verified
// Supabase/JWKS token; the org_id-from-`sub` contract stays.
//
// ── Error contract (#209) ────────────────────────────────────────────────────
// Return 5xx ONLY for retryable failures (DB/network) so PowerSync retries the
// whole transaction with backoff. Never return 4xx: a 4xx blocks the client's
// upload queue forever. Permanent/garbage input is logged and dropped with 200
// so the local op can complete and the queue drains.
//
// Deploy:  supabase functions deploy upload-data --no-verify-jwt
// (JWT verification is off at the gateway because the bearer is a PowerSync
// token, not a Supabase-project JWT; we decode `sub` ourselves. See config.toml.)

import { createClient } from 'jsr:@supabase/supabase-js@2';

// Only the four synced content tables (matches the PowerSync Schema in
// lib/data/sync/powersync_schema.dart). Anything else is dropped, not failed.
const SYNCED_TABLES = new Set(['clients', 'projects', 'tasks', 'time_entries']);

/// A Postgres/PostgREST error that will NEVER succeed on retry (bad data, not a
/// transient outage): SQLSTATE classes 22 (data exception), 23 (integrity
/// constraint), 42 (syntax / insufficient privilege), or any PostgREST-level
/// request error. These are logged and dropped with 200 — retrying (5xx) would
/// wedge the client's upload queue forever. Everything else (connection loss,
/// class 08/53/57, deadlock 40P01, …) is treated as retryable.
function isPermanentError(code: string | undefined): boolean {
  if (!code) return false;
  return /^(22|23|42)/.test(code) || code.startsWith('PGRST');
}

/// Decode (WITHOUT verifying — trial only) the `sub` claim of a bearer JWT.
function orgIdFromBearer(req: Request): string | null {
  const auth = req.headers.get('Authorization') ?? '';
  const match = auth.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  const parts = match[1].split('.');
  if (parts.length < 2) return null;
  try {
    const json = atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'));
    const payload = JSON.parse(json);
    return typeof payload.sub === 'string' && payload.sub.length > 0
      ? payload.sub
      : null;
  } catch {
    return null;
  }
}

function ok(body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    // Retryable-only contract does not apply to the wrong verb (never sent by
    // the client); 405 is fine here.
    return new Response('Method Not Allowed', { status: 405 });
  }

  const orgId = orgIdFromBearer(req);
  if (!orgId) {
    // No identity → cannot scope the write. Permanent, but a 4xx would wedge the
    // client queue, so drop with 200.
    console.error('upload-data: missing/undecodable org_id in bearer token');
    return ok({ applied: 0, dropped: 'no org_id' });
  }

  let batch: unknown;
  try {
    batch = (await req.json())?.batch;
  } catch {
    console.error('upload-data: bad JSON body');
    return ok({ applied: 0, dropped: 'bad body' });
  }
  if (!Array.isArray(batch)) return ok({ applied: 0 });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  let applied = 0;
  for (const entry of batch) {
    const table = entry?.type;
    const id = entry?.id;
    const op = entry?.op;
    if (!SYNCED_TABLES.has(table) || typeof id !== 'string') {
      console.error(`upload-data: dropping unknown op ${op} ${table}/${id}`);
      continue; // permanent garbage: drop, do not fail the queue
    }
    // opData carries the row's columns. org_id is stamped server-side, so any
    // client-supplied org_id is ignored.
    const data = { ...(entry?.data ?? {}) };
    delete data.org_id;

    let error;
    if (op === 'PUT') {
      ({ error } = await supabase
        .from(table)
        .upsert({ ...data, id, org_id: orgId }));
    } else if (op === 'PATCH') {
      ({ error } = await supabase
        .from(table)
        .update({ ...data, org_id: orgId })
        .eq('id', id)
        .eq('org_id', orgId));
    } else if (op === 'DELETE') {
      ({ error } = await supabase
        .from(table)
        .delete()
        .eq('id', id)
        .eq('org_id', orgId));
    } else {
      console.error(`upload-data: dropping unknown op verb "${op}"`);
      continue;
    }

    if (error) {
      if (isPermanentError(error.code)) {
        // Bad data, not a transient outage → drop with 200 so the op leaves the
        // client queue instead of retrying forever. (Should not happen from the
        // real app: uploadData sends every non-null column.)
        console.error(
          `upload-data: dropping permanent error on ${op} ${table}/${id} ` +
            `[${error.code}]: ${error.message}`,
        );
        continue;
      }
      // Retryable (connection/outage) → 500 so PowerSync retries the whole
      // transaction with backoff.
      console.error(`upload-data: ${op} ${table}/${id} failed: ${error.message}`);
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    applied++;
  }

  return ok({ applied });
});
