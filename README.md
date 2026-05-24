# alphatwo-ten

> Second design candidate for the **alpha.tenwhy.com** demo, sitting alongside `alpha-ten`.
> Same product, different codegen backbone: **Sapiom / Blaxel microVM sandbox** + **pluggable coding-agent CLI** + **fallback agent**.

A user submits an app name + short description; the system spins up a Blaxel microVM, runs a coding agent CLI inside it (Cursor / Claude / Codex / Gemini), pushes the result to GitHub, deploys to **Render**, and returns a live URL. All generated apps share a single, multi-tenant **document store API** so a shared link shows the same data to the recipient.

This repo is the **platform** (form/UI + orchestrator API + data API + Postgres schema). The **generated apps' template** lives in [`templates/generated-app`](templates/generated-app) and is the seed the coding agent edits inside the sandbox.

## Start here

| Read | Purpose |
|---|---|
| [PRD.md](PRD.md) | Full product + technical spec. Source of truth. |
| [AGENTS.md](AGENTS.md) | How the executing agent should work, including the review protocol. |
| [tasks/](tasks) | Ordered, atomic, reviewable work units. Execute in numeric order. |

## Quick stack summary

| Layer | Tech |
|---|---|
| Frontend (form + status) | Next.js on Render → `alpha.tenwhy.com` |
| Orchestrator API | Node 20 + Hono on Render → `api.alpha.tenwhy.com` |
| Multi-tenant data API | Node 20 + Hono on Render → `data.alpha.tenwhy.com` |
| Database | Single Render Postgres (apps + documents tables) |
| Sandbox / runtime | **Sapiom Compute** (Blaxel microVM, ephemeral, per-job) |
| Coding agent (primary) | Pluggable CLI — default **Cursor Composer 2.5** |
| Coding agent (fallback) | Pluggable CLI — default **Gemini Flash** (`gemini-3.5-flash` via `@google/gemini-cli`) |
| Supported agents | `cursor` · `claude` · `codex` · `gemini` |
| Repo host | GitHub user `moeghashim`, one repo per generated app |
| App hosting | One Render web service per generated app, public URL = `<service>.onrender.com` |

## How `alphatwo-ten` differs from `alpha-ten`

| Concern | `alpha-ten` | `alphatwo-ten` |
|---|---|---|
| Sandbox + agent | Cursor SDK Cloud (combined) | Sapiom/Blaxel microVM + agent CLI inside it |
| Agent choice | Fixed to Cursor Composer 2.5 | Switchable via `CODING_AGENT` / `CODING_MODEL` |
| Resilience | Single run, fail closed | Primary → fallback (`FALLBACK_AGENT` / `FALLBACK_MODEL`) |
| Where code is built | Cursor cloud + PR + merge to default branch | Sandbox `npm ci && npm run build`, then `git push` |
| Render hookup | Auto-deploy on merged PR | Service created via API after first push |

## Switching the coding agent

Set in env (see `.env.example`):

```
CODING_AGENT=cursor            # cursor | claude | codex | gemini
CODING_MODEL=composer-2.5
FALLBACK_AGENT=gemini
FALLBACK_MODEL=gemini-3.5-flash
```

Each agent's CLI is invoked headless inside the sandbox with the same system prompt (`PRD.md` §6.1). Only the agent it points at needs a secret (`CURSOR_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`).

## Local dev

```bash
cp .env.example .env   # fill values
npm install
npm run db:init        # runs infra/sql/001_init.sql against $DATABASE_URL
npm run dev:api        # http://localhost:8787
npm run dev:data       # http://localhost:8788
npm run dev:web        # http://localhost:3000
```

## Deploy

Deploy via Render Blueprint using [`render.yaml`](render.yaml). DNS: point `alpha`, `api.alpha`, `data.alpha` at the matching Render services.
