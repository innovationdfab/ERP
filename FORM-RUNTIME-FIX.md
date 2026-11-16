# DFAB OneERP — Sales Order and transaction form runtime fix

## Reported issue
Clicking Create on Sales Orders displayed the application-wide error screen: `GitBranch is not defined`.

## Root cause
The shared generic transaction form in `src/main.jsx` renders a `<GitBranch />` icon in its “Linked data & auto-fill” panel, but the icon was absent from that file's `lucide-react` import list. This caused a `ReferenceError` every time that form was rendered, affecting Sales Orders and every other page that uses the same form component.

## Minimal fix
- Imported `GitBranch` from `lucide-react` in `src/main.jsx`.
- Added `tests/form-jsx-import-safety.test.js`, which checks all JSX screen files for capitalized components that are not imported or declared, and specifically protects the linked-document form icon.

No routes, persisted keys, data, Supabase calls, form fields, component layouts, theme files, or workflow logic were modified.

## Verification
- `npm test`: **73/73 passed**.
- JSX static symbol analysis via TypeScript: no `TS2304` (missing name), `TS2552` (misspelled name), or JSX parser errors across `src/*.jsx`.
- Diff versus last release: only `src/main.jsx` changed in existing application source, plus this note and a new test file.
- Full Vite build, ESLint, browser navigation and live Supabase checks could not run because dependencies were unavailable; `npm ci` failed to fetch npm registry packages (`EAI_AGAIN`). An empty/incomplete `node_modules` is intentionally not included.

## Local verification / deployment
1. Extract ZIP, copy your existing `.env` into the project root (do not commit it).
2. Run `npm ci` or `npm install`, then `npm run verify`.
3. Run `npm run dev`, sign in, and open Sales Orders → Create, Sales Orders → Edit, Purchase Orders → Create, Work Order → Create, GRN → Create, and another generic transaction Create/Edit dialog.
4. Verify Save / Cancel / Back and linked document references with a staging Supabase database. If any runtime errors occur, capture the first browser-console stack trace.
5. Deploy only after build, lint and browser checks pass; perform a hard refresh to clear an older cached frontend bundle.
