# Live-audit fix verification — 24 November 2026

Tests use isolated authenticated browser fixtures and temporary PostgreSQL. No production records, permissions, emails, secrets or deployments were changed. All previously working source files remain present; unrelated theme/navigation/login/master code is unchanged.

## Results

| Check | Result |
| --- | --- |
| ESLint | Passed |
| Configured JavaScript utility type check | Passed; existing scope is `src/erp-utils.js` |
| Unit/service tests | 186 passed, 0 failed |
| Production build | Passed; existing non-fatal Lucide `use client` bundler notices remain |
| Production dependency audit | 0 vulnerabilities reported |
| PostgreSQL migration/workspace tests | Passed |
| Fresh single-file SQL bundle | Passed |
| Reapply existing-install update | Passed, with business payloads unchanged and guard still active |
| Menu/report browser sweep | 185 pages opened and 77 reports generated |
| Inline reference transaction forms | 58 forms; headers, products, charges, assignment, Fetch, saved draft/reload checked |
| Create-form actions | 92 create forms and accessible sections, desktop/mobile |
| Master/import/attachment regressions | Passed |
| ERP Extensions | Reorder, ageing, statements, follow-ups, persistence, restricted roles, failed-save handling and six viewport widths passed |
| Session regression | Expiry refresh, rotated tokens, subsequent save and revoked-session sign-out passed |
| Partial dispatch Fetch | Pending quantities, over-selection rejection, source lineage and reservations passed |
| Manufacturing workflow | Enquiry → quotation → SO → purchasing → GRN/QC → WO/route/output/QC → dispatch → invoice → payment → closure passed |
| Labour workflow | Job inward → QC → SO → work order passed; mobile editor passed |
| Previous filter/feedback audit | Search, inclusive dates, reset, invalid ranges, rejected-save retry, invoice terms and save/approve/delete feedback passed |
| New live-audit fixture | Cross-source invoice quantities, email status/retry with an authenticated token, database readiness and reconciliation search passed |

The ten browser suites completed successfully. The final manufacturing and new focused fixture were rerun after the last source-line identity hardening. No runtime errors were recorded in the successful browser runs. One extension fixture was updated to mock the newly working email status request; this did not require a product-code workaround.

## New quantity regression coverage

- A completed order already invoiced through its challan cannot offer the same quantities for direct invoicing.
- Partially billed orders/challans share the remaining order-item budget.
- Separate items with the same product code, separate orders and different source paths remain independent.
- Drafts reserve; rejected invoices release; the invoice being edited is excluded from its own reservation count.
- Source-line ancestry follows the explicit source-line ID before any older retained ID fallback. A colliding child ID cannot select a different commercial budget.
- Editable references cannot change the underlying saved item ancestry. Incomplete/circular ancestry does not offer new invoice quantities.
- The actual SQL RPC rejects cross-path over-allocation and a legacy-flag bypass attempt, rolls back every paired write, and denies direct access to the private base RPC.
- Existing concurrency, totals, permissions, source reservations, stock guards, invoice terms, payment allocation, closure and email-request idempotency checks remain covered.

## Repeat checks

```sh
npm ci
npm run verify
npx playwright install chromium
npm run test:browser
npm install --no-save --package-lock=false @electric-sql/pglite
npm run test:sql
ERP_SQL_BUNDLE=DFAB-OneERP-All-In-One.sql node tests/production-sql.mjs
npm audit --omit=dev --audit-level=high
```

For a separately installed Chromium or PGlite, set `ERP_CHROMIUM_PATH` and `ERP_PGLITE_DIR` respectively. Optional QA packages are not required by the deployed app. The browser suites were executed in independent groups with separate fixture ports; `test:browser` runs the same ten suites serially.

## Deployment acceptance remaining

Apply RUN-THIS-UPDATE.sql, deploy the frontend and updated invoice-email Edge Function, then use the in-app database/email setup checks on your own project. The live site has not yet received this package.

Genuinely missing historical values must be entered after verifying original documents. The software cannot infer unknown currencies, dates, amounts or SMTP credentials. Real Zoho authentication/delivery, actual staff-account permissions and a full labour dispatch/payment workflow remain environment acceptance checks; they are not claimed as live certifications here.
