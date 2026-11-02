# Transaction and page clarity review — 2 November 2026

Transactions were reviewed first, in the existing subsection order below. No menus, pages, data fields, backend rules or new business features were added. The remaining 88 pages retain their own layouts and operations, with shared presentation spacing, borders, readable tables and wrapping action bars. Home, login and navigation are excluded from the visual overrides. Existing settings behavior is unchanged.

## Where the flow is shown

- Register: Transactions / subsection identifies the location. Create, Fetch (where sources exist), export, filters, status counts and pagination remain available.
- Opened record/editor: the existing timeline is replaced by a concise **source → current document → next task** strip. It reflects actual saved source links and the current manufacturing/labour/branch rules; standalone stock pages do not imply a manufacturing milestone.
- When the saved source is available in the expanded transaction workspace, its link opens that exact record. Navigation away from unsaved edits requires the existing discard confirmation. Older summary links are displayed from their saved lineage; no source is invented.
- Details: original header fields and paged input groups. Items: original product, pricing, tax and specification fields, charges, invoice expenses and route operations where applicable. The row remove action now stays beside the product code during horizontal scrolling.
- Assignment, attachments and quality retain their original controls. Workflow contains saved history; approval/Continue/dispatch actions stay above the sections. Assigned task links open their actual document.

## Existing transaction subsections

### Purchase

| Page | Existing source / flow | Where to use it |
| --- | --- | --- |
| Purchase Orders | Fetch: Purchase Indents, Outsource Issue DC, Sales Orders. Next: GRN. Labour next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Vendor Price List | Select product/vendor → view prices → Add Price → Save Price | Existing product/vendor browser and price dialog |
| Purchase Indents | Fetch: Manual entry. Next: Purchase Orders | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Customer Price List | Select product/customer → view prices → Add Price → Save Price | Existing product/customer browser and price dialog |
| Indent To Order | Create/review conversion entry → existing row action → Purchase Orders | Existing conversion register, modal and row actions |
| GRN | Fetch: Purchase Orders. Next: Inward QC. Labour next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Purchase | Fetch: GRN, Inward QC. Next: Vendor Payments | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Tally Link - Purchase | Maintain voucher and recorded sync status; external synchronization is not configured by this cleanup | Existing voucher register and modal |

### Marketing

| Page | Existing source / flow | Where to use it |
| --- | --- | --- |
| CRM Pipeline | Create/review lead → existing stage controls → linked Sales Enquiry summary; complete its original item details before release | Existing lead register, modal and row actions |
| Sales Enquiries | Fetch: Manual entry. Next: Sales Quotations. Labour next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Sales Quotations | Fetch: Sales Orders, Sales Enquiries. Next: Sales Orders. Labour next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Sales Orders | Fetch: Sales Quotations, Job Work Inward, Inward QC. Next: Purchase Orders. Labour next: Work Order | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |

### Sales

| Page | Existing source / flow | Where to use it |
| --- | --- | --- |
| Sales Invoice | Fetch: Sales Orders, Delivery Challan, Job Work Return DC. Next: Customer Payments | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Delivery Challan | Fetch: Sales Orders, Outward QC. Next: Sales Invoice | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Tally Link - Sales | Maintain voucher and recorded sync status; external synchronization is not configured by this cleanup | Existing voucher register and modal |
| Sales Return | Fetch: Sales Invoice. Next: Credit Note | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Proforma Invoice | Fetch: Sales Orders. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Credit Note | Fetch: Sales Invoice, Sales Return. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |

### Stores

| Page | Existing source / flow | Where to use it |
| --- | --- | --- |
| Material Issue | Fetch: Material Request. Next: Route Cards | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Scrap Entry | Fetch: Manual entry. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Opening Stock | Fetch: Manual entry. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Excess Stock | Fetch: Manual entry. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Shortage Stock | Fetch: Manual entry. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Production Output | Fetch: Work Order, Route Cards. Next: Outward QC | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |

### Quality Control

| Page | Existing source / flow | Where to use it |
| --- | --- | --- |
| Inward QC | Fetch: GRN, Job Work Inward, Outsource Receipt. Next: Work Order, Purchase. Labour next: Sales Orders | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Outward QC | Fetch: Production Output, Route Cards. Next: Delivery Challan | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Inward Quality Rejection | Fetch: Manual entry. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Inward Quality | Fetch: Job Work Inward. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |

### Production

| Page | Existing source / flow | Where to use it |
| --- | --- | --- |
| Work Order | Fetch: Sales Orders, Rejection Note. Next: Route Cards, Material Request, Outsource Issue DC | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Outsource Issue DC | Fetch: Work Order, Route Cards. Next: Outsource Receipt | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Job Work Inward | Fetch: Manual entry. Next: No next transaction. Labour next: Inward QC | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Job Work Return DC | Fetch: Manual entry. Next: Sales Invoice | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Outsource Receipt | Fetch: Outsource Issue DC. Next: Inward QC | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Material Request | Fetch: Work Order. Next: Material Issue | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Route Cards | Fetch: Work Order, Material Issue. Next: Production Output, Outsource Issue DC | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |
| Rejection Note | Fetch: Manual entry. Next: No next transaction | Register → Create/Fetch/Open → Details/Items/Quality (if applicable)/Assignment/Attachments (if applicable)/Workflow. Actual source/current/next appears directly below the document title; actions remain above the sections. |

### Approvals

| Page | Existing source / flow | Where to use it |
| --- | --- | --- |
| Pending Approvals | Pending document → Review document → Approve/Reject | Approval list, then the opened document action bar |

### Payments

| Page | Existing source / flow | Where to use it |
| --- | --- | --- |
| Vendor Payments | Released purchase invoice → Add payment → validate allocation → Save → History | Invoice balance table and payment details |
| Customer Payments | Released sales invoice → Add receipt → validate allocation → Save → History; close source only after delivery/payment checks | Invoice balance table and payment details |

SOP Workflow retains both provided SOP overviews and assigned tasks. Route-card production-output inclusion retains its existing direct outward-QC path. All release, approval, inspection, quantity, source reservation and payment gates are unchanged.

## Scope, checks and setup

The reference website session had expired during this pass. This review uses the fields and Pickup choices inspected earlier in this conversation plus the current project and its actual saved workflow graph. No new live-site revalidation, live transaction write, deployment or database migration is claimed.

The full field/source/next-step matrix is in `TRANSACTION-REVIEW.json`. `CLARITY-AUDIT.json` records the local browser results. Tests use the supplied seed data and mocked Supabase transport. The existing production accounting/inventory/integration limitations in START-HERE-SOP.md still apply.

Extract into a fresh folder, retain the existing `.env`, then run `npm ci` and `npm run dev`. Rebuild/redeploy the updated source for hosted use. No additional SQL migration is required.
