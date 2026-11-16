# DFAB OneERP — controlled reliability and in-app dialogue release

## Source baseline and locked scope

Based on the previous DFAB-OneERP-Production-Hardening folder. Navigation, sidebar, dashboard, branding, forms, transaction definitions, workflow handoff screens, invoice calculations, restored data, and all previously authored SQL files were retained. These changes do not silently modify the production Supabase database.

## Actual changes

1. `src/in-app-dialog.jsx` and `src/in-app-dialog.css` (new): accessible in-app notices and promise-based confirmation modal, ordered queue, Escape/Cancel, focus entry, semantic dialog, and screen-size safe overlay. All 53 `alert()` calls and 12 `confirm()` calls in the app route through these controls. Browser-native alert/confirm/prompt is no longer invoked by this app's source.
2. `src/main.jsx`: only dialog import/host and awaiting confirmations in existing delete, return-status, and backup operations. Existing action targets and business logic retained.
3. `src/backend/cloud-store.js`: required compare-and-swap for every ERP collection save and deletion, no legacy blind-overwrite RPC fallback, plus rollback of unconfirmed cached collections when a queued write fails. Connected documents still require the atomic batch RPC.
4. `src/backend/supabase-rest.js`: 30-second bounded requests and clear connectivity/401/403 errors. A timed-out write may have reached the server; the user is instructed to verify it before retrying.
5. `tests/cloud-store.production.test.js`, `tests/dialog-policy.test.js`: regression checks for save conflicts, missing integrity functions, native-popup elimination and accessible modal structure.

## Mandatory Supabase rollout

- First create a restorable backup; restore a copy into a separate staging Supabase project.
- Apply `supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql` and then `supabase/ERP_PRODUCTION_GUARDRAILS.sql` in staging. Verify their compatibility with all existing ERP data. The source package contains these SQL files but does NOT apply them to any database.
- Provision proper least-privilege roles for actual employees. The original production seed grants ADMIN widely; do not use that as a production authorization policy.
- Exercise the full sales, purchase, inventory, production, QC, return, approval and payment paths with at least two users; verify transaction totals, race/conflict handling, unique document numbers, stock/accounting reconciliation, and access-denied cases.
- For Vercel, configure `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` (never expose a service-role key). Test login, refresh, expiry, logout and database errors on the deployed URL.

## Verification performed in this environment

- Node automated tests: **32/32 pass**.
- TypeScript parser syntax validation: **11 source JS/JSX files passed**.
- Relative import file existence: **passed**.
- JavaScript syntax of backend modules: **passed**.
- Chrome-native popup source audit: all `alert` and `confirm` calls resolve to the imported in-app UI service; no `window.alert`, `window.confirm`, `window.prompt` calls remain.
- Full `npm ci` did not complete (installation timed out). Consequently lint, Vite production build and browser automation cannot be claimed as passing.
- Live database authentication, RPC execution, RLS security, production concurrency, and accounting/stock posting have **not** been tested, and no real credentials were used.

## Remaining production blockers

This is a **release candidate, not an unconditional error-free production certification**. More extensive architecture work is required for per-document normalized transactional writes, module-specific server authorization, secure session architecture, certified inventory and GL posting, fiscal-period controls, restore drills and live concurrent user/role tests. Do not deploy with financial or stock posting authority before these have been addressed and signed off.

## Local setup

```powershell
npm ci
npm run verify
npm run test:browser
```

Use a valid `.env` file and a staging Supabase project. `npm run verify` includes build and lint. The current repository requires Node 22.12+.
