# Live-site audit fixes — 24 November 2026

This is an update to the supplied Audit Fixes folder. The existing theme, menus, form fields, financial calculations, role checks, document storage keys and unrelated flows are retained. The previous source folder remains separate. No live records or deployments were changed while preparing this ZIP.

## What changed

1. **Shared invoice quantity reservations.** Invoice Fetch follows saved item ancestry to the sales-order item. A direct sales-order invoice and an invoice through a delivery/return challan use the same quantity budget. Fully billed items show zero pending, unchecked/disabled selection and a disabled Fetch action. Partial invoices leave only the true remaining quantity. Drafts reserve quantities; rejected invoices release them. Editing excludes the current invoice. Product codes alone never identify a quantity budget, so separate order items and separate orders stay independent.
2. **Database enforcement.** The existing process RPC retains its permission, concurrency, QC, total, projection, stock, payment and closure checks. A private wrapper additionally validates shared invoice reservations while the existing organization lock is held. Any failure rolls back the entire save. Its internal base function cannot be called directly by authenticated or anonymous clients. The update is safe to reapply.
3. **Existing-data reconciliation.** The existing Workflow Guide reconciliation table now lists missing dates, item details, currency, invoice due dates and amounts needing confirmation separately. It has search and 25-row pagination. Explicit original invoice dates, currency and payment terms already stored in invoice details are recovered for display when the corresponding document fields are absent. It never assigns today's date, defaults historical currency to INR, rewrites totals or guesses missing values. The existing Review original record action and editing/review controls remain in place.
4. **Database readiness.** Workflow Guide → Existing data reconciliation → Check database update verifies both the due-date trigger and cross-source invoice guard through a read-only authenticated RPC. It identifies a missing migration rather than treating frontend deployment as database verification.
5. **Zoho email authentication and diagnostics.** The mail screen now passes the renewed token correctly; it previously treated the token string as a session object. Setup checks distinguish an undeployed service, request/permission errors, missing server settings and a configured service. Check email setup retries after deployment/configuration changes. Only server-setting names are shown, never secret values. The existing TLS, role checks, invoice rendering and send-request idempotency remain intact. The default allowed origins include the existing ERP production domain and localhost; an explicit `ERP_ALLOWED_ORIGINS` still overrides them.

## Update your deployed installation

1. Back up Supabase and retain your last deployed folder for rollback.
2. Run root **RUN-THIS-UPDATE.sql** in the same Supabase project's SQL Editor. This single file includes the previous audit migration and the current live-audit migration. The earlier `ERP_PRODUCTION_FLOWS_UPDATE.sql` baseline must already be installed. No business records are backfilled or deleted.
3. Replace the project files using this folder, retain your existing frontend Supabase URL/publishable key, use Node 24, and run `npm ci` and `npm run verify`. Deploy through your existing GitHub/Vercel workflow.
4. Deploy the updated `supabase/functions/erp-invoice-email` function to your existing Supabase project. See `ZOHO-SETUP.md`. Frontend deployment alone does not deploy Edge Functions or configure server secrets.
5. Reload the ERP. Open Workflow Guide → Existing data reconciliation → **Check database update**. Both checks must pass. In a saved approved/released Sales Invoice → Workflow, use **Check email setup**.
6. Use a staging/disposable QA workflow to verify staff roles, save/reload, approval, partial Fetch, delivery, invoice and payment. Separately test an approved invoice email with a known recipient once Zoho is configured.

For a **fresh database**, `DFAB-OneERP-All-In-One.sql` contains the complete baseline and all current migrations in one file. It is an alternative to the individual scripts. Do not run the fresh bootstrap as a repair on an existing production database; use RUN-THIS-UPDATE.sql for this update.

## Data and configuration that cannot be invented

- Old records genuinely missing an original date, currency, amount or full line details still require verification against the source documents. They are now clearly listed for review. Paid or linked documents retain their existing edit restrictions; do not bypass them to fabricate history.
- SMTP credentials must be configured on your server if they are not already present. This ZIP contains no real credentials. A settings check proves configuration presence, not successful Zoho authentication or delivery.
- The package does not issue or send an invoice, record a payment, change staff rights or modify your production database automatically.

See `LIVE-FIXES-QA.md` for test results and repeatable checks.
