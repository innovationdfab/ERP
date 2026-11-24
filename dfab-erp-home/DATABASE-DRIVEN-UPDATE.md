# DFAB OneERP - Database Driven UI Update

This build preserves the existing ERP navigation and workflows while making reusable form data database-driven through the existing Supabase UI-state RPC layer.

## Updated behavior
- Product, customer, vendor, UOM, product type, category, group, HSN, department, process, machine/work-center and document references are suggested from saved ERP records.
- Product-code selection can populate related description/UOM and supported rate/drawing fields.
- BOM, Route Card, Sales Invoice and generic transaction forms use the shared database lookup layer.
- Process/sub-process, department users, work centers and machines persist through the cloud state store.
- Notifications are derived from actual pending/rejected/QC/calibration/approval records. The badge is hidden when no real notification exists.
- Reports no longer generate fabricated rows; they project currently saved ERP data where available.
- Deleted seed/demo master data is not recreated automatically.
- Customer/vendor profile audit text uses actual update user/time instead of hard-coded names.

## Persistence
The frontend writes through the existing Supabase RPC-backed cloud store. Local browser storage is not the system of record.

## Verification
- `npm test`: 6/6 passed.
- `node --check src/backend/cloud-store.js`: passed.
- `node --check src/backend/supabase-rest.js`: passed.
- Full Vite build/lint was not completed in this environment because package installation did not finish; run `npm install && npm run verify` locally/Vercel.
