# Admin UI Simplification — Verification

Base: `DFAB-OneERP-Admin-Operations-v2`.

## Changed files

- `src/admin-control.jsx`: Admin Home, clear section navigation, simple business language, guided forms, group filtering, collapsed workflow details, editor auto-scroll.
- `src/admin-control.css`: scoped responsive layout and admin-only styling.
- `src/admin-preview.jsx`: useful, navigable signed-out read-only tour of each admin section.
- `src/admin-preview.css`: scoped preview styling.
- `src/main.jsx`: only the Admin Control default tab changed to `overview` (existing Users and User Roles routes still open their dedicated tabs).
- Added `tests/admin-simple-ui.test.js` and `ADMIN-SIMPLE-UI-GUIDE.md`.

## Preserved exactly

All Supabase SQL files, admin RPC API adapter, permissions engine, business workflows, core ERP module screens, all other CSS, and saved dataset files are byte-identical to the base package.

## Checks

- `npm test`: **53/53 passed** (includes 4 new admin UI contract tests).
- TypeScript compiler JSX parser: **3/3 changed/referenced JSX entry files parse without syntax errors**.
- Source diff: exactly **5 existing files changed**, all admin UI related.
- Production `npm ci`/Vite build: **not verified** — installing dependencies timed out in this environment.
- `npm run typecheck`: **not passing** due to existing backend TypeScript checkJs errors in `cloud-store.js` and `supabase-rest.js`, which were not modified.
- Live Supabase admin CRUD and browser smoke tests: **not performed**; existing admin SQL must already be installed and an authenticated authorized administrator must sign in for writes.

The login-screen Admin button remains read-only (no company data exposed, no writes) unless a legitimate administrator is authenticated. This is an intentional production security boundary.
