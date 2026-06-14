# Review request: tenwhy tool-execution & state architecture

You are reviewing an architecture decision for **tenwhy** before we commit it.
You are running **inside the repo** — read the source of truth first, then judge
the proposal below against it.

**Be harshly critical. We do not want validation — we want to find what's wrong
now, while it's cheap.** Skip all praise. Assume we are too close to this to see
its flaws. The central question is not only "is this sound?" but **"is this the
best way to achieve the goals below?"** — if a materially different architecture
would serve those goals better, say so plainly and describe it, even if it means
discarding large parts of this proposal.

## Read these first (this repo)

- `AGENTS.md` — orientation + source-of-truth hierarchy.
- `design.html` — the architecture (the locked decisions, the workforce, Maestro,
  the brain, **§8 audit**, **§9 the job contract**, **§10 what a tool is**).
- `build.html` — the implementation plan (two parallel impls, the MVP proving
  loop, the build phases).
- `stack-map.html` — the concrete Impl-1 vendor stack (Render, Sapiom µVMs,
  Infisical, Postgres+RLS, R2, GitHub brains) and the µVM life cycle.
- `CONTRACT.md` — **the tool contract v0** (the new artifact under review): CLI
  envelope, canonical verbs, exit codes, plan/apply, injected identity, three-layer
  introspection, conformance.

The four HTML docs render as styled pages; read them as source. `CONTRACT.md` and
this file are plain markdown.

## Context in one paragraph

A per-customer orchestrator (**Maestro**, an always-on LLM service) fires
**specialist tools** to run a real business: market research, SEO audits, managing
Facebook ads, etc. Tools are **CLIs that run in ephemeral micro-VMs** (Sapiom;
Daytona on Impl 2) — boot per job (~1–2s), run, tear down, retain nothing. Maestro
⇄ µVM is **async + HMAC-signed webhook** (the job contract, design §9). State lives
in a **per-customer GitHub repo** ("the brain"), a **shared Postgres** (RLS by
`customer_id`), and **R2** for binaries. Everything is TypeScript; the µVM image is
**Node-only**; each tool is **CLI + Skill, one repo per tool**, built and validated
by an upstream **factory** (Executor + Reviewer).

## What we're trying to achieve (judge the proposal against THIS)

The objective function. Use it to answer "is this the best solution," not just
"is it internally consistent."

**Primary goal.** A fleet of agent-operated tools where **uniformity across tools
beats per-tool cleverness** — the "users" are LLM agents, so every behavioral
inconsistency between tools is a recurring failure/hallucination surface. We expect
to add **many** tools over years, each consumed by agents with zero human glue.

**Success criteria — what "best" has to mean here:**
- Adding tool N+1 is near-free: **no orchestrator code change, no DB migration,
  agent-ready on day one.**
- Any job can crash or be re-run at any point with **zero data loss and no
  double-effect.**
- **No tool can corrupt operational state or move money / mutate a live system
  outside an approved policy.**
- Results are **queryable for analytics and comparable across the whole fleet**, so
  the system can self-improve from real outcomes.
- The **same application code runs on two independent vendor stacks** (portability
  is an explicit goal, not incidental).
- **Multi-tenant isolation**: one customer's tools never see another's data.
- **Maintainable**: a tool can be enhanced or replaced without touching the
  orchestrator or any other tool.

**Non-negotiable constraints:** ephemeral Node-only µVMs; per-customer GitHub brain
+ shared Postgres (RLS) + R2; async HMAC webhook between orchestrator and µVM; TS
end to end; one repo per tool, built by the factory.

**What we are most afraid of:** (1) tool sprawl decaying into per-tool special-casing
inside the orchestrator; (2) an agent corrupting state or spending money wrongly;
(3) building something elegant for 3 tools that collapses at 30.

## The proposal under review

Some of this is written into the repo; some was decided in a design session and is
**not yet in the docs**. The `doc:` tag on each item tells you what is authoritative
vs. what is a fresh proposal you're being asked to pressure-test.

1. **Tools are stateless pure functions of their inputs.** A µVM reads durable
   state at boot (a "brain snapshot" passed in the job request; prior-stage
   artifacts pulled from R2 on replay), computes against a **scratch run
   directory**, writes results back at teardown, and is killable at any point with
   zero loss. *(doc: CONTRACT §7 partial; full framing is new.)*
2. **State is classified by required lifetime and assigned to the layer whose
   lifetime matches.** Run dir = scratch (dies with the µVM). Job ledger =
   Postgres `jobs`. Cross-run memory = brain repo. Results = Postgres `results`
   (JSONB, schema-tagged) + R2 + brain. **Identity/credentials = injected per job**
   via a single-use Infisical bootstrap token; the tool stores nothing — no
   profiles, no login. Config/policy = job request + a versioned Postgres "standing
   policy". *(doc: identity in CONTRACT §10; lifetime taxonomy is new.)*
3. **Generic DB spine, not per-tool tables:** `jobs`, `results` (JSONB tagged
   `tool.kind@version`), `artifacts` (R2 keys), `action_log`. When a result type
   becomes query-hot, an ingest worker fans it into a **derived projection table**
   (rebuildable from `results`). New tools require **zero migrations**.
   *(doc: NEW — not yet in repo.)*
4. **Only the platform writes Postgres, after validating the returned envelope.**
   The µVM writes R2 and the brain repo directly (scoped, short-lived creds) but
   never holds DB credentials. *(doc: CONTRACT §11. NOTE: this contradicts design
   §8, which still implies the µVM writes Postgres alongside the brain commit —
   flagged below.)*
5. **Mutation uses Terraform semantics:** `audit/analyze → plan → apply`, where
   `apply` executes only an approved plan artifact. A **deterministic, platform-side
   policy gate** sits between plan and apply — within standing policy it auto-applies;
   outside it, a human approval card. The gate validates the **proposal, never the
   proposer**. *(doc: CONTRACT §8.)*
6. **A versioned CLI contract** (distinct from the job contract): `{ok, data, error,
   meta}` stdout envelope, canonical verbs, enumerated errors, exit-code taxonomy,
   bounded/paginated output, three **generated** introspection layers (`--help` /
   `--describe` / `SKILL.md`). A shared runtime (`agent-cli-kit`) implements it once;
   a `verify` command enforces conformance in CI = the factory's Reviewer gate.
   *(doc: CONTRACT.md, whole file.)*
7. **Recurring work (e.g. daily ads management) = a series of short stateless cycles
   + durable memory**, not a long-lived process. Each cycle re-reads the brain and
   external API state at boot and writes notes back at teardown. A separate, cheaper
   hourly "spend guard" may only **pause** (asymmetrically safe, no approval needed).
   *(doc: NEW — not yet in repo.)*
8. **Self-improvement = nested loops over this data:** per-customer notes
   (run-to-run), projected-vs-actual calibration, and fleet-wide tool-version evals
   **replayed from archived R2 inputs**, shipped via the factory and canaried by tool
   version. Guardrails are never self-widened (autonomy changes need human approval).
   *(doc: NEW — not yet in repo.)*

## Known open tension (please weigh in)

`design.html §8` ("Write flow") says the brain commit and the Postgres write happen
**inside the same µVM run**. `CONTRACT.md §11` and `build.html`'s MVP step 5 say
**only the platform writes Postgres, after validation**. These conflict. We intend
to amend design §8 to match the contract — tell us if that's the wrong call.

## What we specifically want challenged

- Is "stateless µVM + classify-state-by-lifetime" the right backbone, or are we
  pushing too much coordination into Postgres + webhooks vs. a durable workflow
  engine (Temporal/Inngest)? What breaks first at scale?
- The **generic `results` JSONB + projections** choice: real win, or deferring a
  schema problem that bites harder later (query cost, validation, migration debt)?
- **plan/apply with a platform-side gate** for money-moving actions (ad bids):
  sufficient? Where are the idempotency / partial-failure / double-apply hazards?
- **Injected identity, no stored profiles** (CONTRACT §10): any real case where a
  tool genuinely needs persistent local identity and this becomes impractical?
- **Recurring-as-cycles vs a persistent agent**: where does "re-read everything each
  cycle" get too expensive or too slow to react? Is the hourly spend-guard split right?
- **Two contracts** (job contract over the wire, CLI contract in-process): clean
  separation, or accidental complexity?
- Anything that **assumes a persistent local runtime** and silently breaks in an
  ephemeral Node-only µVM that we haven't already relocated.
- Is `CONTRACT.md` itself complete and enforceable as written? Name any clause a
  tool author could satisfy on paper while still drifting in practice.

## Output format

1. **Verdict** — one of: `sound` / `sound-with-changes` / `reconsider`. One paragraph.
   State explicitly whether this is **the best approach for the goals above**, or
   whether you'd choose differently.
2. **Is there a better architecture?** — if yes, describe it concretely (even a
   sketch), and say what it buys over this proposal against the success criteria. If
   no, say why this is genuinely the right shape and not just an acceptable one.
3. **Strongest objections** — ranked; each with the concrete failure scenario and an
   alternative.
4. **What we'd regret in 12 months** — the single load-bearing assumption most likely
   to be wrong.
5. **Changes to make before committing** — specific and actionable, keyed to a file
   (`design.html §N`, `CONTRACT.md §N`, etc.) where it applies.

Be adversarial and concrete. Skip generic praise. A review that finds nothing wrong
is a failed review — push until you find the real weak points.
