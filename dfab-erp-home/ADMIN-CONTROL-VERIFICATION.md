# Admin Control Center — Verification record

## Completed in this source package
- Admin-only sidebar entry and in-place panel integration.
- Database-backed department, user, role, module permissions, storage mapping and auditable workflow templates.
- Secure invitation Edge Function using the caller's JWT; server-side elevated key only.
- Source and destination field mapping and status gate editing.
- Explicit draft save / publish / restore built-in workflow; no automatic changes to existing documents.
- Route access catalog covers existing menu leaves, including Product Groups and report pages.
- PostgreSQL permission checks on compatibility-state reads/writes and linked-document updates.
- No changes to existing dashboard styling, core transactions or original business schemas.

## Executed checks
- `npm test`: 42 of 42 tests pass, including 10 admin-specific tests.
- TypeScript JSX parser: `src/main.jsx`, `src/admin-control.jsx`, `src/in-app-dialog.jsx` have zero parse diagnostics.
- JavaScript syntax: new API/permission helper modules pass `node --check`.
- Existing source diff includes only `src/main.jsx` and `src/backend/supabase-rest.js`; all other existing application files are unchanged. New code isolated in admin-specific modules, SQL, Edge Function and tests.
- ZIP CRC checked after packaging.

## Not verified / release blockers
- `npm run build` and `npm run lint`: missing node dependencies in this environment (`vite` and `eslint` unavailable). These commands must pass in CI before deployment.
- `npm run typecheck`: missing npm types (`estree`, `json-schema`). A standalone global TypeScript check also found pre-existing JavaScript typing errors. It is not a passing typecheck.
- **The SQL and Edge Function have not been executed against real Supabase.** Staging migration, RLS probes, invitation email delivery, concurrent saves and end-to-end module actions need a real configured project.
- The existing legacy JSON UI-state storage and some normalized business endpoints still require a wider security and accounting/inventory posting audit before unrestricted company-wide production use.
- Original bootstrap assigned ADMIN to existing profiles. Least-privilege role review is mandatory before new departments start using the system.

## Safe deployment
Follow `ADMIN-CONTROL-DEPLOYMENT.md` and run `supabase/ERP_ADMIN_CONTROL_STAGING_CHECKS.sql` as a read-only confirmation after the migration. Do not run the original bootstrap script again on a live production database without first reviewing its side effects.
