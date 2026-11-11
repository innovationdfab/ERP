# DFAB OneERP — Connected Workflow & Calculation Integrity Pass

## Scope and unchanged features
Based on the prior `DFAB-OneERP-Audited` release. Existing Home/dashboard layout,
colors, sidebar, logos, navigation, Supabase production schema, historical dataset,
non-workflow modules and their data keys were left as they were.

Modified: `src/main.jsx`, `src/backend/cloud-store.js`. Added focused pure logic
modules `src/workflow-integrity.js`, `src/invoice-calculations.js`, tests, and an
**optional additive SQL** script `supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql`.

## Delivered changes
- Generic transaction Create/Edit/Delete/Advance now waits for a confirmed
  Supabase save before switching visible state. A failed save leaves the form
  available and displays the error, instead of silently declaring success.
- Connected handoffs save both their target record and workflow link with one
  atomic database RPC **when the optional SQL is installed**. Sales Invoice
  handoff also saves its invoice details in the same transaction.
- The SQL upgrade adds compare-and-swap write protection against stale clients;
  a concurrent edit raises a conflict instead of overwriting a newer document.
- Older deployments remain backward-compatible using confirmed but sequential
  RPC writes. **Sequential fallback is not atomic.** Apply SQL in staging,
  validate, then apply to production before depending on atomicity.
- Invoices now save their summary and line-item details together and use
  consistent currency rounding for line totals/tax/gross totals.
- Approved invoices and invoices with linked customer payments cannot be
  edited or deleted from the invoice screen; unlinked draft deletion remains
  available with a confirmed header/detail save.
- Added checks for numeric quantities, work-order/output/QC delivery limits,
  inbound acceptance/rejection limits, and overpayment of known invoice totals.
- Downstream document creation checks allowed source statuses and required
  source fields; linked downstream documents prevent upstream deletion.
- Better lineage-based auto-fetch for sales enquiry→quotation→order,
  output→QC→delivery, and indent→PO→GRN context. No imaginary item/quantity
  values are manufactured where no source record exists.
- Stale open-page data cannot replace a newer in-memory cache snapshot.

## Setup: required for atomic multi-document persistence
1. Back up the current Supabase database. Run the new SQL file first in **staging**.
2. Sign in using a staging user mapped to the correct `erp_profiles.organization_id`.
3. Verify an enquiry/quotation/order flow, PO/GRN/QC flow, work order/material/
   production/QC/dispatch flow, invoice/payment and return/credit-note flow.
4. Test two browsers editing one document: the second save must show a conflict.
5. Test a deliberately invalid flow, negative quantity, amount exceeding an
   invoice balance, and offline save. The app must not navigate on save failure.
6. Once staging passes, apply the additive SQL upgrade to production as a
   controlled database migration and deploy the frontend.

The SQL script does not remove existing tables/data or replace legacy RPCs.
There are no Supabase credentials included in this package.

## Automated verification executed here
- `node --test tests/*.test.js`: **21/21 passed** (including invoice and workflow rules).
- `node --check` for changed JavaScript backend and rules: passed.
- TypeScript JSX parser checked `src/main.jsx` and `src/premium-forms.jsx`: no syntax errors.
- Full Vite build, ESLint and type-check: **not verified**. `npm ci --offline`
  reported missing npm cache packages; online `npm ci` failed with npm's
  “Exit handler never called” error in this environment.
- Live staging/production Supabase, user/permission matrix, reconciliation,
  browser automation, multi-user load testing: **not run**. Do not claim these pass.

## Important remaining enterprise blockers
This release is a verified improvement, not full enterprise certification.
- The original frontend continues to use shared `erp_ui_state` JSON storage in
  other modules; those modules still use legacy last-write-wins RPCs. Only the
  updated connected transaction pages use the new concurrency protection.
- The SQL functions enforce Supabase authentication and organization scope, but
  per-role create/edit/delete/approve permissions are still not enforced
  everywhere in the backend; the whole ERP must not be considered access-safe.
- Inventory movements, negative-stock prevention, GL posting, tax compliance,
  credit limits, document-number allocation and ledger reconciliation are **not**
  made SAP-level by this patch and need separate normalized transaction APIs.
- Single-field status advances remain a compatibility UI workflow, not a fully
  authorization-gated server-side posting engine.
- Existing report pages and some older modules still require real-data
  reconciliation and full acceptance testing.
- Atomic RPC is opt-in until the SQL is applied; old installs use sequential
  writes and may leave partial handoffs if an RPC fails partway.

Do not push untested upgrades directly into live company data.
