# Task 06 — Render Blueprint deploy + end-to-end smoke

## Goal
Get the platform live on Render and prove the full loop end-to-end against a real Sapiom sandbox, real GitHub, the configured primary coding agent (and at least one fallback rehearsal), and real Render.

## Inputs to read first
- `PRD.md` §7, §10 (acceptance)
- `render.yaml`

## Pre-task checklist (must be done by the human reviewer — do not attempt)
- [ ] DNS for `alpha`, `api.alpha`, `data.alpha` `.tenwhy.com` is ready to be pointed.
- [ ] `tenwhy-generated-app-template` repo is created under `github.com/moeghashim` with the contents of `templates/generated-app/` (push it as a separate repo, **set "Template repository" = true** in repo settings).
- [ ] A GitHub PAT (`GITHUB_TOKEN`) on the `moeghashim` account with `repo` + `read:org` (if applicable) is created — used by the orchestrator to create repos.
- [ ] A second PAT (`GIT_PUSH_TOKEN`) with `repo` scope is created, narrowly scoped if possible — injected into the **sandbox** so the agent can `git push`. Keep it separate so leakage is bounded.
- [ ] **Sapiom Compute** account is provisioned; `SAPIOM_API_KEY` is in hand. The base image `node:20` (or your chosen variant) is reachable from Sapiom.
- [ ] Render workspace is connected to the same GitHub account so it can auto-deploy generated repos.
- [ ] Per-agent secrets for the configured `CODING_AGENT` **and** `FALLBACK_AGENT` are in hand:
      - `CURSOR_API_KEY` (if used)
      - `ANTHROPIC_API_KEY` (if used)
      - `OPENAI_API_KEY` (if used)
      - `GEMINI_API_KEY` (if used) — default fallback model `gemini-3.5-flash`
- [ ] Secrets set in Render (do not commit):
      - `SAPIOM_API_KEY`, `GITHUB_TOKEN`, `GIT_PUSH_TOKEN`, `GITHUB_OWNER=moeghashim`, `GITHUB_TEMPLATE_REPO=tenwhy-generated-app-template`,
        `RENDER_API_KEY`, `RENDER_OWNER_ID`,
        `CODING_AGENT`, `CODING_MODEL`, `FALLBACK_AGENT`, `FALLBACK_MODEL`,
        and the per-agent secrets above,
        `PLATFORM_BASE_URL=https://alpha.tenwhy.com`,
        `DATA_API_BASE_URL=https://data.alpha.tenwhy.com`,
        `NEXT_PUBLIC_API_BASE_URL=https://api.alpha.tenwhy.com`

> Note: alphatwo-ten does **not** require the Cursor GitHub App to be installed. The sandbox authenticates directly to GitHub via `GIT_PUSH_TOKEN`. If `CODING_AGENT=cursor`, only `CURSOR_API_KEY` is needed for the CLI inside the sandbox.

## Deliverables
```
docs/SMOKE.md
```
(everything else already exists from tasks 02–05)

`docs/SMOKE.md` is a short report (paste-friendly) the executor fills in with: timestamps, URLs created, deploy timings, agent used per run, whether the fallback was exercised, screenshots/links of the three smoke runs.

## Implementation notes

### Deploy
1. Open a PR titled **"task 06 — deploy"** that contains only `docs/SMOKE.md` (initially empty headings).
2. On merge to `main`, Render Blueprint should reconcile and create:
   - `tenwhy-alphatwo-web`
   - `tenwhy-alphatwo-api`
   - `tenwhy-alphatwo-data`
   - `tenwhy-alphatwo-db`
3. Wait for all three web services to go `live` and Postgres `available`.
4. From a workstation with `DATABASE_URL` of the Render DB, run `npm run db:init`.
5. Point DNS:
   - `alpha.tenwhy.com` → `tenwhy-alphatwo-web`
   - `api.alpha.tenwhy.com` → `tenwhy-alphatwo-api`
   - `data.alpha.tenwhy.com` → `tenwhy-alphatwo-data`
6. Verify Render shows all three custom domains "verified" with HTTPS issued.

### Smoke

Run **three** end-to-end submissions through the live UI and record results in `docs/SMOKE.md`:

| # | slug              | description                                                  | agent setting |
|---|-------------------|--------------------------------------------------------------|---------------|
| 1 | `plant-kanban`    | a kanban board for tracking plant care tasks and watering    | primary       |
| 2 | `recipe-bin`      | a list of recipes I can add, edit, and tag by cuisine        | primary       |
| 3 | `habit-streak`    | a daily habit tracker that shows my current streak per habit | **force fallback** (e.g. set `CURSOR_API_KEY=invalid` for this run so primary fails and Gemini Flash takes over) |

For each run, record:
- timestamps for each status transition (`queued → generating → building → pushing → deploying → live`),
- which agent + model produced the working artefact (`agent_used`, `model_used`, `fallback_used`),
- GitHub repo URL,
- Sapiom sandbox ID + log link (if accessible),
- Render service URL + first live URL,
- whether opening the URL in two different browsers shows shared data (PRD §10 #7),
- any errors and how they were handled.

## Acceptance criteria
- [ ] All three smoke runs reach `status=live`.
- [ ] Run #3 records `fallback_used=true` and `agent_used=<fallback>`.
- [ ] Each generated app's `/api/health` returns 200.
- [ ] In each app, creating a record from browser A is visible after refresh in browser B.
- [ ] No 5xx logged from `tenwhy-alphatwo-data` during the smoke window.
- [ ] No secrets visible in any commit, in any deploy log, or in any Sapiom log line (verify the redactor in `lib/log.ts` worked).
- [ ] `docs/SMOKE.md` is filled in and committed.

## Out of scope
- Vanity subdomains.
- Cleanup of smoke apps (manual).
- Load testing.
- A/B comparison across all four agents (only primary + one fallback are required).

## Review gate
Open PR titled **"task 06 — deploy + smoke"** with `docs/SMOKE.md` filled in. The reviewer signs off only after personally reproducing the third smoke run (fallback path) from `alpha.tenwhy.com`.
