# Build a tool — reusable agent brief

Hand this file to an implementing agent (Codex / Claude) to build **one tenwhy tool CLI**.
Fill in the block at the top, then give the agent the whole file. The agent works in that
tool's own repo and builds against the published kit.

> **Prerequisite:** `@tenwhy/agent-cli-kit` + the `create-tenwhy-tool` template must already
> exist (see [`/tool` §0](https://tenwhy.pages.dev/tool#kit)). If they don't, build the kit
> first — this brief assumes them. (For a throwaway/standalone CLI with no kit, say so and
> ask for the kit-free variant instead.)

## Fill this in

```
TOOL            <name>                  # e.g. seo, research, catalog
SPECIALIST      <persona>               # the agent that runs it — e.g. max, tom, jon
PURPOSE         <one line: what it does, and when it's used>
KIND            read-only | has-writes  # pipeline only, or plan/apply mutations
COMMANDS        <verbs>                 # e.g. audit · plan · apply
RESULT SCHEMA   <tool.kind@version>     # e.g. seo.audit@1
EXTERNAL        <services it calls>     # LLM gateway, scraping service, a provider API, …
```

---

## The brief (give the agent this + the filled block)

You're building the **`<TOOL>`** CLI — one tenwhy tool, run by **`<SPECIALIST>`**. It must
**conform to the contract**: uniformity across tools beats per-tool cleverness, because the
users are agents.

**Read first — these are authoritative, don't re-derive them:**
- **[`CONTRACT.md`](CONTRACT.md)** — the rules: the `{ok, data, error, meta}` envelope,
  canonical verbs, exit-code taxonomy, plan/apply, `--describe`, enumerated errors, bounded
  output, conformance.
- **[`/tool`](https://tenwhy.pages.dev/tool)** — the how-to: stack (TypeScript · Node 20 ·
  Stricli via the kit · esbuild bundle · one repo per tool), scaffold, the `defineCommand`
  API, the pipeline + plan/apply patterns, `SKILL.md`, verify.

**Build it:**
1. **Scaffold its own repo:** `create-tenwhy-tool <TOOL> --agent <SPECIALIST>`. One repo per
   tool, depending on the published `@tenwhy/agent-cli-kit`. **Never reimplement the
   contract** — the kit does it once; you write only tool logic.
2. **Write each command** with `defineCommand({ verb, rw, input: zodSchema, result, run })`.
   The kit handles the envelope, the universal flags, exit-code mapping, `--describe`, and
   bounded output. Throw `ctx.error('CODE', …, { allowed, got })` for enumerated errors.
3. **If KIND = read-only** → the **pipeline pattern**: idempotent stage subcommands reading
   and writing JSON artifacts in the run dir (scratch); side-effect-free / replayable (an
   LLM stage may vary — the *write* is dedup-keyed); record `model + prompt + input` versions.
4. **If KIND = has-writes** → **plan / apply**: `plan` emits an enforceable changeset (item
   `id`, `params`, `idempotency_key`, `preconditions`, plus plan-level `checksum`,
   `policy_version`, `expiry`); `apply` runs **only** an approved plan ref. Your CLI only
   *proposes* — the platform gate recomputes impact from raw params + read-back, and the
   broker executes. (Read-only tools simply have no write verbs.)
5. **Result + outcome:** register the `<RESULT SCHEMA>`; every result populates the
   cross-fleet outcome — `meta.outcome = { unit, projected, realized, cost_usd, confidence }`.
6. **Identity:** store nothing — no `login`, no profiles. Read scoped creds from `env`
   (injected per job). External *writes* are proposed, not executed in the tool.
7. **`SKILL.md`:** two lines — purpose + when-to-use + the command list. Reference the
   contract; don't repeat it.

**Definition of done** (`/tool` §10):
- Canonical verbs only; any pipeline stage verbs **declared in `--describe`**, never guessed.
- Every command: Zod input, returns `data` + `meta.outcome`; the kit owns the envelope.
- Mutations go through `plan → gate → apply`; `apply` takes only an approved plan ref.
- No stored secrets; registered, versioned result schema; two-line `SKILL.md`.
- **`agent-cli-kit verify` green in CI**, and the failure-path tests pass.

**Rules:** conform to the contract, don't drift per-tool, and if something is genuinely
undefined (not merely unstated-but-obvious), **ask — don't guess.**
