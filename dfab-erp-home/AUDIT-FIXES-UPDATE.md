# ERP audit fixes — 24 November 2026

This folder updates the supplied Production Flows project. It keeps its existing theme, navigation, storage keys, access controls and unrelated workflows. No live deployment or customer database was changed while producing this package.

## Changes

- Shared case-insensitive, whitespace-tolerant multi-word search across registers, masters, reports, payments, system tables and operational views. Search includes nested transaction items and header values where available.
- Inclusive From/To dates, supported historical date formats, as-of report boundaries, invalid-range handling and pagination resets/clamping. Date inputs now update consistently on native browser input events. Undated historical movements remain explicitly undated rather than receiving invented dates.
- Small animated Saved, Deleted, Approved, Submitted, Released, Payment saved and Closed notifications after database confirmation. Failures show an error; success cards allow clicks through to underlying controls, include dismissal and respect reduced-motion settings.
- Fetch carries commercial charges, adjustment, project, buyer PO, currency and terms through the transaction chain. Partial financial allocations use source proportions and cumulative rounding; manually edited values retain ownership.
- Handoffs needing a new vendor open an inline unsaved draft, allowing vendor selection before database validation. Confirmed validation rejection permits correction without reloading; uncertain failures retain the existing write lock.
- Sales Invoice adds Credit Days and Due Date, derives due date from the invoice date and validates released invoices on both client and database.
- Statements and ageing distinguish actual cash received from TDS/LD settlement. Stock reports use saved line description/UOM when a master product is absent.
- Final paid/delivered order closure updates linked work orders atomically, subject to existing role and database guards.

## Install on the existing production-flow version

1. Back up Supabase and retain the current deployed folder for rollback.
2. Run root `RUN-THIS-UPDATE.sql` once in Supabase SQL Editor. The preceding `ERP_PRODUCTION_FLOWS_UPDATE.sql` migration must already be installed. The update is additive; it does not fabricate dates or rewrite historical invoices.
3. Keep your current Supabase URL/publishable key. Use Node 24, run `npm ci`, then `npm run verify`. Deploy this folder through the existing GitHub/Vercel process.
4. Reload the ERP, sign in, and verify a staging transaction with your actual role permissions and data before production use.

For a fresh database, root `DFAB-OneERP-All-In-One.sql` contains the complete ordered baseline and this update in a single SQL file. It is an alternative to running the individual migration files, not an additional script to run after them. Bootstrap only with the intended initial Auth administrator present. Keep production service-role and SMTP secrets out of frontend environment variables.

Zoho sending still requires your Supabase Edge Function secrets and the existing `erp-invoice-email` deployment described in `PRODUCTION-FLOWS-UPDATE.md`. Mail delivery cannot be certified without a configured account and recipient check. Existing historical invoices missing a genuine due date need manual reconciliation; this release does not guess those dates.

## Verification

See `AUDIT-FIXES-QA.md` for the results from this exact folder and commands to repeat them. The automated browsers use isolated authenticated fixtures; SQL tests use temporary PostgreSQL. They do not post transactions into the live ERP.
