# AGENTS.md — orientation for agents working in this repo

This repo holds **tenwhy** — an AI workforce for small businesses. Today it's a static
design-doc site; it will grow to hold the implementation(s).

## What's here now

A static site (no build step) hosted on Cloudflare Pages at **tenwhy.pages.dev**, auto-deployed
on every push to `main` via Cloudflare's native GitHub integration.

| File | Role |
|---|---|
| `index.html` | **Homepage** — the Factory Map: interactive build-pipeline animation ("Watch a build"). |
| `design.html` | **The design** (`/design`) — the comprehensive architecture reference. The source of truth for *what* tenwhy is. |
| `stack-map.html` | **Stack** (`/stack-map`) — what runs where (the current/Impl-1 stack: Render, Cloudflare, Sapiom, OpenRouter, GitHub, etc.). |
| `build.html` | **Build** (`/build`) — the implementation plan. Two implementations in parallel (Impl 1 hand-wired · Impl 2 Stripe Projects), the MVP proving loop, the build phases. **The source of truth for *how* we build.** |
| `tool.html` | **Build a tool** (`/tool`) — the build guide for tool authors (incl. agents): framework (TS · Node 20 · Stricli via `agent-cli-kit`), scaffolding, commands, the pipeline + plan/apply patterns, shipping. The *how-to*; conforms to `CONTRACT.md`. |
| `branding/tenwhy.svg` | Wordmark + favicon. The brand mark (inlined into each page's masthead). |
| `_redirects` | Cloudflare Pages redirects (e.g. legacy `/system-map` → `/design`). |
| `CONTRACT.md` | **The tool contract** (`v0.1`) — the normative spec every tool CLI conforms to: command shape, output envelope, exit codes, plan/apply + the platform gate/broker, injected identity, introspection, conformance. Downstream of design §9–11; `agent-cli-kit verify` checks it in CI. |

**Building tools** (the build-a-tool + build-the-kit briefs) lives in its own public repo —
[`build-cli-tool`](https://github.com/moeghashim/build-cli-tool) — a clonable template / agent
skill. `CONTRACT.md` here is canonical; that repo carries a synced copy.

## Source-of-truth hierarchy

1. The user's live instruction.
2. `design.html` — the architecture (the locked decisions, the workforce, the job contract).
3. `build.html` — the implementation plan (the two impls, the MVP, the phases).
4. `stack-map.html` — the concrete vendor stack.
5. `CONTRACT.md` — the normative tool-CLI spec (detail behind design §9–11).
6. `tool.html` — how to build a tool (the how-to; derived from `CONTRACT.md` + design).

If these conflict, the higher one wins; stop and ask rather than guessing.

## Conventions

- **Brand / visual language:** ivory ground (`#FAF9F5`), serif headings (Georgia/ui-serif),
  monospace eyebrows + labels, single clay accent (`#D97757`), olive (`#788C5D`) and sky
  (`#6A8CAF`) as secondary signals. Editorial, restrained — closer to a literary imprint than a
  tech startup. Keep new pages consistent with this.
- **The masthead logo** is inlined SVG (not an `<img>`) on every page so it renders without a
  file fetch; it links to `index.html`.
- **Cross-links** keep the four pages interlinked (design ↔ factory ↔ stack ↔ build).
- **Deploy:** just `git push` to `main`. Cloudflare Pages rebuilds. No CI workflow file, no
  secrets — the Git integration is native. Commits are SSH-signed as Moe Ghashim
  <mohanadgh@gmail.com>.
- **Naming:** the brand is **tenwhy** (not "alphatwo-ten" — that's the old repo/working name).
  The software factory is the upstream agent-builder; tenwhy is the product.

## When implementation code lands

Per `build.html`, the planned layout is one repo with shared `app/` code and two thin
`infra/impl1` + `infra/impl2` provisioning configs. The `.env` is the seam: app code reads the
same variable names regardless of implementation.
