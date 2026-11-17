# DFAB OneERP

Manufacturing ERP for DFAB Stainless Systems. The React frontend uses Supabase Auth and PostgreSQL. The release keeps the OneERP theme and the legacy-style transaction forms.

## Update an existing workspace

1. Apply `supabase/ERP_WORKSPACE_INTEGRITY.sql` to a staging project with the existing OneERP migrations already installed. It adds the storage mappings and RPCs used by this release, and updates the permission checks for record saves and handoffs.
2. Keep the project’s existing `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY`. See `.env.example` for the variable names.
3. Run `npm ci` and `npm run verify` from this directory. Use `npm run dev` for local development and `npm run build` for a deployment build.
4. Verify sign-in, account provisioning, and a sample transaction in staging with your actual employee roles before promoting the release.

The original production SQL is a fresh-database bootstrap. It grants Admin access to pre-existing Auth accounts at bootstrap and should not be rerun on a populated project. This release does not reassign employees or rewrite existing transaction rows.

## Fresh staging database

Use the following order on an isolated, fresh project where the only pre-existing Auth identities are the intended bootstrap administrators.

1. `supabase/DFAB_ERP_PRODUCTION.sql`
2. `supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql`
3. `supabase/ERP_PRODUCTION_GUARDRAILS.sql`
4. `supabase/ERP_ADMIN_CONTROL.sql`
5. `supabase/ERP_ADMIN_OPERATIONS_V2.sql`
6. `supabase/ERP_INITIAL_LOGIN_PASSWORD_POLICY.sql`
7. `supabase/ERP_WORKSPACE_INTEGRITY.sql`

The optional recovery and staging-check scripts are separate. Employee provisioning requires the existing `erp-admin-invite` Edge Function and server-only configuration described in [Employee password and Supabase setup](EMPLOYEE-PASSWORD-SUPABASE-RELEASE.md).

## Connected business flows

- Order to cash follows enquiry, quotation, sales order, production, quality, dispatch, invoice and customer receipt.
- Procure to pay follows indent, purchase order, GRN, inward quality, invoice and vendor payment.
- Work orders, route cards, material movements and subcontract receipts retain their existing references and approval gates.

Pending Approvals shows waiting documents with links to the source screens. Activity Log and the user-wise transaction report read the scoped database audit records. Product-wise and vendor-wise price lists use the same saved rates. The older price sections remain readable when their product or party code identifies how they were stored.

**Transaction lookups.** PO Number Details, SO Number Details, RM Inward and Outward, Route Card Monitoring, and Customer Payment Overdue use saved OneERP transactions and the source-module view permissions. The overdue register uses the saved invoice due date and recorded payments.

**Fetch.** Use Fetch in the transaction form to select an eligible saved document. It fills supported blank fields and keeps the source reference with the record. Enter actual received quantities and payment amounts on their respective transactions. When billing a fetched dispatch, the invoice checks the customer, item, and available dispatched quantity.

Reapply the included `supabase/ERP_WORKSPACE_INTEGRITY.sql` when upgrading. It updates the server-side handoff gates for job work and dispatch billing using the existing tables.

## Verification

`npm run verify` runs lint, the configured JavaScript type check, unit tests, and the Vite production build.

Run `npx playwright install chromium` once and then run `npm run test:browser` for the desktop navigation sweep, report and master workflows, mobile checks, and transaction regression suite. Both browser suites use isolated Supabase response fixtures.

The SQL acceptance test uses a temporary local PostgreSQL database through PGlite. To run it, make `@electric-sql/pglite` available to Node or set `ERP_PGLITE_DIR` to its `dist` directory, then run `node tests/workspace-sql.mjs`. It applies the migrations, runs staff and administrator permission checks, and verifies conflict handling, handoff rollback, and backup rollback. It never connects to a live Supabase project.

Live Auth, the invitation Edge Function, real production data, Tally, GST e-invoicing and outbound email require separate staging verification with your integrations. Sales Invoice supports multiple product lines. The other legacy transaction editors keep the existing single operational line model.
