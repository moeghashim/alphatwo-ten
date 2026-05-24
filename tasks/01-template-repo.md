# Task 01 — Fill out `templates/generated-app/`

## Goal
Produce the content of the **GitHub template repo** that every generated app is cloned from. It must be a minimal, runnable Next.js 14 (App Router) + TypeScript app that ships a pre-wired data-API SDK at `src/lib/db.ts`. **Composer must never need to modify `db.ts`.**

This task creates files only inside `templates/generated-app/`. Nothing else.

## Inputs to read first
- `PRD.md` §4.3 (SDK contract), §6 (prompt + template), §10 (acceptance)
- `infra/sql/001_init.sql` (`documents` table — informs SDK shape)

## Deliverables (only these paths)
```
templates/generated-app/package.json
templates/generated-app/tsconfig.json
templates/generated-app/next.config.js
templates/generated-app/next-env.d.ts
templates/generated-app/.gitignore
templates/generated-app/README.md
templates/generated-app/.cursor/skills/app-builder.md
templates/generated-app/src/app/layout.tsx
templates/generated-app/src/app/page.tsx
templates/generated-app/src/app/api/health/route.ts
templates/generated-app/src/lib/db.ts
```

## Implementation notes

### `package.json`
- name: `tenwhy-generated-app-template`
- scripts: `dev`, `build`, `start`, `lint`, `typecheck`
- deps: `next@^14`, `react@^18`, `react-dom@^18`, `nanoid@^5`
- devDeps: `typescript@^5`, `@types/node`, `@types/react`, `@types/react-dom`
- Node engine: `>=20`

### `src/lib/db.ts` (the SDK)
Must export `createDb(opts)` and a default `db` that reads from `process.env.NEXT_PUBLIC_DATA_API_URL`, `NEXT_PUBLIC_APP_ID`, `NEXT_PUBLIC_APP_KEY`.

Surface:
```ts
type Doc<T = unknown> = { id: string; body: T; updated_at: string };

db.collection<T>(name).list(opts?: { limit?: number; cursor?: string }):
  Promise<{ docs: Doc<T>[]; next?: string }>;
db.collection<T>(name).get(id: string): Promise<Doc<T> | null>;  // 404 → null
db.collection<T>(name).put(id: string, body: T): Promise<Doc<T>>;
db.collection<T>(name).delete(id: string): Promise<void>;
db.id(): string;  // returns nanoid(12)
```

Headers on every request:
- `Authorization: Bearer ${key}`
- `X-App-Id: ${appId}`
- `Content-Type: application/json`

Throw a typed `DbError` with `status` and `message` on non-2xx. Network errors retry once with 250 ms backoff.

Place a header comment in `db.ts`:
```
// DO NOT EDIT — provided by the alpha-ten template.
// All generated apps must persist data through this module.
```

### `src/app/api/health/route.ts`
```ts
export const runtime = "nodejs";
export async function GET() {
  return Response.json({ ok: true });
}
```

### `src/app/page.tsx`
Replace later by the agent. For the template, render a centered placeholder:
> "This app hasn't been generated yet."

### `.cursor/skills/app-builder.md`
Duplicate verbatim the **Hard requirements** and **Do NOT** lists from `PRD.md` §6.1.

### `README.md`
- What the template is for
- That every generated app shares its data via the platform data API
- That `src/lib/db.ts` and anything under `.cursor/` must not be edited

## Acceptance criteria

- [ ] `cd templates/generated-app && npm install && npm run build && npm run start` works (manually start `node .next/standalone/server.js` or `npm run start` per Next 14 defaults).
- [ ] `curl localhost:3000/api/health` → `{"ok":true}` (200).
- [ ] `tsc --noEmit` clean inside `templates/generated-app`.
- [ ] `db.ts` exports the surface above with no `any` in its public types.
- [ ] No environment variable other than the three declared in PRD §4.3 is referenced.
- [ ] No file is committed under `node_modules` or `.next`.

## Out of scope
- Any UI work beyond the placeholder page.
- Tests.
- ESLint config beyond Next defaults.
- Tailwind / UI libraries (the generating agent decides per app).

## Review gate
Open PR titled **"task 01 — generated-app template"**. Use the template in `AGENTS.md` §6.
