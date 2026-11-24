# DFAB OneERP

**Current release: [AUDIT-FIXES-UPDATE.md](AUDIT-FIXES-UPDATE.md). It describes the filter/workflow fixes, SQL update and verification results.**

Manufacturing ERP with the existing DFAB UI, Supabase Auth and PostgreSQL persistence. This release uses the uploaded Employee Passwords Login project as its base.

**For this production-flow release, start with [PRODUCTION-FLOWS-UPDATE.md](PRODUCTION-FLOWS-UPDATE.md). Apply its SQL bundle before deploying this frontend.**

For the session renewal and Vercel Node.js update, follow `DEPLOYMENT-SESSION-FIX.md`.

## Update an existing installation

1. Back up the existing Supabase project.
2. With the baseline migrations below already installed, run `supabase/ERP_QA_EXTENSIONS_UPDATE.sql` in the Supabase SQL Editor. This combines the workspace fixes and extension migration in execution order. Then apply `supabase/ERP_PRODUCTION_FLOWS_UPDATE.sql` for the transaction engine and Zoho email permissions.
3. Keep your existing `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` values. The variable names are listed in `.env.example`.
4. Run `npm ci`, `npm run verify`, and `npm run build`. Use `npm run dev` for local development.
5. In Admin Control, assign staff view/create/edit/export rights for the new ERP Extensions pages and the source modules listed in `QA-AND-EXTENSIONS.md`.
6. Check employee sign-in and a sample transaction on your staging Supabase project before deploying to production.

## Fresh database

Apply these scripts in order on a fresh staging database. The production bootstrap grants initial access to existing Auth identities, so create only the intended initial administrator before bootstrapping.

1. `supabase/DFAB_ERP_PRODUCTION.sql`
2. `supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql`
3. `supabase/ERP_PRODUCTION_GUARDRAILS.sql`
4. `supabase/ERP_ADMIN_CONTROL.sql`
5. `supabase/ERP_ADMIN_OPERATIONS_V2.sql`
6. `supabase/ERP_INITIAL_LOGIN_PASSWORD_POLICY.sql`
7. `supabase/ERP_QA_EXTENSIONS_UPDATE.sql`
8. `supabase/ERP_PRODUCTION_FLOWS_UPDATE.sql`
9. `supabase/ERP_AUDIT_FIXES_UPDATE.sql`

Alternatively use the current root `DFAB-OneERP-All-In-One.sql` bundle on a fresh database.

Employee provisioning uses the existing `erp-admin-invite` Edge Function. Its deployment requirements are in `EMPLOYEE-PASSWORD-SUPABASE-RELEASE.md`.

## ERP Extensions

The separate navigation section contains Reorder Planning, Receivables Ageing, Collection Follow-ups and Customer Statements. It follows documented Zoho inventory and finance patterns using the saved OneERP records. Collection follow-ups store internal notes and next-contact dates.

See `QA-AND-EXTENSIONS.md` for supported behaviour, SQL prerequisites, role requirements and verification coverage.

## Verification

- `npm run verify` runs ESLint, the configured JavaScript type check, unit tests and a production build.
- `npx playwright install chromium` installs the browser needed for `npm run test:browser`.
- `npm run test:browser` runs the authenticated fixture page/report audit, transaction flows, create-form sweep, upload/import tests and ERP extension tests.
- `npm run test:premium` runs the upload and master-form suite independently.
- `npm run test:sql` requires `@electric-sql/pglite`, or `ERP_PGLITE_DIR` pointing to its `dist` directory, and verifies migrations, permissions, transaction rollback and extension validation in temporary PostgreSQL.

The browser suites use isolated Supabase fixtures. Live Auth, employee invitations, production data and external Tally, GST e-invoicing, email and Zoho OAuth connections require verification with the deployed services.
