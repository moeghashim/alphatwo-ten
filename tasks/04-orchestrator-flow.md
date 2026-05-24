# Task 04 — Orchestrator flow + `/v1/apps` routes

## Goal
Wire the clients from task 03 into an in-process orchestrator that drives a per-job sandbox, then expose the public API: `POST /v1/apps`, `GET /v1/apps/:id`.

## Inputs to read first
- `PRD.md` §4.1 (API contract), §5 (sandbox flow), §6 (prompt + agent matrix), §8 (failure / fallback)
- `infra/sql/001_init.sql` (statuses incl. `building`, `agent_used`, `model_used`, `fallback_used`, `sandbox_id`, `app_keys`)

## Deliverables
```
apps/api/src/db.ts
apps/api/src/index.ts
apps/api/src/routes/apps.ts
apps/api/src/lib/orchestrator.ts
apps/api/src/lib/validate.ts
apps/api/src/lib/keys.ts
```

## Implementation notes

### `db.ts`
- Single `pg.Pool`.
- Typed helpers: `getApp(id)`, `getAppBySlug(slug)`, `insertApp({slug, description})`, `updateApp(id, patch)`.
- Patch fields: `status`, `status_message`, `repo_url`, `repo_name`, `agent_used`, `model_used`, `fallback_used`, `attempt_count`, `sandbox_id`, `sandbox_log_url`, `render_service_id`, `render_deploy_id`, `preview_url`, `error`.
- All writes touch `updated_at` via trigger.

### `keys.ts`
- `generateAppKey()`: `nanoid(32)` returning plaintext.
- `hashKey(plain): string`: `crypto.createHash('sha256').update(plain).digest('hex')`.
- `insertAppKey(appId, plain)`: stores `(appId, sha256(plain))` into `app_keys`.

### `validate.ts`
- `validateCreateApp(input): { slug, description }` — uses zod.
- Slug regex must match the SQL `apps_slug_format` check exactly: `^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$`.
- Reserved slugs (reject 400): `api`, `data`, `admin`, `www`, `app`, `apps`, `alpha`, `health`.
- `description`: trim, length 1..300; reject if it contains any URL (`/\bhttps?:\/\//i`) or any abuse keyword from a small denylist: `["porn","casino","weapon","malware","phishing","keylogger","creditcard"]` (case-insensitive substring).

### `orchestrator.ts`
Exports `enqueue(appId: string): void`.

- In-memory **concurrency cap of 3**. If at capacity, queue the appId; drain when a slot frees.
- Run `runJob(appId)` with an `AbortController` whose timeout is `JOB_TIMEOUT_MS`.

`runJob(appId)`:
```
1. app = getApp(appId)
2. updateApp(id, { status: 'generating', status_message: 'creating repo' })
3. { repoUrl, repoName, cloneUrlWithToken } = github.createRepoFromTemplate(app.slug, app.description)
   updateApp(id, { repo_url: repoUrl, repo_name: repoName })

4. Sandbox attempt loop: primary first, then fallback once if enabled.
   For each (agentName, modelName) in [primary, fallback?]:
     attempt_count += 1; updateApp(id, { agent_used: agentName, model_used: modelName, fallback_used: attempt_count>1 })
     updateApp(id, { status: 'generating', status_message: `agent: ${agentName}/${modelName}` })

     sandbox = await createSandbox({
       envs: secretsFor(agentName),     // only the secret needed by this agent
       timeoutMs: env.AGENT_TIMEOUT_MS,
     })
     updateApp(id, { sandbox_id: sandbox.id, sandbox_log_url: sandbox.logUrl() ?? null })

     try {
       await sandbox.exec(["git","clone", cloneUrlWithToken, "/work"])
       await getAgent(agentName).install(sandbox)
       const ok = await getAgent(agentName).run({
         sandbox, repoDir: "/work", slug: app.slug, description: app.description,
         model: modelName, signal,
       })
       if (!ok.ok) throw new Error(`agent ${agentName} failed: ${ok.lastMessage ?? 'no message'}`)

       updateApp(id, { status: 'building', status_message: 'npm ci && build' })
       const build = await sandbox.exec(
         ["bash","-lc","cd /work && npm ci && npm run build"],
         { timeoutMs: env.BUILD_TIMEOUT_MS }
       )
       if (build.exitCode !== 0) throw new Error(`build failed: ${tail(build.stderr)}`)

       updateApp(id, { status: 'pushing', status_message: 'git push origin main' })
       const push = await sandbox.exec(
         ["bash","-lc","cd /work && git add -A && git -c user.email=bot@tenwhy.dev -c user.name=tenwhy-bot commit -m 'feat: generated app' && git push origin main"]
       )
       if (push.exitCode !== 0) throw new Error(`push failed: ${tail(push.stderr)}`)
       break   // success → exit attempt loop
     } catch (err) {
       log('warn', 'agent attempt failed', { agentName, err: String(err) })
       if (attempt_count >= attempts.length) throw err
       // else fall through to the next agent
     } finally {
       await sandbox.dispose()
     }

5. updateApp(id, { status: 'deploying', status_message: 'creating render service' })
   plaintextKey = generateAppKey(); insertAppKey(appId, plaintextKey)
   { serviceId, serviceUrl } = render.createService({
     name: shortRenderNameFrom(repoName),
     repoUrl,
     envVars: {
       NEXT_PUBLIC_DATA_API_URL: env.DATA_API_BASE_URL,
       NEXT_PUBLIC_APP_ID: appId,
       NEXT_PUBLIC_APP_KEY: plaintextKey,
     }
   })
   updateApp(id, { render_service_id: serviceId, preview_url: serviceUrl })

6. loop every DEPLOY_POLL_MS, budget JOB_TIMEOUT_MS - elapsed:
   d = render.getLatestDeploy(serviceId)
   updateApp(id, { render_deploy_id: d.deployId, status_message: `deploy: ${d.status}` })
   if d.status === 'live' → updateApp(id, { status: 'live' }); return
   if d.status ends with '_failed' or 'canceled' → throw

7. on any throw or timeout → updateApp(id, { status: 'failed', error: message }).
```

Helpers:
- `secretsFor(name)` returns `{ CURSOR_API_KEY }`, `{ ANTHROPIC_API_KEY }`, `{ OPENAI_API_KEY }`, or `{ GEMINI_API_KEY }`. Never leak the others into the sandbox.
- `attempts` = `[ {agent: env.CODING_AGENT, model: env.CODING_MODEL} ]` plus, if `env.FALLBACK_AGENT` is set, `[{ agent: env.FALLBACK_AGENT, model: env.FALLBACK_MODEL }]`.
- Never let an unhandled rejection escape the worker — wrap in try/catch.

### `routes/apps.ts`
- `POST /v1/apps` —
  - validate body, check slug collision (`getAppBySlug` → 409 `{error:'slug_taken'}`).
  - `insertApp(...)` → `enqueue(id)` → return 202 `{id, slug, status:'queued'}`.
- `GET /v1/apps/:id` —
  - 404 if missing; otherwise return the row plus a derived `health_url = preview_url + '/api/health'` if `preview_url`.

### `index.ts`
- Build Hono app, mount `/health` (always 200 `{ok:true}`), mount `routes/apps.ts`.
- CORS: allow `PLATFORM_BASE_URL` and `http://localhost:3000`; methods `GET, POST`; headers `Content-Type`.
- `serve({fetch: app.fetch, port: env.PORT})`.

## Acceptance criteria

You may stub `createSandbox` and `render.*` via a `SANDBOX_DRIVER=mock` env (NOT a feature flag in code paths — implement as a thin module replacement loaded only when `NODE_ENV==='test'`) **or** simply skip the external calls in a local script and document it.

- [ ] `tsc --noEmit` clean.
- [ ] `npm --workspace apps/api run build` succeeds.
- [ ] `curl -X POST localhost:8787/v1/apps -d '{"slug":"plant-kanban","description":"a kanban for plants"}' -H 'Content-Type: application/json'` returns `202 {id, slug, status:"queued"}`.
- [ ] Submitting the same slug a second time returns `409`.
- [ ] `curl localhost:8787/v1/apps/<id>` returns the row with status advancing past `queued`.
- [ ] Submitting `slug:"admin"` returns `400`.
- [ ] Submitting description containing `https://` returns `400`.
- [ ] Posting 5 jobs → at most 3 sandboxes alive at once (verified in log lines).
- [ ] Simulated primary-agent failure causes one fallback attempt; row records `agent_used` + `model_used` of whichever agent actually succeeded, and `fallback_used=true` only if fallback ran.
- [ ] On simulated failure of both primary and fallback at step 4, the row ends as `failed` with a non-empty `error`.

## Out of scope
- Persistent queue (in-process is fine for v1).
- Webhook callbacks.
- Admin endpoints.
- Retries beyond the single fallback attempt.
- Auth on the orchestrator API (open for the demo).

## Review gate
Open PR titled **"task 04 — orchestrator flow"**. In the “Decisions” section, list how you handled sandbox/render calls during local testing (mock vs real), and confirm that per-agent secrets are scoped (i.e. a Claude-only run never receives `OPENAI_API_KEY`).
