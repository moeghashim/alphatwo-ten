# Build the kit — agent brief for `@tenwhy/agent-cli-kit`

Hand this to an implementing agent to build **the kit** — the shared runtime every tenwhy
tool CLI is built on. This is the **prerequisite** for [`BUILD-A-TOOL.md`](BUILD-A-TOOL.md):
build the kit first, then tools are thin.

The kit's whole job: **implement the contract once** so a tool author writes only tool
logic. The code examples in [`/tool`](https://tenwhy.pages.dev/tool) *are* the kit's intended
interface — your job is to make them real.

## Read first — authoritative
- **[`CONTRACT.md`](CONTRACT.md)** — the spec you are implementing, end to end (envelope,
  canonical verbs, exit codes, plan/apply, `--describe`, enumerated errors, bounded output,
  conformance). The kit **is** this, in code.
- **[`/tool`](https://tenwhy.pages.dev/tool)** — the developer experience the kit must
  deliver. **§0 lists the exact surface** to provide.

## What you're building
Two things, in one **monorepo**, published as **`@tenwhy/agent-cli-kit`**:
1. **The kit** — the runtime + the `defineCommand` API tool authors program against.
2. **`create-tenwhy-tool`** — the scaffolder + starter template that stamps out a conforming
   tool repo wired to the kit.

## Stack (locked)
TypeScript · Node 20 · **Stricli** (wrapped — tools never import it directly) · **Zod** (one
schema drives input validation, the result, and `--describe`) · **esbuild** (bundle to JS) ·
**npm workspaces** monorepo. Targets `contract_version: 0`.

## The surface to implement (from `/tool` §0)

| Export | Must do |
|---|---|
| `defineCommand({ verb, rw, input, result, run })` + `z` | The command API. `input` is a Zod schema; `run({ input, ctx })` returns `{ data, outcome }`. Re-export Zod as `z` so tools import only the kit. |
| The runner / entrypoint | Wrap Stricli: parse args, **validate input against the Zod schema**, run the command, emit the `{ok,data,error,meta}` envelope on `--json`, map errors → the exit-code taxonomy, bound list output (pagination + `meta.truncated` + hint), provide the universal flags (`--json`, `--describe`, `--dry-run`, `--fields`, `--limit`, `--force`/`--yes`, `--no-input`, `--wait`, `--run-dir`), non-interactive by default, **stdout = data / stderr = diagnostics**, TTY detection. (CONTRACT §2–6.) |
| `--describe` generator | Emit the machine schema from the Zod defs: `{ contract_version, tool, commands: [{ name, verb, tier, rw, flags, result_schema }] }`. Maestro routes on this. (CONTRACT §9.) |
| `ctx` (run context) | Helpers handed to every `run`: `error(code, msg, {allowed, got})` (enumerated, CONTRACT §4), `cost()`, `idem()`, `applyPlan(ref)`, run-dir read/write, and egress-allow-listed clients for the LLM gateway + scraping service. |
| plan / apply | The enforceable plan artifact — item `id` / `params` / `idempotency_key` / `preconditions`, plus plan-level `checksum` / `policy_version` / `expiry` — and an `apply` that runs **only** an approved plan ref. The gate + broker live in the platform; the kit emits/consumes the artifact shape. (CONTRACT §8.) |
| result + outcome | Tag results `tool.kind@version`; require every result populate `meta.outcome = { unit, projected, realized, cost_usd, confidence }`. (CONTRACT §11.) |
| `verify` | `agent-cli-kit verify <tool>` — assert envelope shape, canonical verbs only, enumerated errors, exit codes, bounded lists, `--describe` matches the schema, no stored credentials. The CI ship gate. (CONTRACT §12.) |
| harness-seam adapter | Map a CLI envelope → a job-contract response (design §9); ship a harness-conformance test so the two contracts can't drift. (CONTRACT §12.) |
| `create-tenwhy-tool <name> --agent <persona>` | Scaffold a tool repo: `spec.yaml`, `SKILL.md` stub, `src/index.ts` (kit entry), `src/commands/`, `src/schemas/`, `test/`, `package.json` depending on the published kit. |

## Verbs (CONTRACT §1)
Enforce the **two tiers**: a *closed* fleet-wide set (`get · list · create · update · delete`
+ `plan · apply`) the runner knows; tool-local **stage verbs** are an *open* set the tool
declares and the kit surfaces in `--describe` — never guessed. Reject the forbidden synonyms
(`info`, `ls`, `show`, `fetch`, `rm`, `new`, `make`, `run`).

## Acceptance — prove the kit works
Build a trivial **reference tool** on the kit (e.g. `hello`: a `get` + a `list`, plus a no-op
`plan`/`apply`) and show:
- `hello get --json` → a valid envelope; bad input → an **enumerated** error + exit 2.
- `hello list --limit 1 --json` → bounded output with a truncation hint in `meta`.
- `hello --describe` → the machine schema, matching the Zod defs.
- `agent-cli-kit verify hello` → **green**; then break one rule and show verify **catches it**.
- `create-tenwhy-tool demo --agent max` → a repo that builds + passes verify out of the box.

## Definition of done
- A command written with only `defineCommand` gets the **entire contract for free** (envelope,
  flags, exit codes, `--describe`, bounded output) — zero contract code in the tool.
- Stricli is fully wrapped; tools never import it.
- `verify` is real and catches violations; the reference tool **and** a freshly-scaffolded
  tool both pass it.
- Published as `@tenwhy/agent-cli-kit`; `create-tenwhy-tool` works end to end.

## Rules
The kit **is** `CONTRACT.md` in code — match it exactly, no per-tool escape hatches. If the
contract is ambiguous on a point, follow `/tool`'s examples; if still unclear, **ask — don't
guess.**
