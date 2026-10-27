# DFAB OneERP — UI Redesign & Flow Verification

## Scope
This build starts from the latest strict working ERP and changes only the application shell/layout styling plus connected workflow handoff behavior in `src/main.jsx` and `src/styles.css`.

## New placement system
- Full-height left workspace rail for brand, quick access and module explorer.
- Command bar inside the working area for breadcrumb, search, notifications and profile.
- Connected process dock below the command bar for Order-to-Cash, Procure-to-Pay, Outsource/Job Work and Returns/Adjustments.
- Scroll-contained working canvas so each module stays inside the viewport.
- Responsive drawer behavior on tablet/mobile.

## Flow hardening
- Sales Enquiry -> Sales Quotation gate.
- Sales Quotation -> Sales Order gate.
- Sales Order -> Work Order gate.
- Purchase Indent -> Indent To Order -> Purchase Order -> GRN -> Inward QC.
- Purchase invoice -> Vendor Payment.
- Work Order -> Material Request -> Material Issue -> Route Card -> Production Output -> Outward QC -> Delivery Challan -> Sales Invoice.
- Sales Return -> Credit Note -> Customer Payment.
- Job Work Inward -> Job Work Return DC.
- Duplicate downstream document creation remains blocked through workflow links.
- Selected source documents advance to the appropriate forward status after successful conversion.

## Preserved
- Supabase SQL/schema.
- Supabase cloud-store adapter.
- Restored ERP datasets.
- Existing master/product/account/production module components.
- Existing storage keys and saved records.
- Authentication/session behavior.
- Notifications and database suggestions.

## Verification
- ERP utility tests: 6/6 PASS.
- Backend/cloud/restore JS syntax checks: PASS.
- 28 configured workflow stages resolved.
- 21 explicit connected transitions resolved to valid destinations.
- Full Vite build/lint not completed in this environment because dependency installation could not complete; run `npm install && npm run verify` locally before production deployment.
