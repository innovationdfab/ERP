# DFAB OneERP: i-MANTRA checklist integration

Source reference: user-provided **i-MANTRA features (2) (1).pdf**, page 1 (feature checklist). This integration is an extension of the last corrected DFAB ERP. It does not copy i-MANTRA's proprietary source code.

## Scope / preservation
- Existing dashboard, DFAB branding, styles, login/session, tables, original navigation entries, production SQL, existing records and stored keys remain unchanged.
- Additive work is concentrated in `src/imantra-integration.js`, `src/imantra-stock.js` and their wiring in `src/main.jsx`. New sections appear under the existing Transactions and Reports sidebars; no existing section was deleted.
- New workflow pages reuse existing confirmed Supabase save, data suggestions, back/status controls, and CSV/Excel-compatible export.
- New document keys use `dfab-erp-<Module Title>`. The database still needs the existing UI-state RPCs, and production deployments should use the previously supplied flow-integrity SQL upgrade for atomic batched saves.

## Source feature coverage

| PDF group | Existing DFAB pages reused | New connected documents or reports |
|---|---|---|
| Procurement | Purchase Indents, Indent To Order, Purchase Orders, GRN (Goods Receipt), Purchase Invoice, Sales Return, Pending Approvals | Import Purchase |
| Planning | Work Order and PO flows | Procurement Planning/Schedule, Production Schedule, Dispatch Schedule, Project Planning |
| Jobwork | Outsource Issue DC, Outsource Receipt, Job Work Inward/Return DC | Job Order, Jobwork Material Issue/Receipt, Service Invoice |
| Production | Work Order, Material Request/Issue, Route Cards, Production Output, Scrap Entry | Input to Production, Stage Receipt/Consumption, Excess Issue, Return to Store, Dispatch Intimation |
| Inventory | Production BOM, Work Order, Opening/Excess/Shortage Stock | BOM-Based Work Order, Stock Adjustment, Material Reserve/Unreserved |
| Sales | Sales Enquiries, Sales Quotations/Orders, Sales Invoice, Proforma Invoice, Credit Note, Delivery Challan | Terminate Order, Project Order, Delivery Channel, Purchase Return |
| Warehouse and QC | Inward QC, Outward QC, Inward Quality | Pick Slip, Put Away, In-process QC, Job Work QC |
| Reports | Existing sales, procurement, stock, production, and QC reports remain | 29 new read-only control/register reports using actual saved rows, plus computed posted stock view |

## Connected-document behavior
- The additional documents use the same persistent Supabase-backed state as the existing workflow pages. Drafts do not become posted inventory merely by being created.
- Source references use stored PO/SO/WO/BOM/GRN and the new linked document identifiers where configured. Missing references, invalid/negative quantities, and required empty fields block saves/approval advancement.
- Source-to-target handoff copies only values actually present in the source. Physical receipt and QC quantities are **not invented** from planned quantities. A forward action creates a reviewable first-status document and stores a workflow link; the user must enter missing operational details before advancing.
- Posted stock calculations use accepted GRNs, posted opening/adjustments, issued material, posted returns, accepted production output and confirmed scrap. Draft or pending quantities are excluded. Available stock is only as accurate as the historical posted transaction data. Stock valuation uses known opening rates and labels absent rates as `Not costed`.

## Deployment / verification
- `node --test tests/*.test.js` completed with **26/26 tests passed**.
- TypeScript `transpileModule` reported **0 JSX parse diagnostics** on `src/main.jsx`.
- `node --check` passed for new JavaScript modules.
- **Full Vite build, lint, live Supabase persistence, concurrent users and actual invoice/stock posting have NOT been verified in this environment.** `npm ci` could not complete (missing offline packages / online timeout), and therefore no production deployment certification is claimed.
- Existing Supabase `.env` is intentionally not included in the handoff ZIP. Copy your current `.env` into the extracted folder, then run `npm ci`, `npm run verify`, and staging tests before deployment.

## Separate integrations still required; do not consider these completed
The reference PDF also lists Barcode-Based Inventory Movement, Sales E-Invoice Automation, Sales Order Gateway, Sales Forecast Portal, Route Card Process Monitoring Portal, Forecast/Order-Based PPC Module, automated approval emails, and multi-window features. Full external integration or portal operation needs device/API specifications, providers and permission design; these are **not implemented** here. Existing activity logs, roles/permissions and backup pages remain unchanged, but do not constitute a server-side security audit. Reports export as Excel-readable CSV, not native `.xlsx`.

## Staging acceptance tests required
1. Create/approve an indent; convert to PO; process GRN→Inward QC with actual accepted/rejected quantities.
2. Create Sales Enquiry→Quotation→SO→WO→Material Request/Issue→route/stage output→QC→DC→Sales Invoice→payment.
3. Create schedules and verify they remain plans until real receipts/issues exist; validate incomplete record rejection.
4. Run Purchase Return, Store Return and Stock Adjustment through approvals and compare posted stock report to actual ledger.
5. Create Job Order→Jobwork Issue/Receipt→Job Work QC, then check every link and report.
6. Reload in another browser/user and confirm every document survives the session and permission boundaries behave as designed.
7. Run financial and inventory reconciliation against a controlled sample dataset before allowing real production transactions.
