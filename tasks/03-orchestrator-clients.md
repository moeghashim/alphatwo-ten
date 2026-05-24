# Task 03 — Orchestrator clients (`github`, `sandbox`, agent adapters, `render`)

## Goal
Build thin, testable client modules used by the orchestrator. No HTTP routes in this task. No orchestration logic.

## Inputs to read first
- `PRD.md` §4.1 (API), §5 (orchestrator flow), §6 (prompt + agent matrix), §7 (Render API)
- The existing `apps/api/package.json` (already scaffolded)

## Deliverables
```
apps/api/tsconfig.json
apps/api/src/env.ts
apps/api/src/lib/log.ts
apps/api/src/lib/github.ts
apps/api/src/lib/sandbox.ts
apps/api/src/lib/agents/index.ts
apps/api/src/lib/agents/cursor.ts
apps/api/src/lib/agents/claude.ts
apps/api/src/lib/agents/codex.ts
apps/api/src/lib/agents/gemini.ts
apps/api/src/lib/render.ts
```

You may not yet create `index.ts` or `routes/*` — that is task 04.

## Implementation notes

### `env.ts`
- Parse and validate `process.env` with `zod`.
- Required: `DATABASE_URL`, `SAPIOM_API_KEY`, `GITHUB_TOKEN`, `GIT_PUSH_TOKEN`, `GITHUB_OWNER`, `GITHUB_TEMPLATE_REPO`, `RENDER_API_KEY`, `RENDER_OWNER_ID`, `DATA_API_BASE_URL`.
- Coding agent: `CODING_AGENT` (enum `cursor|claude|codex|gemini`, default `cursor`), `CODING_MODEL` (string, default `composer-2.5`).
- Fallback agent: `FALLBACK_AGENT` (same enum or empty string to disable, default `gemini`), `FALLBACK_MODEL` (default `gemini-3.5-flash`).
- Per-agent secrets are **conditionally required**: only the secret(s) for the configured `CODING_AGENT` and `FALLBACK_AGENT` must be present. Validate with `superRefine`.
  - `cursor` → `CURSOR_API_KEY`
  - `claude` → `ANTHROPIC_API_KEY`
  - `codex` → `OPENAI_API_KEY`
  - `gemini` → `GEMINI_API_KEY`
- Optional with defaults: `PORT=8787`, `RENDER_REGION=oregon`, `RENDER_PLAN=starter`, `AGENT_TIMEOUT_MS=900000`, `BUILD_TIMEOUT_MS=300000`, `DEPLOY_POLL_MS=12000`, `JOB_TIMEOUT_MS=1800000`.
- Fail fast on missing values; print the missing keys.

### `log.ts`
- Single export `log(level, msg, meta?)`. Levels: `info|warn|error`.
- Plain JSON line to stdout. No external dep.
- Add a `redact` helper that scrubs values matching any known secret env var before logging.

### `github.ts` (uses `@octokit/rest`)
Exports:
```ts
createRepoFromTemplate(slug: string, description: string): Promise<{
  repoUrl: string;     // https URL (no token)
  repoName: string;    // owner/repo
  cloneUrlWithToken: string;  // https://x-access-token:GIT_PUSH_TOKEN@github.com/owner/repo.git
}>;
```

- `POST /repos/{template_owner}/{template_repo}/generate` with `owner=GITHUB_OWNER`, `name=app-{slug}-{shortId}` (use `nanoid(6)`), `private=true`, `include_all_branches=false`, `description=<truncated to 200>`. The authenticated `GITHUB_TOKEN` must belong to `GITHUB_OWNER` when `GITHUB_OWNER` is a user account.
- Poll `GET /repos/{owner}/{name}` until 200 (max 30 s, 1 s interval).
- No PR / merge helpers in alphatwo-ten — the sandbox pushes directly to `main`.

### `sandbox.ts` (Sapiom Compute / Blaxel microVM)
Exports:
```ts
interface SandboxHandle {
  id: string;
  exec(cmd: string[], opts?: { cwd?: string; env?: Record<string,string>; timeoutMs?: number }): Promise<{
    exitCode: number;
    stdout: string;
    stderr: string;
  }>;
  writeFile(path: string, contents: string | Buffer): Promise<void>;
  dispose(): Promise<void>;
  logUrl(): string | null;
}

createSandbox(opts: {
  image?: string;            // default: "node:20"
  envs: Record<string,string>;
  timeoutMs: number;         // hard wall-clock limit
}): Promise<SandboxHandle>;
```

- Thin wrapper over Sapiom's REST/SDK (look up in their docs; if SDK exists, prefer it; otherwise use `fetch` against `https://api.sapiom.dev` with `Authorization: Bearer ${SAPIOM_API_KEY}`).
- Sandbox image must already contain `git`, `node 20`, `npm`. If the chosen base image does not, the first `exec` should `apt-get install -y git` (or equivalent) — document this in code comments.
- `exec` returns combined timing info via `log`; truncate stdout/stderr to last 32 KB in the returned strings, but stream all output to the log redactor.
- `dispose` is best-effort and idempotent — always called in a `finally`.

### `agents/index.ts` + per-agent adapters
Exports:
```ts
type AgentName = "cursor" | "claude" | "codex" | "gemini";

interface RunInSandboxArgs {
  sandbox: SandboxHandle;
  repoDir: string;          // path inside sandbox where the cloned repo lives
  slug: string;
  description: string;
  model: string;
  signal?: AbortSignal;
}

interface AgentAdapter {
  name: AgentName;
  install(sandbox: SandboxHandle): Promise<void>;     // installs the CLI inside the sandbox
  run(args: RunInSandboxArgs): Promise<{ ok: boolean; lastMessage?: string }>;
}

getAgent(name: AgentName): AgentAdapter;
buildPrompt(slug: string, description: string): string;   // exact text from PRD §6.1
```

Per-agent install + run commands (run via `sandbox.exec`):

| Agent    | Install                                          | Run (headless)                                                      | Auth env                  |
|----------|--------------------------------------------------|----------------------------------------------------------------------|---------------------------|
| `cursor` | `npm i -g cursor-agent` (or pinned tarball)      | `cursor-agent --model <model> --non-interactive --prompt "$PROMPT"`  | `CURSOR_API_KEY`          |
| `claude` | `npm i -g @anthropic-ai/claude-code`             | `claude --print --model <model> "$PROMPT"`                           | `ANTHROPIC_API_KEY`       |
| `codex`  | `npm i -g @openai/codex`                         | `codex exec --model <model> "$PROMPT"`                               | `OPENAI_API_KEY`          |
| `gemini` | `npm i -g @google/gemini-cli`                    | `gemini --non-interactive -m <model> -p "$PROMPT"`                   | `GEMINI_API_KEY`          |

Notes for adapters:
- Each adapter writes `$PROMPT` to a file inside `repoDir/.agent-prompt.txt` and pipes via shell — never embed user description in a shell-interpolated string.
- All adapters honour `signal` by aborting the underlying `exec` (Sapiom should support `cancel`).
- All adapters return `ok=false` on non-zero exit; orchestrator decides fallback policy.

### `render.ts`
Plain `fetch` against `https://api.render.com/v1`, header `Authorization: Bearer ${RENDER_API_KEY}`.

```ts
createService(opts: {
  name: string;
  repoUrl: string;
  envVars: Record<string,string>;
}): Promise<{ serviceId: string; serviceUrl: string }>;

getLatestDeploy(serviceId: string): Promise<{
  deployId: string;
  status: "created"|"queued"|"build_in_progress"|"pre_deploy_in_progress"|"update_in_progress"|"live"|"build_failed"|"pre_deploy_failed"|"update_failed"|"canceled";
}>;
```

- `createService` posts the body from `PRD.md` §7.2 with `branch:"main"`, `autoDeploy:"yes"`, `serviceDetails.runtime:"node"`, `plan:RENDER_PLAN`, `region:RENDER_REGION`, `numInstances:1`, `healthCheckPath:"/api/health"`, build `npm ci && npm run build`, start `npm run start`, `renderSubdomainPolicy:"enabled"`.
- Return `serviceId` from response; `serviceUrl` from `serviceDetails.url` (fallback to `https://{name}.onrender.com`).
- Retry once on `429` with `Retry-After` honoured.

## Acceptance criteria

- [ ] `tsc --noEmit` clean inside `apps/api`.
- [ ] `npm --workspace apps/api run build` succeeds.
- [ ] No file under `apps/api/src/routes` or `apps/api/src/index.ts` is created.
- [ ] No client calls happen at module load — all are inside exported functions.
- [ ] `env.ts` fails fast when a key is missing (test by running `node -e "import('./dist/env.js')"` with an empty env), and only enforces per-agent secrets for `CODING_AGENT` + `FALLBACK_AGENT`.
- [ ] `getAgent('gemini').install(stub)` returns the right `npm i -g @google/gemini-cli` command (assert via a sandbox mock that records `exec` calls).
- [ ] Smoke (optional, with real keys): a tiny scratch script `createSandbox` → `exec(["node","-v"])` returns `v20.*`.

## Out of scope
- Orchestrator loop, routes, DB writes.
- Persistent queues or retries beyond 1× on 429.
- Webhooks.

## Review gate
Open PR titled **"task 03 — orchestrator clients"**. In the “Decisions” section, list:
- the exact Sapiom SDK/endpoint shape used,
- the exact CLI package + version pinned per agent.
