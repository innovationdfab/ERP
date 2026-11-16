# DFAB OneERP — Premium Admin Header and Navigation Update

## Scope
- New Admin button in the signed-in ERP topbar, immediately before global Search. The button opens the existing `Admin Control` route and highlights when active.
- The authenticated Admin Control interface now groups all eight existing sections into Team & Access, Document Connections, and Oversight.
- Admin Home has a clickable three-step team onboarding guide and a direct read-only Data Connections shortcut.
- Each management section explains what is changed, where data is saved, and how it affects employees/workflows.
- Small-screen presentation is responsive and reduced-motion preferences are respected.

## Locked existing behavior
No changes were made to Supabase RPCs, SQL schema, authentication rules, role checks, admin mutation functions, or non-admin page logic. The original sidebar Admin link remains available. A user who is not an authorized administrator may view only the existing restricted Admin overview.

## Source comparison
Modified: `src/main.jsx`, `src/admin-control.jsx`, `src/admin-control.css`.
Added: `tests/admin-layout-refresh.test.js` and this release note.

## Verified
- `node --test tests/*.test.js`: 65/65 passed.
- JSX parse: `src/main.jsx` and `src/admin-control.jsx` have no TypeScript compiler parse diagnostics.
- CSS parse: zero top-level syntax errors.
- Full `npm run build`, lint and browser E2E: not verified because dependency installation failed (`npm ci`: npm Exit handler never called).
- Live Supabase write testing: not performed; no database operations were changed.

## Local setup
Extract the archive, use your existing local `.env` file (not included), run `npm ci` or `npm install` on your workstation, then `npm run verify` and `npm run dev`. Never put service-role or other secret keys in Vite client-side env variables.
