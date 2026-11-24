# DFAB OneERP — Admin Add Member Repair

Scope: ONLY `src/admin-control.jsx`, `supabase/functions/erp-admin-invite/index.ts`, and one new Admin-only SQL migration. No ERP transaction, login, navigation, CSS, or other database scripts changed.

## Why Add Member could fail

Supabase Auth account creation happened before a separate call to `erp_admin_save_user`. That existing function expects an ERP profile created by an `auth.users` trigger. A missing trigger/profile made complete forms fail during the second stage. The new `erp_admin_provision_employee` validates the Auth identity and provisions any missing ERP profile plus role and department within one database transaction, using the original audited Admin role-assignment function.

## One-time installation

1. Make a database backup / test in staging, then open the **same** Supabase project configured by `VITE_SUPABASE_URL`.
2. Verify the existing `ERP_ADMIN_CONTROL.sql` was previously applied. Do NOT rerun the full setup or destructive migrations.
3. Run **only** `supabase/ERP_ADMIN_EMPLOYEE_PROVISIONING_REPAIR.sql` in the Supabase SQL Editor. It is additive and non-destructive. It will fail safely if prerequisites are missing.
4. In Supabase Edge Functions, replace `erp-admin-invite` with `supabase/functions/erp-admin-invite/index.ts` from this release and deploy with JWT verification / Admin authorization enabled.
5. Ensure `ERP_ALLOWED_ORIGINS` includes your actual dev and production origins. Keep service-role credentials only on Supabase.
6. Deploy the frontend and create one **new non-admin test employee** from Admin > Saved logins. Confirm the new account in Supabase Authentication > Users, and the profile/role in ERP Saved Logins. Sign in with the exact temporary password, change it on first login, then confirm ERP access.
7. For an account that already partially exists, DO NOT repeatedly click Create. Check Authentication > Users and Saved Logins; fix that specific identity first. This migration intentionally does not reset or delete existing users.

## Diagnostics

- `403 Administrator authorization required`: actor is not an active Admin with SYSTEM.ADMIN permission.
- `503 employee-provisioning SQL is missing`: migration was not installed or PostgREST schema cache not refreshed.
- `422 ERP profile or role assignment failed`: read exact error and check department/role IDs, DB permissions, and organization membership.
- `409 employee already exists`: edit/reconcile the existing entry, do not create a duplicate.
- Network `Failed to fetch`: verify Edge Function deployment, CORS, project URL and secrets.

No SQL migration can guarantee a correctly deployed Edge Function or repair a separate browser/network problem. Live Supabase access was not available during packaging.
