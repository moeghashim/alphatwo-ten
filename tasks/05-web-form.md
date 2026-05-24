# Task 05 — Next.js form + status page

## Goal
Ship the public-facing UI at `alpha.tenwhy.com`: one form, one status page. No extras.

## Inputs to read first
- `PRD.md` §1 (UX), §4.1 (API shapes), §10 (acceptance)

## Deliverables
```
apps/web/package.json
apps/web/tsconfig.json
apps/web/next.config.js
apps/web/next-env.d.ts
apps/web/.gitignore
apps/web/src/app/layout.tsx
apps/web/src/app/page.tsx
apps/web/src/app/globals.css
apps/web/src/app/apps/[id]/page.tsx
apps/web/src/lib/api.ts
```

## Implementation notes

### Stack
- Next 14 App Router, TypeScript, React 18.
- No UI library. Plain CSS in `globals.css`. ~150 lines is plenty.
- One env var: `NEXT_PUBLIC_API_BASE_URL` (e.g. `https://api.alpha.tenwhy.com`).

### `src/lib/api.ts`
```ts
export type AppStatus = 'queued'|'generating'|'pushing'|'deploying'|'live'|'failed';
export type AppRow = {
  id: string; slug: string; description: string;
  status: AppStatus; status_message?: string;
  preview_url?: string; error?: string;
  repo_url?: string; github_pr_url?: string;
  created_at: string; updated_at: string;
};

export async function createApp(input: {slug:string; description:string}): Promise<{id:string}>;
export async function getApp(id: string): Promise<AppRow>;
```
- Throw with `{status, message}` on non-2xx (the `message` should surface `error_code` if the API returns one).

### `/` — landing + form (`src/app/page.tsx`)
- Headline: "Describe an app. We'll build it."
- Two inputs:
  - `slug` (text) — show inline validation matching the regex; helper text: "lowercase letters, numbers, dashes; 3–40 chars".
  - `description` (textarea, maxlength 300, counter visible).
- Submit button: disabled until both inputs valid.
- On submit: `createApp({slug, description})`; on success `router.push('/apps/'+id)`; on 409 show "That name is taken — try another."; on 400 show the API's message.

### `/apps/[id]` — status page (`src/app/apps/[id]/page.tsx`)
- Client component. Fetch `getApp(id)` immediately, then poll every **3 s** while status ∈ {queued, generating, pushing, deploying}.
- Stop polling on `live` or `failed`.
- Render:
  - Big status pill (one of the six).
  - Step list with current state:
    1. Queued
    2. Generating with Composer 2.5
    3. Pushing to GitHub
    4. Deploying to Render
    5. Live
  - `status_message` below the pill in muted text.
  - If `repo_url` known → show "View source ↗".
  - If `github_pr_url` known → show "View PR ↗".
  - If `live`: big **Open app** button → `preview_url` (target=_blank).
  - If `failed`: show `error` in a red panel, no retry button.

### `globals.css`
- A clean modern look. System font stack. Max-width 720 px centered. Two colors max + grays.

### `next.config.js`
- `reactStrictMode: true`. Nothing else.

## Acceptance criteria

Run locally with the API stubbed (return canned JSON via `MSW` not allowed — just point `NEXT_PUBLIC_API_BASE_URL` at a tiny local mock or your real API):

- [ ] `npm --workspace apps/web run build` succeeds.
- [ ] `npm --workspace apps/web run start` serves `/`.
- [ ] Submitting an invalid slug never enables the button.
- [ ] Submitting a valid slug + description navigates to `/apps/<id>` and starts polling.
- [ ] Polling visibly advances the step list as the API row's status changes (test by manually updating the DB row through `psql`).
- [ ] On `live`, the **Open app** button appears and links to `preview_url`.
- [ ] On `failed`, the red panel shows the `error`.
- [ ] No CSS framework or component library added.
- [ ] No `useEffect` polling continues after `live` or `failed`.

## Out of scope
- Authentication.
- Listing past apps on the homepage.
- Sharing UI / Twitter cards.
- Analytics.
- Dark mode toggle (system default is fine via `@media (prefers-color-scheme)`).

## Review gate
Open PR titled **"task 05 — web form + status"**. Attach screenshots of: form, status page mid-flight, status page on live, status page on failed.
