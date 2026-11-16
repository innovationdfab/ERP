# Verification — Temporary Admin Preview (2026-11-14)

Base: DFAB-OneERP-Admin-Control-Center release. This patch adds a localhost-only UI preview, clearer missing-RPC login error, and a PostgREST reload notification in the existing admin SQL migration. Existing business pages, flow implementations, session guards and data schemas are unchanged.

## Checks run

- `node --test tests/*.test.js` — **44/44 passed** (42 baseline + 2 preview gating tests).
- `node --check src/admin-api.js` and `src/admin-preview-policy.js` — passed.
- TypeScript parser JSX syntax checks of `src/main.jsx`, `src/admin-preview.jsx`, `src/admin-control.jsx` — 0 errors.
- Diff comparison — only `src/main.jsx`, `src/admin-api.js`, `supabase/ERP_ADMIN_CONTROL.sql` changed among existing files, plus new preview/UI/tests/docs.
- `npm run build` / lint — **not verified**. Installed dependencies were incomplete in this environment; `npm ci` timed out. Run `npm ci && npm run verify` locally before deployment.
- Supabase migration — **not executed** on the live database; the user must apply it in staging and validate before production.

## Security properties

- Preview visible only when `import.meta.env.DEV===true` and hostname is one of localhost, 127.0.0.1, ::1.
- No Supabase REST/RPC calls from preview; no tokens, no `setAuthenticated(true)`, no fake admin roles.
- Only project-bundled static admin catalog and built-in connections are shown; no employee data or real active templates.
- The existing Login and all production role checks are unchanged; deployed production builds cannot access preview.
