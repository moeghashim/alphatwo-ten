# Review response: tenwhy tool-execution & state architecture

Response to [`review-request.md`](review-request.md). Reviewed at commit `69c02b7`
against `design.html` (esp. §8 audit, §9 job contract, §10 what a tool is),
`CONTRACT.md`, `build.html` (two-impl plan, MVP loop, component map),
`stack-map.html` (Impl-1 stack, µVM lifecycle, auth/secrets §7).

This review was itself pressure-tested by a second reviewer; the corrections from
that pass are folded in. Where the first draft overreached, it says so inline.

---

## 1 · Verdict

**`sound-with-changes`.** The CLI contract (`CONTRACT.md`) is the strong core and is
close to best-in-class for the "uniformity beats per-tool cleverness" goal — the
*tool* layer genuinely scales. What is missing is not a vendor but a
**specification**: the durable orchestration semantics that your three hardest
guarantees ("crash/re-run anywhere, zero data loss, no double-effect," "no tool moves
money outside policy," "results comparable across the fleet") all silently depend on.
Today those are asserted in prose, not pinned in a contract. This is the best *shape*
— keep the ephemeral µVM tools, the storage-by-lifetime split, plan/apply, and the
CLI contract — but it is incomplete in exactly the place that will produce your first
real incident. Fill the orchestration gap and tighten where writes and money are
trusted, and it's the right architecture, not merely an acceptable one.

## 2 · Is there a better architecture?

Not a different shape — a **missing layer** in this one. Do **not** rip out the µVM
model, the brain/Postgres/R2 split, or plan/apply. The change is to define a
**durable orchestration boundary** and decide its backend second.

```
                         keep                              add (the missing spec)
 +-------------------------------+     +--------------------------------------------+
 | CLI contract (CONTRACT.md)    |     | durable orchestration semantics            |
 | ephemeral Node-only uVM tools |     |  - job state machine: queued -> dispatched |
 | brain / Postgres / R2 split   |     |    -> running -> awaiting_approval ->       |
 | plan / apply + policy gate    |     |    applying -> {succeeded|partial|failed|   |
 +-------------------------------+     |    timed_out}                              |
                                       |  - idempotency ledger (per apply item)     |
                                       |  - outbox (dispatch) / inbox (webhook),    |
                                       |    unique(job_id,event_type,external_id)   |
                                       |  - leases + per-agent no-overlap locks     |
                                       |  - approval = durable wait (hrs/days)      |
                                       |  - reconciliation: effect-happened-but-    |
                                       |    webhook-lost                            |
                                       +--------------------------------------------+
```

**Backend choice is downstream of the spec, not the headline.** For MVP this is a
Postgres-backed state machine with a transactional outbox/inbox — no new vendor. A
durable engine (Inngest/Restate fit the event+webhook+HTTP shape better than Temporal
here) is justified later, when approvals sit for days, multi-step specialist chains
become common, or homemade leasing gets fragile — and only if it lives behind the
*same* orchestration interface on both impls.

**Crucial caveat (corrected from the first draft):** a durable engine gives you
timers, retries, waits, and completion correlation — it does **not** give you
exactly-once external effects, trustworthy audit, or spend caps. Those come from
idempotency keys, credential scoping, and platform-side ledgers regardless of engine.
Do not let "we added Inngest/Temporal" create false confidence about double-effects.

**Model the µVM as an external async activity, never a durable worker.** Durability
lives in the platform layer that dispatches, waits, dedupes, validates, and finalizes;
the specialist stays ephemeral. This is the one place the durable-engine idea
genuinely fights the µVM model, and the resolution is to keep them on opposite sides
of the boundary.

## 3 · Strongest objections (ranked by defensibility)

### 3.1 — "No double-effect" rests on per-item external idempotency that nothing enforces. *(very high)*
`CONTRACT.md §8`: "each item has an id; `apply` reads external truth first and skips
items already landed." Scenario: apply lands a Meta bid change → µVM posts webhook →
Maestro mid-deploy, webhook lost → µVM torn down → Maestro times out, no outcome →
re-fires apply → effect re-applied **unless** the external API lets you read "did *my*
item-id land?" Many APIs can't, or require an idempotency key attached *before* the
write. The contract asserts the skip but mandates no mechanism, and `verify` can't
test it.
**Fix:** engine-issued idempotency key per apply item → external idempotency key where
supported; "record intent → execute → confirm" two-phase where not; an `action_items`
ledger (job_id, plan_item_id, external_idempotency_key, before/after snapshot)
independent of any engine. A durable engine alone does **not** fix this.

### 3.2 — The customer-facing audit is authored by the least-trusted component, and the docs contradict themselves. *(high)*
`design §8` says the brain commit happens *inside the µVM run* alongside the writes;
`CONTRACT.md §11` and `build.html` MVP step 5 say only the platform writes Postgres
after validation, and the µVM commits the brain directly. So the record `design §8`
sells to third-party auditors as "cryptographically auditable" is written by the
untrusted tool; the signature proves "a µVM with our token wrote this text," not "a
validated action occurred."
**Fix (narrowed — do NOT centralize all writes):** the **platform finalizes** —
validates the envelope, dedupes the webhook, verifies the plan checksum, optionally
reads back external state, writes `action_log`, renders the canonical
`history.html`/`timeline.html` entry from a trusted template over validated data, and
**commits it to the customer's git brain using the scoped token**. Tools still
*author* report content, evidence bundles, and proposed brain updates. The git brain
stays customer-owned and exportable; only *authority* over canonical audit moves.
Centralizing content *generation* would destroy the near-free-N+1 goal — keep the
platform a generic finalizer, not a domain author.

### 3.3 — `agent-cli-kit verify` is a quality gate, not a security boundary, but the docs lean on it as one. *(high)*
`CONTRACT.md §12` claims `verify` asserts "no stored credentials," and §1/§8 lean on
it for "reads never mutate," "writes go through §8." CI can check *shape* (flags,
envelope, exit codes, schema metadata, bounded lists). It cannot prove: reads don't
mutate, writes only via plan/apply, no credential exfiltration (a tool can write a
secret to the R2/brain it legitimately holds), truthful `cost_usd`/`projected_impact`,
real idempotency, or bounded egress. Since fear #2 is "an agent corrupts state /
spends money," the actual boundary must be runtime.
**Fix:** state in `CONTRACT.md §12` that conformance ≠ security; enumerate runtime
controls in `stack-map §7` (per-job scoped + separate read/write creds, enforced
egress allow-listing, brain-path allowlist, webhook schema validation, signed tool
releases). Confirm Sapiom/Daytona actually enforce `constraints.allow-listed
endpoints` at the network layer — if not, "no tool spends money wrongly" has no teeth.

### 3.4 — Injected-identity has under-specified failure edges that are central, not peripheral. *(high)*
`CONTRACT.md §10` / `stack-map §7`: 60s single-use bootstrap token, 1h GitHub
installation token, per-job HMAC secret. Unhandled: slow boot or failed first fetch vs
the 60s window; a job exceeding the 1h GitHub token; **retrying a job needs fresh
credentials without re-causing the external effect** (ties to 3.1); webhook replay
needs a nonce/event-id window; secret scope should differ between `plan` (read) and
`apply` (write); register-once secrets (APIs that issue a non-retrievable credential
on registration) have no path under "store nothing."
**Fix:** specify token-refresh/retry semantics, plan-vs-apply scope split, webhook
replay protection, and a sanctioned escape hatch (tool emits a new credential in the
envelope → platform writes Infisical).

### 3.5 — Spend caps are self-reported, and unenforced on Impl 1. *(high)*
`design §9` enforces the per-customer cap by summing self-reported `cost_usd` at
Maestro; a crashed job reports nothing, an under-reporting tool evades it. Impl 2 has
`stripe projects billing update --limit` (provider-side); Impl 1 has no equivalent and
the cost ceiling is still OPEN on `design §13` + `stack-map §9`.
**Fix:** distinguish LLM/runtime cost from external ad/API spend; enforce a
**preflight monthly cap before dispatch** plus **provider-side hard limits** on both
impls; use reported `cost_usd` for accounting/reconciliation only, never enforcement.

### 3.6 — The "deterministic, platform-side gate" can be bypassed because it consumes a tool-authored proposal. *(medium-high)*
`CONTRACT.md §8` plan items carry `projected_impact`, authored by the proposer.
Nothing forbids the gate from deciding on it. If the gate reads "−$42/day, within
cap," a tool that under-reports walks through, then `apply` does more.
**Fix:** forbid gate decisions based on tool-authored impact; the gate recomputes the
bound deterministically from raw `params` + live external read-back. Add plan expiry /
re-validation at apply time (an approval card sitting for days against stale external
state is a TOCTOU hazard).

### 3.7 — Recurring-as-cycles needs leases and backpressure, not just cron. *(medium-high)*
Daily/weekly/24/7 shifts (`stack-map §2`, decision #22) over many customers produce:
thundering herd at schedule boundaries, overlapping runs for the same agent/customer,
retry storms, stale runs applying old plans, cost-cap races, unbounded backlog.
**Fix:** per-customer concurrency limits, per-agent no-overlap locks, run coalescing,
schedule jitter, max-attempts + dead-letter, explicit **skip-vs-catch-up** for missed
shifts. Also: 24/7 Sal (support) is a poor fit for boot-a-µVM-per-event latency/cost —
the uniform ephemeral-cycle model may need a warm path for latency-sensitive,
high-frequency work.

### 3.8 — "Tools are pure functions / idempotent stages" is false on the LLM hot path. *(medium)*
`CONTRACT.md §7`: "re-running a stage on the same inputs yields the same output." But
`analyze`/`synthesize` call an LLM — same input, different bytes.
**Fix:** rename the property to **side-effect-free / replayable** (the *write* is
dedup-keyed; the *output* is not deterministic), and record `model + prompt + input`
versions so replay-as-regression-test is meaningful. Framing fix, not a teardown — but
proposal #1's "pure function of inputs" wording oversells it.

### 3.9 — Node-only base forces sidecar sprawl; per-boot `git clone` is on the hot path. *(low-medium)*
`stack-map §3` base = "Node 20, git, curl, jq" — no browser. Scraping is correctly
offloaded to Scrapling-as-a-service, but QA screenshots (Sid), API-less ad UIs, and
PDF rendering have nowhere to go without growing the image or spawning a service each.
And `git clone tenwhy-tools/<name>` per boot is a latency + GitHub-availability
dependency.
**Fix:** name the "Node-only ⇒ non-Node-is-a-service" boundary explicitly; prebake
tool images / shallow-clone / pull from R2. (Architecturally minor — Node-only is a
deliberate, defensible simplicity choice.)

## 4 · What we'd regret in 12 months

**The single load-bearing assumption most likely wrong: that "fire µVM → await HMAC
webhook" is sufficient orchestration, so durable semantics never get written down.**
It holds for read-only tools and the MVP, and fails the first time an `apply` lands a
money move and the completion webhook is lost (deploy, restart, blip) — leaving a job
whose *effect* happened but whose *record* didn't, and a re-fire that double-applies
because external-idempotency-by-id wasn't actually there (3.1). Cheap to fix now (write
the job state machine + ledger before apply-tools ship), expensive later (reconciling
money by hand). The "pure function" framing (3.8) is the conceptual error that makes
this feel safe.

## 5 · Changes to make before committing (keyed to files)

1. **`design.html` (new §) + `CONTRACT.md` (new §):** Specify **durable orchestration
   semantics** — job state machine, `action_items` idempotency ledger, outbox/inbox
   with `unique(job_id, event_type, external_event_id)`, leases, durable approval
   waits, effect-happened-but-webhook-lost reconciliation. Backend = Postgres for MVP;
   a durable engine is a later swap behind this interface. (3.1, 3.7, §2.)
2. **`CONTRACT.md §8`:** Mandate a concrete idempotency mechanism per apply item
   (engine-issued key → external idempotency key where supported; "record intent →
   execute → confirm" where not). Kit-implemented, not contract-assumed. (3.1.)
3. **`design.html §8` ↔ `CONTRACT.md §11`:** Resolve the conflict toward
   **platform-finalized audit**: platform validates and renders the canonical
   `history.html`/`timeline.html` from a trusted template over validated data, then
   commits to the customer's git brain with the scoped token. Tools still author
   content/artifacts/proposed updates. (3.2.)
4. **`CONTRACT.md §12` + `stack-map §7`:** State that `verify` is a quality gate, not a
   security boundary; enumerate the runtime controls. Confirm the sandbox enforces
   egress. (3.3.)
5. **`CONTRACT.md §10`:** Specify token-refresh/retry semantics (slow boot, 1h GitHub
   token vs long jobs), plan-vs-apply scope split, webhook replay nonces,
   retry-without-re-effect, and the register-once-secret escape hatch. (3.4.)
6. **`design.html §9` + `stack-map §9`:** Enforce per-customer spend as **preflight cap
   before dispatch + provider-side hard limit on both impls**; `cost_usd` for
   reconciliation only. (3.5.)
7. **`CONTRACT.md §8`:** Forbid gate decisions based on tool-authored
   `projected_impact`; require deterministic recomputation from `params` + external
   read-back; add plan expiry / re-validation at apply time. (3.6.)
8. **`build.html` (component map):** Abstract `Queue/background` behind a common
   scheduler/event interface so Render Cron (Impl 1) and Inngest (Impl 2) both deliver
   the *same* platform events to the *same* job-state-machine code; add a conformance
   suite both impls must pass. (Portability — this is an un-abstracted *risk*, not yet
   a proven violation.)
9. **`CONTRACT.md §7` + proposal #1 wording:** Rename "pure function / idempotent
   output" to "side-effect-free / replayable"; record `model + prompt + input`
   versions. (3.8.)
10. **`stack-map §3`:** Document the "Node-only ⇒ non-Node-is-a-service" boundary;
    replace per-boot `git clone` with prebaked images / shallow clone / R2 artifacts.
    (3.9.)
11. **`CONTRACT.md §11` (data spine):** "Comparable across the fleet" is oversold —
    JSONB tagged `tool.kind@version` is queryable, not comparable. Add a small
    **mandatory cross-fleet outcome sub-object** (`cost`, `projected_impact`,
    `realized_impact`, a fixed set of dims) every result populates, and require the
    platform to **validate `data` against the registered schema for `meta.schema` at
    ingest** (reject on mismatch).
12. **`CONTRACT.md §1`:** Pipeline stage verbs are an open set ("e.g. scrape,
    extract…"), contradicting the §1 anti-hallucination rationale. Either enumerate the
    fleet-wide stage verbs or concede they're a per-tool learning surface — don't claim
    "canonical verbs only" with a hole in it.

---

## Appendix · Objections that were demoted or dropped after pressure-testing

- **"Orchestrator decision space breaks at 30 tools"** — demoted as speculative
  (roadmap is 12 specialists, ~1 tool each). The defensible, narrower version is
  "routing evals and tool-selection metadata are unspecified," folded into changes
  11–12.
- **"Two contracts are accidental complexity"** — dropped. The job/tool split is sound;
  the real risk is **schema drift at the harness seam** (the adapter between the CLI
  envelope and the job-contract response), which is currently assigned to neither
  `verify` nor the Reviewer. Assign harness conformance somewhere.
- **"Move ALL writes platform-side"** (first-draft form of 3.2) — corrected as
  over-broad; it would re-centralize domain logic in Maestro and kill the near-free
  N+1 goal. See 3.2 for the narrowed version.
