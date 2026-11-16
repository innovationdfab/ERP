# DFAB OneERP — temporary local Admin Preview & login recovery

## Temporary no-login preview

Run `npm install` then `npm run dev` and open **http://localhost:5173**. On the login card click **View Admin Control locally — no login**. This opens the Admin Control navigation, existing ERP module catalog, and built-in workflow connections without credentials.

**Important:** Local preview is read-only, contains no employee credentials or real production data, does not read or write Supabase, and cannot create users, modify roles, or publish workflows. Other tabs explain why they are locked. It is limited to Vite development on `localhost`/`127.0.0.1`/`::1`, and cannot be enabled on any production hostname or production build. There is no bypass of backend authentication or authorization. Close it via **Back to sign in**.

## Fix the screenshot's error and enable real admin controls

The message `Could not find the function public.erp_admin_my_access without parameters in the schema cache` means Supabase cannot resolve a required administration RPC. It is a database migration/schema-cache problem, not a password problem. The local preview is only for navigation/design inspection and **does not resolve live Admin Control login**.

1. Back up staging database. Apply missing prerequisite migrations from `ADMIN-CONTROL-DEPLOYMENT.md` and then `supabase/ERP_ADMIN_CONTROL.sql` using Supabase SQL Editor in **staging** first. Do not rerun the old bootstrap blindly against production.
2. In the Supabase SQL Editor, run `notify pgrst, 'reload schema';` after the migration. Check `select to_regprocedure('public.erp_admin_my_access()');` — the result must be `erp_admin_my_access()` rather than null.
3. Confirm the authenticated account has an active role and one trusted ADMIN assignment. Review previous broad ADMIN grants before company-wide rollout.
4. Test authenticated login, Admin Control data refresh, user/role changes, and workflow templates in staging. Only after successful checks apply changes to production.
5. Never put a service-role key into Vite variables or bypass login on a public URL to work around this error.

## What changed

New `admin-preview.jsx`, preview styling, preview policy and test. Existing login and ERP modules remain unchanged except a local development preview button and a clearer error for missing administration RPC. No database/schema/data changes were made by this package.
