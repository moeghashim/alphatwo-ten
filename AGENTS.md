# AGENTS.md — working agreement

This file governs how the **executing agent** and the **human reviewer** (Moe) collaborate on this repository. The agent must read this file fully before starting any task, and must re-read it at the start of every new session.

If anything in this file conflicts with the user's direct instruction in the conversation, ask before deviating.

---

## 1. Roles

| Role | Who | Responsibilities |
|---|---|---|
| **Executor** | The coding agent picking up this repo (Cursor/Claude/Codex/etc.) | Implement tasks one at a time, stop at review gates, respond to critique. |
| **Reviewer** | The original architect (planning agent / the human) | Approve the PRD, review each task's output, leave critique, sign off. |
| **Decider** | Moe (human) | Final say on scope changes or anything not covered by the PRD. |

The reviewer does NOT write code in this repo. The executor does NOT change scope.

---

## 2. Source of truth

In order of precedence:

1. The user's live instruction (in chat).
2. `PRD.md` — the product spec.
3. `tasks/NN-*.md` — the task currently in progress.
4. `infra/sql/001_init.sql` — schema is authoritative.
5. `render.yaml` — deployment topology is authoritative.

If you find a contradiction between these, **stop and ask**. Do not pick.

---

## 3. Task workflow

Tasks live under `tasks/` numbered `01`, `02`, ... Work strictly in numeric order. Each task file contains: **Goal**, **Inputs**, **Deliverables**, **Acceptance Criteria**, **Review Gate**.

### Per-task loop

```
1. Read tasks/NN-*.md and any files it references.
2. Create a branch:  task/NN-<short-slug>
3. Implement only what the task asks. No "while I'm here" refactors.
4. Run the task's local validation (build/typecheck/curl). Fix until green.
5. Commit with message:  task(NN): <summary>
6. Open a PR titled:     task NN — <task title>
7. PR body must include the "Review request" template (see §6).
8. STOP. Wait for the reviewer.
```

You **must not** start task `NN+1` until task `NN` is signed off.

---

## 4. Scope discipline

- Touch only files listed under **Deliverables** in the current task. If you genuinely need to touch something else, list it under **Out-of-scope edits** in the PR body and justify each one in one line.
- No new dependencies unless the task allows them. New deps need explicit reviewer approval.
- No infrastructure changes (`render.yaml`, `infra/sql/*`, GitHub Actions) outside the tasks that declare them.
- No tests unless a task asks for them. v1 demo, not v1 production.
- Do **not** generate placeholder/TODO code or commented-out blocks.

---

## 5. Quality bar (every task)

Before requesting review:

- `npm install` at repo root succeeds.
- The workspace(s) you touched build (`npm --workspace apps/<x> run build`).
- `tsc --noEmit` is clean in the touched workspace.
- Any HTTP endpoint you added returns the documented shape when curl'd locally.
- No secrets, tokens, or `.env` files are committed.
- No files larger than 200 KB unless the task allows them.

---

## 6. PR template (paste into every review-request PR body)

```
## Task
tasks/NN-<slug>.md

## What changed
- file path — one-line rationale
- file path — one-line rationale

## Out-of-scope edits
(list any file you touched that is NOT in the task's Deliverables, with a one-line justification — or write "none")

## Validation
- [ ] `npm install` clean
- [ ] `npm --workspace apps/<x> run build` succeeds
- [ ] `tsc --noEmit` clean
- [ ] Local check: <copy/paste of curl + response, or screenshot, or build log tail>

## Decisions I made (reviewer to confirm or reject)
- short bullet, one decision per line

## Open questions
- short bullet, one question per line — or "none"

## Ready for critique ✅
```

If you cannot tick all four validation boxes, **do not open the PR** — say so in chat and wait.

---

## 7. Critique → revision loop

The reviewer will leave critique either as inline comments on the PR or in a top-level comment using this format:

```
[MUST]   <change required to merge>
[SHOULD] <change strongly recommended>
[NICE]   <optional>
[ASK]    <question for you to answer>
```

Your response loop:

1. Address every `[MUST]` and `[ASK]`.
2. Address `[SHOULD]` unless you have a concrete reason not to, which you state in the reply.
3. Commit fixes to the same branch. Commit message: `fix(NN): <what changed>`.
4. Reply on the PR thread with a `Critique addressed` comment listing each item and "done" / "see comment".
5. Re-request review.

Do **not** force-push, rebase, or rewrite history once the PR is open. Add commits.

---

## 8. Stop conditions

Stop immediately and ask the reviewer if any of the following happens:

- The task as written is impossible or contradicts the PRD.
- Tests/local validation needs a credential you don't have.
- A library has a different API than the task assumes.
- You discover a bug or design flaw in the PRD itself.
- A `MUST` from the reviewer conflicts with the PRD.
- You'd need to write more than ~400 lines of code that isn't in the task's spec.

Asking is free. Guessing is not.

---

## 9. Environment expectations

- Node 20+.
- Postgres available locally for tasks `02–04` (Docker is fine).
- `SAPIOM_API_KEY`, `GITHUB_TOKEN`, `GIT_PUSH_TOKEN`, `RENDER_API_KEY`, and the **per-agent secret(s)** matching `CODING_AGENT` and `FALLBACK_AGENT` (e.g. `CURSOR_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`) are available **only** for tasks that explicitly use them. Other tasks should be implemented without them and stubbed in tests if needed.
- `CODING_AGENT` / `CODING_MODEL` choose the primary agent CLI run inside the Sapiom sandbox; `FALLBACK_AGENT` / `FALLBACK_MODEL` choose the single retry agent if the primary fails. Defaults: primary `cursor` / `composer-2.5`, fallback `gemini` / `gemini-3.5-flash`.
- Never log secrets. Never commit `.env`. `.env.example` is the only env file in git. Use the `redact` helper in `apps/api/src/lib/log.ts` for anything that prints sandbox stdout/stderr.

---

## 10. Definition of "done"

A task is done when:

1. The PR is merged into `main` by the reviewer.
2. CI (if configured) is green.
3. The PRD has been updated if behaviour shifted — by the reviewer, not by you, unless the task explicitly asks.

The overall demo is done when the **§10 acceptance criteria in `PRD.md`** are satisfied on three different descriptions in a row.
