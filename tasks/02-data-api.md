# Task 02 — `apps/data-api` (multi-tenant document store)

## Goal
Build the Hono HTTP service that every generated app calls to persist data. It is the only thing that talks to Postgres `documents`.

## Inputs to read first
- `PRD.md` §4.2 (Data API spec), §3 (schema), §8 (guardrails)
- `infra/sql/001_init.sql` (RLS policy — your queries must `set_config` per request)

## Deliverables
```
apps/data-api/package.json
apps/data-api/tsconfig.json
apps/data-api/src/index.ts
apps/data-api/src/db.ts
apps/data-api/src/auth.ts
apps/data-api/src/rateLimit.ts
apps/data-api/src/routes/documents.ts
```

A `package.json` already exists at `apps/api`; mirror its style.

## Implementation notes

### Stack
- Node 20, ESM, `tsx` for dev, `tsc` for build.
- Deps: `hono`, `@hono/node-server`, `pg`, `zod`, `nanoid`.
- DevDeps: `tsx`, `typescript`, `@types/node`, `@types/pg`.

### `db.ts`
- Export a single `pg.Pool` (`max: 10`, `idleTimeoutMillis: 30_000`).
- Export `withAppContext<T>(appId: string, fn: (client) => Promise<T>): Promise<T>` that:
  1. checks out a client
  2. `BEGIN`
  3. `SELECT set_config('app.current_id', $1, true)` with the app id
  4. runs `fn(client)`
  5. `COMMIT` (rollback on throw)
  6. release

### `auth.ts`
- Hono middleware: requires `Authorization: Bearer <key>` and `X-App-Id: <uuid>`.
- Look up `app_keys` for that `appId`; verify `sha256(key)` matches a stored hash.
- Cache `(appId,keyHash)` in-memory for 60 s to avoid hammering the DB.
- Attach `c.set('appId', appId)` for downstream handlers.
- On failure: `401` for missing/invalid bearer, `403` if the bearer belongs to a different app than `X-App-Id`.

### `rateLimit.ts`
- In-process token bucket keyed by `appId`.
- `RATE_LIMIT_PER_SEC` from env (default 50). Bucket size = 2× rate.
- Return `429` with `Retry-After` header on exhaustion.

### `routes/documents.ts`
Mount under `/v1/d/:appId/:col`. Validate `:appId` is a uuid and `:col` matches the regex in PRD §3. Reject otherwise with 400.

Endpoints (exact shape per PRD §4.2):
- `GET    /v1/d/:appId/:col` — query: `?limit=<1..100>&cursor=<updated_at>`. Returns `{docs, next?}`. Excludes `deleted_at IS NOT NULL`.
- `GET    /v1/d/:appId/:col/:id` — `404` if missing or soft-deleted.
- `PUT    /v1/d/:appId/:col/:id` — body `{body: jsonb}`. Enforce `MAX_BODY_BYTES`. Reject with `413` if exceeded. Reject with `413` if `MAX_DOCS_PER_APP` would be exceeded (compute `count(*) where deleted_at is null` for that app+col? **No — total per app**). On collision update.
- `DELETE /v1/d/:appId/:col/:id` — sets `deleted_at = now()`. `204` even if it was already deleted (idempotent).

All DB calls go through `withAppContext(appId, …)`. **Never accept `appId` from a body or query — only the path.**

### `index.ts`
- Read `PORT` (default 8788), `DATABASE_URL` (required), limits, rate.
- Apply CORS: allow `*`, methods `GET POST PUT DELETE`, headers `Authorization X-App-Id Content-Type`.
- Mount `/health` (no auth) returning `{ok:true}`.
- Mount documents routes behind `auth` + `rateLimit`.
- `serve({ fetch: app.fetch, port })`, log `data-api listening on :PORT`.

## Acceptance criteria

Run locally against a Postgres seeded with `infra/sql/001_init.sql` and one row in `apps` + a `app_keys` row whose plaintext key you know:

```bash
APP_ID=<uuid>
KEY=<plaintext>

# health
curl -s localhost:8788/health
# → {"ok":true}

# put
curl -s -X PUT localhost:8788/v1/d/$APP_ID/notes/abc \
  -H "Authorization: Bearer $KEY" -H "X-App-Id: $APP_ID" \
  -H "Content-Type: application/json" \
  -d '{"body":{"text":"hello"}}'
# → 200 {"id":"abc","body":{"text":"hello"},"updated_at":"..."}

# get
curl -s localhost:8788/v1/d/$APP_ID/notes/abc \
  -H "Authorization: Bearer $KEY" -H "X-App-Id: $APP_ID"
# → 200 same shape

# list
curl -s "localhost:8788/v1/d/$APP_ID/notes?limit=10" \
  -H "Authorization: Bearer $KEY" -H "X-App-Id: $APP_ID"
# → 200 {"docs":[...]}

# delete
curl -i -X DELETE localhost:8788/v1/d/$APP_ID/notes/abc \
  -H "Authorization: Bearer $KEY" -H "X-App-Id: $APP_ID"
# → 204

# 401: missing bearer
# 403: bearer belongs to a different app
# 413: body > MAX_BODY_BYTES
# 429: spam past rate limit
```

- [ ] All curl checks above behave as documented.
- [ ] `tsc --noEmit` clean.
- [ ] `npm run build` succeeds.
- [ ] Soft-deleted docs are excluded from `GET` and `LIST`.
- [ ] Querying with `appId` of app A using app B's key returns `403`.

## Out of scope
- Pagination beyond `updated_at` cursor.
- `POST /query` JSONB filter.
- Realtime / SSE.
- Schema migrations beyond `001_init.sql`.
- Admin endpoints.

## Review gate
Open PR titled **"task 02 — data-api"**. Use the AGENTS.md §6 template. Paste the curl session output.
