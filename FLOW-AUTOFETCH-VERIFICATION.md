# Flow & Auto-Fetch Verification

Validated on 27 Oct 2026.

## Fixes applied
- Transaction workflow pages remount per active module to prevent stale rows crossing into a different storage key.
- Added database suggestions for Output No, Issue DC, Inward No, QC No/Inspection No and Delivery Challan references.
- Added reference auto-fetch for Enquiry, Quotation No, SO No, Work Order/WO No, PO No, GRN No, Output No, Issue DC, Inward No, Purchase Invoice and Sales Invoice.
- Restored/connected Purchase -> Vendor Payments, Sales Return -> Credit Note, Credit Note -> Customer Payments and Job Work Inward -> Job Work Return DC.
- Route Card starts Completed Qty at 0 when created through the workflow.
- Production Output starts Reject Qty at 0 when created through the workflow.
- Material Issue can forward only from Issued state.

## Verification
- ERP utility tests: 6/6 passed.
- Backend helper syntax checks passed.
- 21 configured next-document targets resolve to valid ERP pages.
- Production build was attempted, but npm dependency installation timed out in the execution environment. No build-pass claim is made.
