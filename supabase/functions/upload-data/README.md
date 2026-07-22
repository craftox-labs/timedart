# `upload-data` — sync write endpoint (Phase 4b, #209)

The app's `uploadData` connector POSTs its local CRUD queue here; this function
applies it to the source Postgres with the `service_role` key and stamps
`org_id` from the caller's token. PowerSync Cloud does not proxy writes, so this
is the write half of the trial (the read/stream-down half is 4c).

## Wire contract

Request (`Authorization: Bearer <powersync-dev-token>`):

```json
{ "batch": [ { "op": "PUT|PATCH|DELETE", "type": "<table>", "id": "<uuid>", "data": { ... } } ] }
```

- `org_id` is derived from the token's `sub` claim, **never** the body (any
  `org_id` in `data` is discarded). Trial: `sub == org_id == "timedart"`.
- Only `clients`, `projects`, `tasks`, `time_entries` are written; other tables
  are dropped.
- Response: `200 {"applied": N}` on success. `500` only for **retryable** DB
  errors (connection/outage → PowerSync retries). Permanent Postgres errors
  (constraint/data/privilege — SQLSTATE 22/23/42, or PostgREST) are logged and
  dropped with `200`. Never `4xx` — any of these would wedge the upload queue.

## Deploy

Needs the Supabase CLI and a login to the project from 4a. `verify_jwt = false`
is set in `supabase/config.toml` (the bearer is a PowerSync token, not a
Supabase JWT, so the gateway must not verify it — the function decodes `sub`
itself; Phase 5 restores verification).

```bash
supabase login
supabase link --project-ref <your-project-ref>
supabase functions deploy upload-data --no-verify-jwt
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically — no
secrets to set.

## Verify the DoD (#209)

A client upload batch (insert/update/delete) lands in the source Postgres with
the correct `org_id`. Use the same dev token the app uses (dashboard →
Dev Tokens; `sub = timedart`):

```bash
FUNC="https://<ref>.supabase.co/functions/v1/upload-data"
TOKEN="<dev-token>"

# insert a client
curl -sS -X POST "$FUNC" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"batch":[{"op":"PUT","type":"clients","id":"11111111-1111-7111-8111-111111111111","data":{"name":"CLI Curl Co","created_at":0,"updated_at":0}}]}'
# → {"applied":1}
```

Then confirm in the Supabase table editor that the `clients` row exists with
`org_id = "timedart"`. Re-run with `"op":"DELETE"` (same `id`, `data` omitted)
to confirm removal. Column names in `data` must match the Postgres schema
(snake_case).

## App wiring

Build the app with the function URL alongside the existing sync defines:

```bash
flutter run -d linux \
  --dart-define=ENABLE_SYNC=true \
  --dart-define=POWERSYNC_URL=https://<id>.powersync.journeyapps.com \
  --dart-define=POWERSYNC_TOKEN=<dev-token> \
  --dart-define=SUPABASE_FUNCTION_URL=https://<ref>.supabase.co/functions/v1/upload-data
```

Create/edit/delete a client, project, task or entry → it lands in Postgres and
streams to the other device. `org_id` is stamped server-side.
