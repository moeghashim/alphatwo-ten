# tenwhy — design docs

Three interlinked design documents for the **tenwhy** platform: a software factory + AI workforce for small businesses.

This is a static site. No build step. No dependencies.

## Pages

| Page | What it covers |
|---|---|
| [`index.html`](index.html) | **System map** — the whole design. What tenwhy is, the two layers (factory + workforce), Maestro, the 8-document brain, the workforce roster, all locked decisions. |
| [`factory-map.html`](factory-map.html) | **Factory map** — interactive walkthrough of how the factory builds a tool, stage by stage, with a "Watch a build" animation. |
| [`stack-map.html`](stack-map.html) | **Stack** — what runs where. Platform columns (Render, Cloudflare, Sapiom, OpenRouter, GitHub), the signup sequence, the first-build flow, the auth/secrets model. |

Brand mark: [`branding/tenwhy.svg`](branding/tenwhy.svg).

---

## Deploy

The site is plain HTML + one SVG. Push the repo anywhere that serves static files.

### GitHub Pages
1. Push this repo to GitHub.
2. **Repo Settings → Pages → Source:** `main` branch, `/ (root)` folder.
3. Live at `https://<user>.github.io/<repo>/`.
4. Custom domain: add a `CNAME` file at the repo root containing the domain, and point your DNS `CNAME` record at `<user>.github.io`.

### Cloudflare Pages
1. Push this repo to GitHub.
2. **Cloudflare Pages → Create project → Connect to Git → select repo.**
3. Build settings: leave empty. Root directory: `/`. Build output: `/`.
4. Live at `https://<project>.pages.dev`. Custom domains via the Cloudflare dashboard.

### Render Static Site
1. Push this repo to GitHub.
2. **Render → New → Static Site → connect repo.**
3. Build command: leave empty. Publish directory: `.`
4. Live at `https://<service>.onrender.com`.

---

## Local preview

Open `index.html` directly in a browser, **or** serve the folder:

```bash
python3 -m http.server 8000
# → http://localhost:8000
```

---

## Layout

```
.
├── index.html           # system map (default page)
├── factory-map.html     # interactive factory walkthrough
├── stack-map.html       # tech stack reference
├── branding/
│   └── tenwhy.svg       # logo / favicon
├── README.md            # this file
└── .gitignore
```
