# Verification — Admin Control Operations v2

## Code and scope
- Source baseline: `DFAB-OneERP-Admin-Preview-Safe`.
- Existing application files changed: `src/main.jsx`, `src/admin-api.js`, `src/admin-control.jsx`, `src/admin-control.css`, `src/admin-preview.jsx`, `src/admin-preview.css`.
- Existing data, SQL schema files, manufacturing logic, document flows, Home styling, general navigation, authentication implementation and saved datasets were not edited.
- New files: one additive SQL migration, staging SQL checks, optional trusted-admin recovery SQL, new admin CRUD contract tests and release documentation.
- Existing admin catalog: 181 module/page definitions, 40 built-in next-document connections, 9 module groups. Catalog source is unchanged.

## Local checks performed
- Node automated tests: **49/49 passed**.
- TypeScript AST parsing of `src/main.jsx`, `src/admin-control.jsx`, `src/admin-preview.jsx`, `src/admin-api.js`: **0 syntax errors**.
- JavaScript syntax check of backend admin API and permissions helpers: passed.
- Relative source imports: **0 unresolved** across inspected source files.
- Source diff: only the six admin-specific/application-entry files listed above were changed.
- ZIP integrity: validate after packing.

## Unable to verify in this environment
- `npm ci`: failed due unavailable package registry/cache (npm exit handler failure / missing tarball).
- `npm run build`: not passed (`vite: not found`).
- `npm run typecheck`: blocked by incomplete node_modules typings (`estree`, `json-schema`).
- Browser E2E, login/Auth, Edge Function invitation and actual SQL migrations: not executed against a live staging Supabase database.

**This is a source-complete admin upgrade, NOT an error-free production certification.** Apply database migration in staging and complete the mandatory acceptance tests in `ADMIN-OPERATIONS-RELEASE.md` before rollout.
