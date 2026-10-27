# DFAB OneERP · Production Supabase Setup

This build uses one new SQL file only:

`supabase/DFAB_ERP_PRODUCTION.sql`

The production objects use the `erp_` prefix and do not depend on any earlier ERP SQL file.

## 1. Supabase environment

Create `.env` from `.env.example` and set:

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_KEY
```

Never place the database password, service-role key, or `sb_secret_*` key in the Vite frontend.

## 2. Run the schema

Open Supabase → SQL Editor → New query, paste the complete contents of `supabase/DFAB_ERP_PRODUCTION.sql`, and run it once.

The script creates a DFAB organization, maps existing Auth users to the organization, creates an Administrator role, and installs the full ERP data model, RLS policies, audit triggers, document numbering, stock/receivable/payable views, and the compatibility RPCs used by the current UI.

## 3. Create/login users

Create employees in Supabase Authentication. Existing users at schema-install time are mapped automatically to DFAB and the Administrator role for the initial rollout. New users receive an ERP profile but no automatic administrator role.

## 4. Data architecture

Core production tables are normalized: products, partners, BOM/routing, enquiries/quotations/orders, procurement, GRN/QC, inventory movements, work orders, route execution, outsourcing, dispatch, invoices, returns, payments, approvals, attachments, notifications, and audit.

The current screen set persists through `erp_get_ui_state`, `erp_put_ui_state`, and `erp_delete_ui_state`. The snapshot is JSONB (PostgreSQL TOAST-compressed when large) and is expanded into `erp_ui_records` for record-level visibility. This compatibility layer preserves the existing UI while the normalized model provides the production database foundation.

## 5. Start the app

```powershell
npm install
npm run dev
```

Then login with a Supabase Auth email/password.
