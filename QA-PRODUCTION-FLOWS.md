# Production-flow verification

Date: 23 November 2026. Tested the updated folder using Node.js 24.22.3, Chromium/Playwright and isolated PGlite PostgreSQL. All data used for write tests was synthetic. The customer production database and external mailboxes were not modified.

| Check | Result | Evidence/scope |
| --- | --- | --- |
| ESLint | PASS | Application and test source |
| Configured JavaScript type check | PASS | Existing utility-module check in package.json |
| Unit tests | PASS, 165 tests | Fetch, amounts, GST, release gates, legacy compatibility, reports, sessions, extensions and mocked SMTP handler |
| Production build | PASS | Vite production output |
| Dependency audit | PASS | `npm audit --omit=dev --audit-level=high`: zero reported vulnerabilities |
| Route/report sweep | PASS | 185 desktop routes; generated 77 reports; no captured browser runtime errors |
| Accessible form/action sweep | PASS | 92 reachable create actions across 185 menu pages; sections opened on desktop and mobile |
| Transaction parity/editor sweep | PASS | 58 inline schemas; header pages, product add/remove, charge add/remove, assignment, eligible Fetch dialog and draft persistence/reload |
| Manufacturing workflow | PASS | Enquiry → quotation → SO approval → PO → GRN → passed inward QC → WO → completed route operations → output → passed outward QC → DC/dispatched/delivered → invoice → payment → source enquiry closure |
| Labour workflow branch | PASS | Job inward → passed inward QC → SO approval → WO; bypasses purchasing and preserves customer/item lineage. The shared downstream production/invoice/payment components are exercised in the manufacturing chain |
| Partial Fetch | PASS | 5-item dispatch; first invoice reserves 3, next invoice sees 2; excessive request rejected; all 5 reserved after second draft; source/root-line lineage retained |
| Database regression | PASS | Original workspace roles, CAS, backup/restore, price lists, password policy and extension guards with new migrations installed |
| Database process controls | PASS | Actual guarded RPCs: multi-document atomic commits, register projections, source gates/reservations, stale snapshots, forged totals, maker/approver separation, immutable lineage, restricted numbering and private authorization table |
| Stock/payment/closure database guards | PASS | Prevent worsening negative stock, premature closure, overpayment and paid-invoice edits; cash 200 + TDS 36 settles a 236 invoice; another 1 is rejected |
| Reorder extension | PASS | Saved policy → atomic normal draft indent → duplicate prevention → reload |
| Finance extensions | PASS | Dated ageing, posted credits, CSV export, follow-up save/edit, linked invoice navigation, denied source access and failed-save preservation |
| Extension responsive actions | PASS | Four extension screens at 1440, 1280, 1024, 768, 390 and 320 px; action labels unbroken and pinned table actions reachable |
| Masters/uploads | PASS | Product/party/BOM/route forms, CSV import/template, image validation/preview, attachments saved/downloaded and master dialog Escape handling |
| Session recovery | PASS | Single refresh after 401, rotated token persistence, subsequent save, revoked session returns to sign-in |
| Zoho Edge Function | PASS, isolated | Deno check using locally installed pinned npm dependencies; actual handler tested with mocked SMTP/Supabase for session/origin/export checks, TLS settings, recipient injection rejection, idempotency and unknown-send handling |
| Zoho database jobs | PASS | Approved saved invoice only; private jobs; idempotency; status completion restricted to service role |

## Reproduce

Use the commands in PRODUCTION-FLOWS-UPDATE.md. `npm run test:browser` runs the eight browser suites. They were also executed independently on their own fixture ports. `npm run test:sql` runs the baseline regression and guarded process suite; the latter applies the combined release SQL bundle. The TypeScript Edge Function was additionally checked in a temporary dependency workspace; frontend dependencies and lockfile were not changed for that check.

## Deployment acceptance still required

- Apply the included SQL to the target Supabase project before deploying this frontend.
- Verify actual existing records that have missing original dates/item details using the reconciliation UI. Automated tests cannot establish missing business facts.
- Configure and deploy the Zoho function with the company's SMTP credentials, correct sender and exact allowed frontend origins; send one approved test invoice and confirm receipt.
- Confirm production Supabase/Vercel environment configuration, staff permissions and one real staging transaction before production rollout.
- GST e-invoice provider integration is intentionally not enabled; provider configuration was unavailable and the user chose to skip it.

These results establish the tested code and isolated flows. They do not certify every combination of production records, external services or roles, and no deployment is claimed.
