# Product Requirements Document — alphatwo-ten

**Status:** approved for build  
**Owner:** Moe Ghashim  
**Reviewer of all PRs/critique:** the human reviewer who hands you this repo  
**Executing agent:** see [AGENTS.md](AGENTS.md) for working rules and review protocol

> **About this repo:** `alphatwo-ten` is the *second* design candidate alongside `alpha-ten`. Same product, different codegen backbone. `alpha-ten` uses **Cursor SDK Cloud** as the sandbox+agent in one. `alphatwo-ten` uses a **Sapiom (Blaxel) microVM sandbox** with a **pluggable coding-agent CLI** running inside it, plus a **fallback agent** if the primary fails.

---

## 1. Product

A public demo at **`alpha.tenwhy.com`** that turns one form submission into a deployed web app.

### 1.1 User journey
1. User opens `alpha.tenwhy.com`.
2. User enters:
   - **App name** (slug, e.g. `plant-kanban`).
   - **Description** (≤300 chars, e.g. `"a kanban board for tracking plant care tasks"`).
3. User submits → redirected to a status page.
4. Status page shows progress: `queued → generating → building → pushing → deploying → live` (or `failed`).
5. When status is `live`, the page shows an **Open app** button linking to the deployed URL.

### 1.2 Generated app expectations
- Anyone with the URL can use the app.
- Data is persisted on the server and visible to anyone the link is shared with.
- No login required for the demo.

### 1.3 Non-goals (v1)
- No user accounts on `alpha.tenwhy.com`.
- No auth inside generated apps.
- No vanity subdomains.
- No paid tier, quotas UI, or app deletion UI.
- No SSE; polling is fine.
- No realtime sync inside generated apps (writes propagate on refetch).

---

## 2. Architecture

```
┌────────────────────────────┐
│ User browser               │
│ alpha.tenwhy.com           │
└─────────────┬──────────────┘
              │
              ▼
┌────────────────────────────┐
│ Next.js web (Render)       │
│ apps/web                   │
└─────────────┬──────────────┘
              │ REST
              ▼
┌──────────────────────────────────────────────────────┐
│ Hono API + orchestrator (Render)                    │
│ apps/api                                             │
│ POST /v1/apps  ·  GET /v1/apps/:id                   │
│                                                      │
│ In-process job loop per app:                         │
│  1) github.createRepoFromTemplate                    │
│  2) sapiom.createSandbox (Blaxel µVM)                │
│  3) <agent>.install  →  <agent>.run(prompt, model)   │
│     primary → fallback if it fails                   │
│  4) sandbox.exec  npm ci && npm run build  (gate)    │
│  5) sandbox.exec  git push origin main               │
│  6) sandbox.delete                                   │
│  7) render.createService  →  poll deploy             │
└──┬──────────────┬─────────────┬─────────────┬───────┘
   │              │             │             │
   ▼              ▼             ▼             ▼
┌──────────┐ ┌──────────┐ ┌──────────────┐ ┌──────────┐
│ Render PG│ │ GitHub   │ │ Sapiom        │ │ Render   │
│ apps,    │ │ owner +  │ │ Compute       │ │ REST API │
│ documents│ │ template │ │ (= Blaxel µVM)│ │ (deploy) │
└──────────┘ └──────────┘ └──────────────┘ └──────────┘
                                                │
                                                ▼
                                       ┌─────────────────────┐
                                       │ Generated app       │
                                       │ <name>.onrender.com │
                                       │  └ calls data-api   │
                                       └─────────┬───────────┘
                                                 ▼
                                       ┌─────────────────────┐
                                       │ data-api (Render)   │
                                       │ data.alpha.tenwhy.  │
                                       │ com                 │
                                       │  └ Render PG        │
                                       └─────────────────────┘
```

### 2.1 Platform services on Render

| Service | Path | Domain | Purpose |
|---|---|---|---|
| `tenwhy-alpha-web`  | `apps/web`      | `alpha.tenwhy.com`      | Next.js form + status pages |
| `tenwhy-alpha-api`  | `apps/api`      | `api.alpha.tenwhy.com`  | Orchestrator (Sapiom + GitHub + Render clients), in-process job loop |
| `tenwhy-alpha-data` | `apps/data-api` | `data.alpha.tenwhy.com` | Multi-tenant document store API used by every generated app |
| `tenwhy-alpha-db`   | Postgres        | —                       | Shared Postgres: `apps`, `app_keys`, `documents` |

### 2.2 Why Sapiom/Blaxel + CLI (and not Cursor SDK Cloud)
Each codegen run gets a fresh microVM we own. The coding agent (CLI) is **pluggable** — Cursor, Claude Code, OpenAI Codex, Gemini CLI are all interchangeable behind one `CodingAgent` interface. This matches the original "Sapiom sandbox" pattern from `logs.txt` and gives us a built-in fallback path if the primary agent fails.

---

## 3. Data model (Postgres)

Schema is authoritative in [`infra/sql/001_init.sql`](infra/sql/001_init.sql). Summary:

### `apps`
| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `slug` | text unique | regex `^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$` |
| `description` | text | ≤300 chars enforced at API |
| `status` | enum | `queued` `generating` `building` `pushing` `deploying` `live` `failed` |
| `status_message` | text | human-readable current step |
| `tier` | text | `free` default |
| `agent_used` | text | which CLI ran (`cursor`/`claude`/`codex`/`gemini`) |
| `model_used` | text | which model the CLI used |
| `attempt_count` | int | 1 for primary, 2 if fallback was used |
| `repo_url`, `repo_name` | text | GitHub artifacts |
| `sandbox_id` | text | last Sapiom sandbox id used |
| `render_service_id`, `render_deploy_id` | text | |
| `preview_url` | text | the final live URL |
| `error` | text | last error if `failed` |
| `created_at`, `updated_at` | timestamptz | |

### `app_keys`
Hashed bearer keys the data API uses to authenticate generated apps. One per app.

### `documents`  (multi-tenant document store)
| Column | Type | Notes |
|---|---|---|
| `app_id` | uuid FK | scope key |
| `collection` | text | regex `^[a-z0-9][a-z0-9_-]{0,62}$` |
| `doc_id` | text | client-generated |
| `body` | jsonb | arbitrary |
| `deleted_at` | timestamptz nullable | soft-delete |
| `updated_at` | timestamptz | |
| PK | `(app_id, collection, doc_id)` | shard key by `app_id` later if needed |

Postgres **Row-Level Security** on `documents` (`app_id = current_setting('app.current_id')::uuid`) — defense in depth on top of API auth.

---

## 4. APIs

### 4.1 Orchestrator API (`apps/api`)

Base: `https://api.alpha.tenwhy.com`

| Method | Path | Body | Response |
|---|---|---|---|
| `GET` | `/health` | — | `{ok:true}` |
| `POST` | `/v1/apps` | `{slug, description}` | 202 `{id, slug, status}` |
| `GET` | `/v1/apps/:id` | — | full row + derived `health_url` |
| `GET` | `/v1/apps` | — | recent apps |

**Validation:**
- `slug` matches schema regex (3–40 chars); reserved: `api`, `data`, `admin`, `www`, `app`, `apps`, `alpha`, `health`.
- `description` 1–300 chars; reject if it contains any URL (`/\bhttps?:\/\//i`) or a denylist keyword: `porn casino weapon malware phishing keylogger creditcard`.
- 409 on slug collision.

### 4.2 Data API (`apps/data-api`)

Base: `https://data.alpha.tenwhy.com`

Auth on every endpoint: `Authorization: Bearer <APP_PUBLIC_KEY>` and `X-App-Id: <app_id>` (must match the bearer). CORS open.

| Method | Path | Body | Response |
|---|---|---|---|
| `GET` | `/health` | — | `{ok:true}` |
| `GET` | `/v1/d/:appId/:col` | — | `{docs, next?}` paginated, limit 100 |
| `GET` | `/v1/d/:appId/:col/:id` | — | doc or 404 |
| `PUT` | `/v1/d/:appId/:col/:id` | `{body}` | upsert |
| `DELETE` | `/v1/d/:appId/:col/:id` | — | 204 (soft delete) |

**Limits:** `MAX_BODY_BYTES` 1 MB · `MAX_DOCS_PER_APP` 10 000 · `RATE_LIMIT_PER_SEC` 50 (per-app token bucket).

**Connection handling:** every request `BEGIN; SELECT set_config('app.current_id', $1, true); …; COMMIT;` so RLS scopes the query.

### 4.3 Generated-app SDK (`templates/generated-app/src/lib/db.ts`)

```ts
db.collection<T>(name).list(opts?): Promise<{docs, next?}>;
db.collection<T>(name).get(id): Promise<Doc<T> | null>;
db.collection<T>(name).put(id, body): Promise<Doc<T>>;
db.collection<T>(name).delete(id): Promise<void>;
db.id(): string;
```

Reads `NEXT_PUBLIC_DATA_API_URL`, `NEXT_PUBLIC_APP_ID`, `NEXT_PUBLIC_APP_KEY` — all set by the orchestrator on the generated app's Render service. **The agent must not modify `db.ts` or add any other backend.**

---

## 5. Orchestrator flow (with fallback)

```
POST /v1/apps
  └─ validate → insert apps row (status=queued) → enqueue → 202

job(appId):
  1. updateApp(id, status='generating', status_message='creating repo')
  2. { repoUrl, repoName } = github.createRepoFromTemplate(slug, description)
       updateApp(id, repo_url, repo_name)

  3. sandbox = sapiom.createSandbox({ tier:'s', ttl:'30m', image:'blaxel/base-image:latest' })
       updateApp(id, sandbox_id = sandbox.id)
       await sandbox.ready()
       await sandbox.exec(`git clone <repoUrl-with-token> /app && cd /app && \
                           git config user.email "agent@alpha.tenwhy.com" && \
                           git config user.name  "alpha-ten agent"`)

  4. for attempt in [PRIMARY, FALLBACK]:
       agent = getAgent(attempt.agent)
       updateApp(id, agent_used=attempt.agent, model_used=attempt.model, attempt_count++)
       await agent.install(sandbox)              // installs CLI inside the VM
       result = await agent.run(sandbox, {
         cwd:'/app',
         prompt: buildPrompt({slug, description}),
         model: attempt.model,
         timeoutMs: AGENT_TIMEOUT_MS
       })
       if (result.status === 'ok') break
     end
     if (no attempt ok) → fail

  5. updateApp(id, status='building')
     buildResult = await sandbox.exec(`cd /app && npm ci && npm run build`,
                                       { timeoutMs: BUILD_TIMEOUT_MS })
     if (buildResult.exitCode !== 0) → fail

  6. updateApp(id, status='pushing')
     await sandbox.exec(`cd /app && git add -A && \
       git commit -m "feat: initial implementation" --allow-empty && \
       git push origin main`)

  7. sapiom.deleteSandbox(sandbox.id)

  8. updateApp(id, status='deploying')
     plaintextKey = generateAppKey(); insertAppKey(appId, plaintextKey)
     { serviceId, serviceUrl } = render.createService({
       name: `app-${slug}-${shortId}`,
       repoUrl,
       envVars: {
         NEXT_PUBLIC_DATA_API_URL: env.DATA_API_BASE_URL,
         NEXT_PUBLIC_APP_ID: appId,
         NEXT_PUBLIC_APP_KEY: plaintextKey,
       }
     })
     updateApp(id, render_service_id, preview_url=serviceUrl)

  9. loop every DEPLOY_POLL_MS, budget JOB_TIMEOUT_MS - elapsed:
     d = render.getLatestDeploy(serviceId)
     updateApp(id, render_deploy_id, status_message=`deploy: ${d.status}`)
     if d.status === 'live' → updateApp(id, status='live'); return
     if d.status ∈ {build_failed, pre_deploy_failed, update_failed, canceled} → fail

  on any throw → updateApp(id, status='failed', error=msg); ensure sandbox cleaned up.
```

**Defaults:**
- `PRIMARY = { agent: env.CODING_AGENT ?? 'cursor', model: env.CODING_MODEL ?? 'composer-2.5' }`
- `FALLBACK = { agent: env.FALLBACK_AGENT ?? 'gemini', model: env.FALLBACK_MODEL ?? 'gemini-3.5-flash' }`
- Set `FALLBACK_AGENT=` (empty) to disable fallback.

**Concurrency cap:** 3 concurrent jobs in v1 (in-process semaphore).
**Timeouts:** `AGENT_TIMEOUT_MS=900000` (15 min), `BUILD_TIMEOUT_MS=300000` (5 min), `DEPLOY_POLL_MS=12000`, `JOB_TIMEOUT_MS=1800000` (30 min total).

---

## 6. Coding agent providers (pluggable CLI runtimes)

The orchestrator owns one tiny abstraction. Adding a new agent = one file.

### 6.1 `CodingAgent` interface
```ts
export interface CodingAgent {
  readonly name: 'cursor'|'claude'|'codex'|'gemini';
  install(sb: Sandbox): Promise<void>;
  run(sb: Sandbox, opts: {
    cwd: string;
    prompt: string;
    model: string;
    timeoutMs: number;
  }): Promise<{ status: 'ok'|'failed'; logs: string }>;
}
```

### 6.2 Shipped implementations (`apps/api/src/lib/agents/`)

| Agent | Install (inside VM) | Auth env | Headless run |
|---|---|---|---|
| **cursor** | `curl https://cursor.com/install -fsS \| bash` then `export PATH=$HOME/.local/bin:$PATH` | `CURSOR_API_KEY` | `cursor-agent --print --model {model} "$PROMPT"` |
| **claude** | `npm i -g @anthropic-ai/claude-code` | `ANTHROPIC_API_KEY` | `claude -p "$PROMPT" --model {model}` |
| **codex**  | `npm i -g @openai/codex` | `OPENAI_API_KEY` | `codex exec --model {model} "$PROMPT"` |
| **gemini** | `npm i -g @google/gemini-cli@latest` | `GEMINI_API_KEY` | `gemini --non-interactive -p "$PROMPT" -m {model} --output-format json` |

The executor verifies each CLI's exact headless syntax during task 03 and pins install command versions. Each `install` is idempotent.

### 6.3 Sandbox interface (Sapiom Compute)

```ts
export interface Sandbox {
  id: string;
  ready(): Promise<void>;                              // wait for status=running
  exec(cmd: string, opts?: {
    cwd?: string;
    env?: Record<string,string>;                       // merged on top of base
    timeoutMs?: number;
  }): Promise<{ stdout: string; stderr: string; exitCode: number }>;
  writeFile(path: string, content: string|Buffer): Promise<void>;
  delete(): Promise<void>;
}

export async function createSandbox(opts: {
  tier?: 'xs'|'s'|'m'|'l'|'xl';
  ttl?: string;
  image?: string;
}): Promise<Sandbox>;
```

HTTP: `POST https://blaxel.services.sapiom.ai/v1/sandboxes`, then runtime proxy endpoints (`/process`, `/filesystem`). Use `@sapiom/fetch` for auth/billing headers.

### 6.4 Prompt (shared by all agents)

```
You are generating a complete runnable demo web app in this repository.

APP SLUG: {{slug}}
USER DESCRIPTION: {{description}}

Hard requirements:
1. Build a single-service Next.js (App Router) + TypeScript app only.
2. Persist all user data using the pre-installed SDK at src/lib/db.ts via
   db.collection(name).{list, get, put, delete}. Do not import any other
   database, add migrations, or fetch the data API directly.
3. Do not add auth, payments, email, Docker, infra files, or any new env vars.
4. The app must build and run with:
     npm ci
     npm run build
     npm run start
5. src/app/api/health/route.ts must return HTTP 200 with JSON {"ok":true}.
6. Replace src/app/page.tsx (and add components as needed) with a polished UI
   and working interactions that match the user's description.
7. Keep dependencies minimal; do not add UI libraries unless essential.
8. Update README.md with: what the app does, how to run, and the limitation
   that all visitors share the same data (it is a demo).
9. Before finishing, run `npm run build` and fix any errors.
10. Commit your changes. Do NOT create a branch — commit directly to main.

Do NOT:
 - ask follow-up questions
 - leave TODOs, placeholders, or commented-out code
 - require additional environment variables
 - modify src/lib/db.ts or any file under .cursor/
 - generate unsafe, malicious, or credential-harvesting functionality
```

Pinned in `templates/generated-app/.cursor/skills/app-builder.md` so it stays embedded in the repo regardless of which agent runs.

---

## 7. Render deployment

### 7.1 Platform — via Blueprint
`render.yaml` declares `web`, `api`, `data-api`, and `postgres`. Push to `main` ⇒ Render redeploys.

### 7.2 Generated apps — via Render REST API
`POST https://api.render.com/v1/services` (body identical to alpha-ten — see source `apps/api/src/lib/render.ts`).
Poll `GET /v1/services/{id}/deploys?limit=1`; live when `status == "live"`. Interval **12 s**, total budget **15 min** post-sandbox.

---

## 8. Failure modes and guardrails

| Risk | Mitigation |
|---|---|
| Sandbox create timeout / 5xx | Retry create once with 5 s backoff; fail with `error=sandbox_create_failed` |
| CLI install fails in sandbox | Return `status:'failed'` from agent.install; orchestrator triggers fallback |
| Primary agent hangs | `AGENT_TIMEOUT_MS` kills the process via sandbox API; orchestrator triggers fallback |
| Primary returns no commit / empty diff | Detect via `git diff --quiet HEAD~1`; fallback |
| Generated app fails to build | Build gate fails; mark failed; record stderr tail in `error` |
| App crashes after deploy | Render reports `build_failed`/`update_failed`; mark failed |
| Sandbox leak | All exits go through `finally { sapiom.deleteSandbox(id) }` |
| Slug collision | DB unique constraint → 409 |
| Abusive description | Server-side denylist + URL detector |
| Secret leakage to CLI | The sandbox env exposes only the CLI's own auth env var (`CURSOR_API_KEY` xor `ANTHROPIC_API_KEY` xor `OPENAI_API_KEY` xor `GEMINI_API_KEY`). Never `RENDER_API_KEY`/`GITHUB_TOKEN`/`DATABASE_URL`/`SAPIOM_API_KEY`. |
| GitHub push from sandbox | Use a scoped `GIT_PUSH_TOKEN` (PAT with `repo` only) injected into the clone URL: `https://x-access-token:<token>@github.com/...`; rotate quarterly |
| Cross-app data read | Data API enforces `X-App-Id` matches bearer; Postgres RLS enforces again |
| Render rate limits | Poll at 12 s; concurrency cap 3 |
| Cost runaway | All sandboxes have `ttl:'30m'` hard cap; concurrency cap 3 |

---

## 9. Out of scope (v1)

- Vanity subdomains
- User accounts / auth
- SSE / WebSocket
- Realtime sync in generated apps
- Per-app DB
- Retries beyond the single fallback attempt
- Separate background worker service
- Admin UI / app deletion
- Billing
- Multiple template families (only `next-single-service`)

---

## 10. Acceptance criteria

Submitting `slug=plant-kanban, description="a kanban board for tracking plant care tasks"` from `alpha.tenwhy.com` must:

1. Insert an `apps` row and return 202 with the id within 1 s.
2. Create a new GitHub repo `moeghashim/app-plant-kanban-<shortid>` within ~30 s.
3. Boot a Sapiom sandbox, install the primary agent CLI, and commit code in ≤10 min.
4. Pass `npm run build` inside the sandbox; push to `main`.
5. Create a Render web service that finishes deploying within ~10 min.
6. Show a live `https://app-plant-kanban-<shortid>.onrender.com` URL on the status page.
7. Visiting that URL from two different browsers shows the **same** data; adding a record in one shows up in the other after refresh.
8. If the primary agent fails at any step (3–4), `attempt_count` becomes 2, `agent_used` switches to the fallback (`gemini` / `gemini-3.5-flash`), and the rest of the flow continues.

When all eight pass reliably for three different descriptions in a row, the demo is shippable.
