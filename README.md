# tenwhy — design docs

The design + build documentation for **tenwhy**: an AI workforce for small businesses,
supplied by an upstream software factory that builds the agents' tools.

Static site. No build step. No dependencies. Live at **[tenwhy.pages.dev](https://tenwhy.pages.dev)**.

## Pages

| Page | URL | What it covers |
|---|---|---|
| [`index.html`](index.html) | `/` | **Factory map** (homepage) — interactive pipeline diagram of how a company gets built, with animated sequences. |
| [`design.html`](design.html) | `/design` | **The design** — the comprehensive architecture reference. The workforce, Maestro, the brain, the job contract, the audit layer, all locked decisions. Source of truth for *what* tenwhy is. |
| [`stack-map.html`](stack-map.html) | `/stack-map` | **Stack** — what runs where for Implementation 1 (Render, Cloudflare, Sapiom, OpenRouter, GitHub). |
| [`build.html`](build.html) | `/build` | **Build** — the implementation plan. Two implementations in parallel (hand-wired vs Stripe Projects), the MVP proving loop, the build phases. Source of truth for *how* we build. |
| [`review.html`](review.html) | `/review` | **Review** — the Codex + AMP architecture review, reconciled: the verdict, every recommendation decided, the §8 audit resolution, the one open decision, the phased edit plan, and a full-system diagram with the durable-orchestration layer added. |

Tool-CLI spec: [`CONTRACT.md`](CONTRACT.md) — the versioned contract every tool conforms to (the detail behind design §9–10). Brand mark: [`branding/tenwhy.svg`](branding/tenwhy.svg). Legacy URL redirects: [`_redirects`](_redirects).

Agents working in this repo: read [`AGENTS.md`](AGENTS.md) first.

## Deploy

Hosted on **Cloudflare Pages** with the native GitHub integration — every push to `main`
auto-builds and deploys. No CI workflow, no secrets, no manual step:

```bash
git push   # that's the whole deploy
```

Branches and PRs get preview URLs at `<short-id>.tenwhy.pages.dev` automatically.

## Local preview

Open `index.html` directly in a browser, **or** serve the folder:

```bash
python3 -m http.server 8000
# → http://localhost:8000
```

## Layout

```
.
├── index.html           # factory map (homepage)
├── design.html          # the design — architecture reference
├── stack-map.html       # Impl 1 stack reference
├── build.html           # implementation plan (Impl 1 ∥ Impl 2)
├── review.html          # architecture review (Codex + AMP), reconciled
├── branding/
│   └── tenwhy.svg       # logo / favicon
├── _redirects           # Cloudflare Pages redirects
├── CONTRACT.md          # the tool contract (v0) — normative CLI spec
├── AGENTS.md            # orientation for agents
└── README.md            # this file
```
