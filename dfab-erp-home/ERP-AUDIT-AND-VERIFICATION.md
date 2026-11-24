# DFAB OneERP — Integrity Audit and Stabilization Pass

Baseline: `DFAB-OneERP-DFAB-Logo.zip` (latest version with the DFAB logo).
Scope: repair verified defects with no removal or redesign of the established ERP navigation, forms, assets, Supabase schema, dashboard, or document flow definitions.

## Implemented

1. Prevented background writes from row-based ERP pages on initial mount; a page opening must not replace saved cloud state merely because a component initialized. Changed shared row-state hook and five legacy page effects to persist user-driven changes only.
2. Stopped successful historic data imports from recreating intentionally deleted records on later logins. An already-committed import marker now overrides historical population counts. New first-time imports still verify expected baselines before setting the marker.
3. Backups: uploading a backup now waits for confirmation that the queued Supabase writes have settled; it no longer announces success when the writes are just queued. Backup export checks any outstanding cloud-write errors first.
4. Sign-out now waits for in-flight Supabase writes; if a save fails it stays in the current session and displays the error rather than silently dropping unsaved edits.
5. Fixed the error-boundary 'Return to login' action to clear the actual Supabase session key, rather than obsolete sessionStorage keys.
6. Product CSV import now uses the existing robust CSV parser, preserving quoted commas, newlines, and escaped quotes.
7. Calendar validation rejects impossible dates such as February 30, while permitting valid leap days.
8. Backup validation also rejects authentication token/secret-related keys, not only password/session keys.
9. CSV downloads are labeled CSV, not Excel, where the output is in fact CSV.
10. Signing out clears the in-memory cloud cache; this avoids exposing a previous session's cached data to a different login on the same device.

## Verification executed

- Node built-in test suite: **10/10 passing** (6 pre-existing + 4 integrity tests).
- JavaScript syntax checks for cloud store, Supabase helper, and utilities: pass.
- React main JSX and premium-forms JSX parsed with TypeScript's JSX parser: no syntax diagnostics.
- Full Vite production build: **NOT VERIFIED**, because `vite` executable was missing and dependency installation timed out.
- ESLint: **NOT VERIFIED**, because `eslint` executable was missing.
- Existing typecheck: **NOT VERIFIED** due to incomplete `@types` dependency tree. Additional direct TS checks also found existing JSDoc typing gaps in `supabase-rest.js` and `cloud-store.js`.
- Browser automation & live Supabase: **NOT RUN**; no environment credentials or reachable test instance were used.

## Remaining release blockers — NOT COMPLETE / NOT SAFE TO CLAIM SAP-LEVEL

**Critical**
- ERP UI data is persisted in large shared JSON state records (`erp_ui_state`). Concurrent edits by two users remain susceptible to last-write-wins lost updates. A versioned/row-level transactional API and conflict handling must be implemented and tested before broad multi-user usage.
- Organization-level RLS in the existing SQL does not by itself enforce per-role create/edit/delete/approve permissions for the generic UI-state RPCs. Server-side authorization per action is needed.
- Document conversions currently use multiple independent writes; a partial failure can create a target without a link or vice versa. Server-side atomic RPC/transaction is needed for production posting.
- Inventory, financial posting, approval gates, and audit events must be verified at the database/API layer, not inferred from frontend flow buttons.
- Previously existing hardcoded/demo-like user presentation and generic report views need validation against the live data model before claiming full production equivalence.

**High**
- Real Supabase integration tests, role-matrix tests, data migration/restore tests, posting reconciliation, negative inventory prevention, and concurrent-user tests.
- Complete production build, lint/typecheck, browser navigation and accessibility checks across all pages, plus cross-browser responsive tests.
- One-click rollback and database point-in-time backup/restore drill before deployment.

## Setup and deployment checklist

1. Extract ZIP; put the real `.env` values locally, from `.env.example` (never put service role keys in `VITE_*`).
2. `npm ci` with supported Node version, then `npm run verify` and `npm run test:browser` against the local dev server where applicable.
3. Use a staging Supabase organization and imported test data to exercise the complete sales, procurement, production, QC, invoice, return and payment loops.
4. Do **not** run this release on live company data without testing the critical blockers above and taking a backup.

The release is a verified **stabilization pass**, not a claim that all modules are SAP S/4HANA-equivalent or fully production-certified.
