# The tool contract — v0

**`contract_version: 0`**

The normative spec every tenwhy tool CLI conforms to. It is the foundation the
shared runtime (`agent-cli-kit`) implements once and the `verify` command checks
mechanically in CI. A tool that fails `verify` does not ship — this is the
Reviewer gate from [design §9](design.html) made concrete.

Downstream of [design §9 (the job contract)](design.html) and
[§10 (what a tool is)](design.html); it pins the detail those sections leave open.
When this spec and the design conflict, the design wins — stop and reconcile.

---

## 0 · Two contracts, one nesting

There are **two** contracts at two layers. Don't confuse them.

| | Job contract ([design §9](design.html)) | **Tool contract (this file)** |
|---|---|---|
| Between | Maestro ⇄ µVM | specialist/harness ⇄ CLI |
| Medium | HMAC-signed HTTP, over the wire | subprocess: argv in, stdout/stderr/exit out |
| Governs | how a job is fired and reported | how a CLI behaves when invoked |

They nest cleanly: inside one µVM job, the harness invokes one or more CLI
commands **per this contract**, then reports the aggregate **per the job
contract**. The two evolve and version independently.

---

## 1 · Command shape & canonical verbs

```
<tool> <resource> <verb> [flags]      # resource-shaped tools
<tool> <verb> [flags]                 # flat / pipeline tools
```

Three verb families, and nothing else:

- **CRUD** — `get` (one), `list` (many), `create`, `update`, `delete`.
- **Mutation** — `plan`, `apply` (see §8).
- **Pipeline stages** — the named transforms of a pipeline tool: e.g.
  `scrape`, `extract`, `analyze`, `synthesize`, `crawl`, `audit`, `score`.

**Forbidden synonyms, always:** `info`, `ls`, `show`, `fetch`, `rm`, `new`,
`make`, `run`. Agents are trained on the canonical verbs; every synonym is a
hallucination surface. Enforced by `verify`, not by code review — *manual
consistency through review is Swiss cheese.*

Every verb is classified **read** or **write** and that classification is
surfaced in `--describe` (§9). Reads never mutate external state; writes go
through §8.

---

## 2 · The output envelope

In `--json` mode every command emits **exactly one** JSON object to stdout, then
exits. Same shape for success and failure:

```json
{
  "ok": true,
  "contract_version": 0,
  "tool": "seo",
  "command": "audit",
  "data": { },
  "error": null,
  "meta": {
    "schema": "seo.audit@1",
    "duration_ms": 8124,
    "cost_usd": 0.0142,
    "llm_tokens": 9310,
    "pagination": { "limit": 50, "returned": 50, "total": 380, "next_cursor": "eyJvIjo1MH0" },
    "truncated": true,
    "truncation_hint": "330 more issues — add --severity=high or --limit=400",
    "run_dir": "/run/seo-7f3a"
  }
}
```

| Field | Rule |
|---|---|
| `ok` | bool. `true` ⟺ `data` present and `error` null. |
| `contract_version` | int. The contract major this binary targets (mirrors `contract_version` in the tool's `spec.yaml`). |
| `tool`, `command` | strings. Echo the invocation so logs are self-describing. |
| `data` | object. Command-specific payload. Tagged by `meta.schema`. Present iff `ok`. |
| `error` | object or null. See §4. Present iff `!ok`. |
| `meta` | object. Always present. Timing, cost, pagination, truncation, schema ref, run dir. |

`meta.cost_usd` and `meta.llm_tokens` exist so the harness can sum them into the
job-contract response's `cost_usd` / `llm_tokens_used` without re-instrumenting.

---

## 3 · Universal flags

Every tool accepts all of these. The kit provides them; tools never redefine them.

| Flag | Effect |
|---|---|
| `--json` | Emit the envelope (§2). **Not** `--agent`, **not** `--format=json` — one spelling, fleet-wide. Agents always pass it. |
| `--describe` | Print the machine introspection doc and exit 0 (§9). |
| `--dry-run` | Do everything except the side effect. For `apply`, validate the plan and report what *would* execute. |
| `--fields a,b.c` | Project the `data` payload to these paths. Reduces tokens; never changes the envelope shape. |
| `--limit N` | Bound a list. Has a sane default (§6); `0`/absent never means "unbounded". |
| `--force` / `--yes` | Proceed past a confirmation a human would get. Agents pass it; it never widens a §8 policy gate. |
| `--no-input` | Hard guarantee of non-interactivity: any prompt becomes an error, not a hang. |
| `--wait` | On a command that submits to a slow **external** API, block until it settles instead of returning a pending handle (§8). |
| `--run-dir PATH` | Where pipeline artifacts are read/written (§7). Defaults to a fresh temp dir. |

**Non-interactive by default.** A CLI invoked without a TTY never prompts.
Human-readable tables/colour are emitted only on a TTY; ANSI is suppressed
otherwise. Inside a µVM there is no TTY, so machine output is the default path,
not a flag agents must remember.

---

## 4 · Errors that teach

When `ok` is false, `error` is:

```json
{
  "code": "INVALID_ENUM",
  "message": "--severity must be one of: low, medium, high (got: 'urgent')",
  "retryable": false,
  "allowed": ["low", "medium", "high"],
  "got": "urgent"
}
```

- `code` — stable, screaming-snake, part of the tool's API. Agents branch on it.
- `message` — one line, **enumerates valid values** when rejecting an enum, so
  the agent self-corrects on the *next* call instead of round-tripping to `--help`.
- `retryable` — whether retrying the same invocation could succeed (true for
  transient upstream failures; false for usage/policy errors).
- `allowed` / `got` — present for enum and range rejections.

The same `error` objects are what the harness forwards as the job contract's
structured `errors[]` — and they are first-class self-improvement telemetry
(every rejection is a labelled "the agent got this wrong").

---

## 5 · Exit codes & streams

**stdout is data, stderr is diagnostics — always.** The envelope is the only
thing on stdout in `--json` mode. Logs, progress, and human chatter go to stderr.

| Code | Meaning | Agent's move |
|---|---|---|
| `0` | success (`ok:true`) | continue |
| `1` | internal / unexpected | report; maybe retry once |
| `2` | usage error — bad flags or args | fix the invocation |
| `3` | input/precondition — missing artifact, malformed plan | fix the input |
| `4` | upstream/external failure | retry (`retryable:true`) |
| `5` | policy/guardrail rejection (§8) | **do not retry** — needs approval |

Exit code and `error.code` always agree. Code `5` is the one an agent must never
brute-force: it means a human gate, not a transient failure.

---

## 6 · Bounded output

Lists paginate with a **bounded default** (the kit sets it; tools may lower it).
When output is truncated, `meta.truncated` is `true` and `meta.truncation_hint`
names the flag that widens it. Summarise before detailing: a `list`/`audit`
returns counts and top items, and a `get` returns the full object on demand.

This is a token-budget guard as much as a UX one: an unbounded result blows the
specialist's context window *inside* the µVM, before it ever reaches Maestro.

---

## 7 · The pipeline contract (read path)

Pipeline tools are a chain of **idempotent stage subcommands** that read and
write JSON artifacts in the run dir:

```
scrape  → run-dir/scrape.json
extract → reads scrape.json   → run-dir/extract.json
analyze → reads extract.json  → run-dir/analyze.json
```

- **Idempotent**: re-running a stage on the same inputs yields the same output.
- **The run dir is scratch, not state.** It lives and dies with the µVM. Durable
  state is the platform's job (§11) — Postgres, R2, the brain repo.
- **Resumable**: a later stage can be re-run against an earlier stage's artifact
  without redoing the whole chain.
- **Replayable**: because the platform archives stage inputs to R2, a *new*
  version of `analyze` can be run against *last month's* `scrape.json` — free
  regression testing every time a stage changes.

---

## 8 · The mutation contract (write path) — plan / apply

Nothing mutates external state except through `plan` → gate → `apply`. Terraform
semantics, because we don't trust an agent's self-certification before money or a
live site moves.

```
audit/analyze ─▶ plan  (writes plan.json: a changeset)
                  │
            [ policy gate ]   ← deterministic, platform-side (not the CLI)
                  │
                apply --plan <ref>   (executes the approved plan only)
```

- `plan` emits a changeset artifact. Each **item** carries: stable `id`,
  `action`, `reason`, `projected_impact`, and the params to execute. This maps
  directly onto the job contract's `actions[]` (`proposal` → plan item;
  `validation` → gate verdict; `executed`/`outcome` → apply result).
- `apply` accepts **only** `--plan <ref>` — never free-form mutation args. It
  refuses a plan whose checksum doesn't match what the gate approved.
- **Idempotent execution**: each item has an id; `apply` reads external truth
  first and skips items already landed. **Partial success is a first-class
  status**, not an exception — report per-item `executed`/`outcome`.
- Every executed item writes an `action_log` row and a `history.html` entry, with
  `audit_path` anchoring back ([design §8](design.html)).
- The **policy gate is deterministic and platform-side** — within standing
  policy, `apply` proceeds unattended; outside it, the item waits behind an
  Approve card. The gate validates the *proposal*, never the proposer — so a
  smarter agent never weakens the guardrail. `--force` does not bypass it.

Read-only tools (research, audit) simply have **no write verbs**. Same
architecture, different verb classification — not a different kind of tool.

---

## 9 · Three-layer introspection

Three views of one tool, all **generated from the same Zod schemas** and kept in
sync mechanically — never hand-edited apart.

| Layer | Surface | Audience |
|---|---|---|
| 1 | `--help` | humans at a terminal |
| 2 | `--describe` (the *agent-context* doc) | **Maestro & the specialist** — routing |
| 3 | `SKILL.md` | the specialist — composition prose ([decision #23](design.html)) |

`--describe` emits machine JSON: every command, its verb family and
**read/write** class, its flags, its result schema id+version, and the
`contract_version`. Maestro routes on this; it never parses `--help`. Because
all three derive from the schema, "the docs drifted from the code" is structurally
impossible.

This makes fleet documentation collapse to **one fleet-level skill** ("every
tenwhy CLI obeys this contract") plus a two-line purpose stub per tool. A new tool
is agent-ready on day one with zero per-tool integration.

---

## 10 · Identity & secrets — injected, never stored

Tools hold **no** persistent identity. No `login`, no saved profiles, no config
file with credentials.

- Credentials arrive in the environment, fetched by the µVM at boot from Infisical
  via a single-use bootstrap token scoped to one job ([design §9](design.html),
  [S14](stack-map.html)).
- A tool reads `OPENROUTER_API_KEY`, a scoped `GITHUB_TOKEN`, etc. from `env` and
  never writes them anywhere.

This is a **deliberate divergence** from workstation CLIs (Ramp's `auth login`,
profile bundles). Those assume a long-lived machine that owns its identity. Our
tools run in ephemeral µVMs where a stored credential would be both useless (gone
at teardown) and a security regression (a secret outliving its 60-second scope).
Identity is injected per job, not remembered.

---

## 11 · Artifact delivery — platform-owned, by type

A CLI produces **artifacts in the run dir + the envelope on stdout**. It does
**not** route them onward — there is no `--deliver` flag and the CLI holds no R2
or webhook config.

The **harness** (kit code in the µVM) binds destinations by artifact type,
uniformly across every tool ([S3](stack-map.html)):

| Artifact | Destination | Who reads it |
|---|---|---|
| bulky raw output (crawl dump, full report) | Cloudflare R2 | replay, audit |
| human-readable synthesis + `history.html` | brain repo (git) | the customer |
| the envelope / structured result | job-contract webhook → validated → Postgres | Maestro, dashboard |

Keeping routing in the harness (not a per-call flag) is what makes it uniform:
the CLI stays a pure transform, and **only the platform writes Postgres, after
validation** — a misbehaving tool can return garbage but cannot corrupt
operational state.

---

## 12 · Conformance

`agent-cli-kit verify <tool>` mechanically asserts everything above: envelope
shape, universal flags present, canonical verbs only, enumerated errors, exit-code
taxonomy, bounded lists, `--describe` matches the schema, no stored credentials.
It runs in CI on every tool repo. Green `verify` is a ship gate, identical in
standing to lint and tests ([design §9 enforcement](design.html)).

---

## Out of scope for v0 (named, not solved)

- Wire encoding of `--describe` beyond "valid JSON from the schema" (no formal
  JSON-Schema export yet).
- Cross-tool transactions (one `apply` spanning two tools). Today each tool's
  `apply` is its own unit; Maestro sequences them via `next[]`.
- Streaming/progress on stdout. v0 is one-shot: one envelope, at the end.
- A formal deprecation policy for retiring an `error.code` or a verb.

## Versioning

Additive changes (new optional `meta` field, new `error.code`, new command) stay
within `contract_version: 0`. Anything that could break a conforming caller —
renaming a field, changing exit-code meaning, removing a flag — bumps the major.
Tools declare the major they target in `spec.yaml`; Maestro routes accordingly.
