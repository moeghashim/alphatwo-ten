# Task index — alphatwo-ten

Execute strictly in order. Do not start `NN+1` until `NN` is merged.
Each task is sized to be a single PR reviewable in <30 min.

| #  | File                                | Title                                                        | Approx. LOC |
|----|-------------------------------------|--------------------------------------------------------------|-------------|
| 01 | `01-template-repo.md`               | Fill out `templates/generated-app/`                          | ~200 |
| 02 | `02-data-api.md`                    | Build `apps/data-api` (Hono document store)                  | ~250 |
| 03 | `03-orchestrator-clients.md`        | `github.ts`, `sandbox.ts`, agent adapters, `render.ts`       | ~400 |
| 04 | `04-orchestrator-flow.md`           | `orchestrator.ts` + `POST/GET /v1/apps` routes (sandbox loop)| ~300 |
| 05 | `05-web-form.md`                    | Next.js form + status page                                   | ~250 |
| 06 | `06-deploy-smoke.md`                | Render Blueprint deploy + end-to-end smoke                   | ~50 |

Total ~1450 LOC across six PRs.

## Before you start

Read in this exact order:
1. [`README.md`](../README.md) — and the “How alphatwo-ten differs from alpha-ten” table.
2. [`PRD.md`](../PRD.md) — full spec.
3. [`AGENTS.md`](../AGENTS.md) — working rules + review protocol.
4. [`infra/sql/001_init.sql`](../infra/sql/001_init.sql) — DB schema is authoritative.
5. [`render.yaml`](../render.yaml) — service topology is authoritative.
6. The task you're about to do.

If anything in this index conflicts with the PRD, the PRD wins.

## Backbone (recap)

- Sandbox: **Sapiom Compute (Blaxel microVM)**, ephemeral per-job.
- Inside the sandbox: a **coding-agent CLI** chosen via `CODING_AGENT` + `CODING_MODEL`.
- On failure of the primary, the orchestrator runs the **fallback agent** (`FALLBACK_AGENT` + `FALLBACK_MODEL`, default `gemini` / `gemini-3.5-flash`).
- Output of the sandbox = a pushed `main` branch on the generated GitHub repo.
- Render service is created via API after first push; deploy is polled to `live`.
