# DFAB OneERP — Manufacturing and Labour Workflow Upgrade

Updated 2 November 2026 from the uploaded DFAB project, the signed-in iMANTRA reference and both supplied SOP images.

## Start and database setup

1. Keep the existing Supabase project and existing `.env` values. The uploaded ZIP did not contain live credentials.
2. For a new database, run `supabase/DFAB_ERP_PRODUCTION.sql` first. For an existing configured database, do not rerun bootstrap just to install this upgrade.
3. Run the additive `supabase/DFAB_PROCESS_UPGRADE.sql` in that project's SQL Editor. It creates two RPCs; it does not truncate or delete company data.
4. Existing users need their existing ERP organization profile and the appropriate existing `ERP.CREATE`, `ERP.EDIT`, `ERP.APPROVE`, or `ERP.DELETE` permissions. No new user or password is embedded in this project.
5. Use Node 22.12+ (Node 24 supported), then `npm ci` and `npm run dev`. Use `npm run build` for the deployment build.

The existing welding torch login, session restoration, company logo, masters, source seed data, reports, exports, backup, menus and styling files remain in the package. The changed transaction routes use the expanded workspace; legacy records retain their original storage keys and summary layouts. No reference-site transaction was submitted, approved, deleted or changed during inspection.

## Workflow usage

Open Transactions → SOP Workflow, or use the Manufacturing & Labour SOP button on Home.

- Manufacturing & Supply: enquiry → quotation → sales order → purchase order → GRN → inward QC → work order → route card → production output → outward QC → delivery challan → invoice → receipt.
- Labour Job Work: job inward → inward QC → sales order → work order → route card → production output → outward QC → delivery challan → invoice → receipt.
- Work orders also retain material request/material issue and outsourcing branches. Purchase invoices lead to vendor payments. Return/credit workflows remain available.
- Every release requires the next responsible user, department and target date. Drafts may be incomplete assignments.
- Create next documents from a released/approved source using Continue. Saved source references and inherited lines persist. Duplicate handoffs open their existing child instead of creating another.
- Choose the supplier on purchase orders. The downstream manufacturing work order retrieves the finished product lines and customer from the linked sales order.
- QC requires an inspector and reconciled accepted/rejected quantities. Rejected lots cannot advance. Split lots must be recorded separately.
- Route cards support in-house/outsourced operations and required operation QC. Active master-route operations can be loaded. Complete operation quantities and QC before advancing.
- If production output is already included in the route card, its explicit checkbox permits the direct route-card → outward-QC path shown in the SOP.
- Approvals appear in Pending Approvals. The database checks approval permissions.
- Dispatch and delivery are separate confirmations. Delivery can complete a fully delivered sales order. Receipt allocation tracks cash, TDS and LD. Closing the linked enquiry or labour work order checks payment and delivery completeness.
- PO/SO detail lookups, raw-material document lookup, sales details, customer payment overdue reporting and route process pricing are available under their reference menu names.

## Data and preservation

Only `src/main.jsx`, `src/backend/cloud-store.js`, `src/backend/supabase-rest.js` and `package.json` among the original project files were edited. Other original files are retained. New modular source files contain the expanded fields, transaction UI, workflow rules, document adapters and styles. `PRESERVATION-CHECK.json` records byte comparisons against the original ZIP.

Transaction details are saved through the existing Supabase UI-state compatibility layer. Each commit groups the full document, original summary projection, invoice details and/or workflow link. Expected payload checks reject stale concurrent edits. Number reservation checks legacy rows to avoid replacing an existing document number. Failed writes keep the editor open. Database audit triggers continue to identify the authenticated writer. Linked documents and invoices with payment allocations cannot be deleted through the new UI.

Attachments accept images, PDF, text, CSV, Excel and Word files up to 2 MB each. They remain document attachments; uploading a spreadsheet does not import its transactions. The existing master import functions are retained. No automatic live-site data import or ongoing synchronization is installed.

## Production scope and limitations

This is an enterprise workflow UI and persistence upgrade, not a complete SAP implementation or statutory accounting certification. The original normalized database model is retained, but the expanded transaction screens still persist through compatibility UI records. They do not automatically post double-entry journals or immutable normalized stock movements. Validate and implement those postings before treating stock balances, costing, payables/receivables reports or financial statements as production books. Existing report screens were retained. Pending receivables, pending payables and overdue-report adapters use the saved payment allocations. A successful render is not proof of accounting accuracy.

The new payment register and the three balance-report adapters calculate balances from saved allocations, including supported original payment rows without double counting. Reconcile them against the actual company books before finance sign-off. E-invoicing, e-way bills, GST filing, bank transfers, external mail and Tally synchronization require their separately configured services; recording their reference fields does not call those services. No mock is used in the normal application.

Some reference System application links and the Categories link redirected to Home for the signed-in account. Their ZIP modules were preserved rather than claiming inaccessible settings were copied. Legacy invoices with summary data only retain their amount; enter original lines before changing them. Partial QC acceptance requires separate accepted/rejected lots. Cross-currency accounting, inventory availability checks and granular per-record row permissions require additional production work.

## Verification

`npm run verify` runs lint, the existing configured utility/backend type-check scope, unit tests and a production build. It is not a full TypeScript check of the JSX application.

`npm run test:process` runs local Chromium integration with a mocked Supabase transport and the supplied original seed snapshot. Install Chromium with `npx playwright install chromium`, or provide `ERP_CHROMIUM_PATH` to an installed Chromium executable. The test transport exists only in `tests/browser-process.mjs`. It never connects to a live company database.

See `VERIFICATION-SOP.md` for the actual results and their limits.
