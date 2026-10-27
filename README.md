# DFAB OneERP

Manufacturing ERP frontend for DFAB Stainless Systems with Supabase PostgreSQL persistence.

## Production setup

1. Configure `.env` with the Supabase Project URL and Publishable Key.
2. Run **only** `supabase/DFAB_ERP_PRODUCTION.sql` in Supabase SQL Editor.
3. Create/login users through Supabase Authentication.
4. Run `npm install` and `npm run dev`.

## Connected business flows

- Order-to-Cash: Enquiry → Quotation → Sales Order → Work Order → Material Request/Issue → Route → Production Output → Outward QC → Delivery Challan → Sales Invoice → Customer Receipt.
- Procure-to-Pay: Purchase Indent → Indent-to-Order → Purchase Order → GRN → Inward QC → Purchase Invoice → Vendor Payment.
- Outsource/Job Work: Work Order → Outsource Issue → Outsource Receipt → Quality → Return/closure.
- Returns/Adjustments: Sales Return → Credit Note/payment adjustment plus controlled scrap/stock adjustment.

The UI contains status gates so downstream documents cannot be created from invalid upstream states.

## Verification

```powershell
npm run verify
```

`verify` runs lint, JS type checking, unit tests and the Vite production build.
