# DFAB OneERP — Employee logins, initial passwords, and locked scope

## What changed

This release is based on the **exact user-uploaded** `DFAB-OneERP-Connected-Data(1).zip`.
Only login/Supabase Auth integration, password setup, and the Admin employee-login controls have changed. No existing ERP transaction, workflow, dashboard, styling, inventory, accounting or master-data implementation was modified.

**Important:** Admin employee cards store `erp_profiles` / `erp_user_roles` in Supabase PostgreSQL. Passwords are **never** stored in those cards or in the browser source. The matching Auth account is stored in Supabase Authentication (`auth.users`). The existing schema links the two by user ID.

## Required staging setup — do not skip

1. Back up the existing database. Check which migrations are already installed. This release **does not** rerun the full database setup or modify your existing ERP data.
2. The existing ERP schema, `ERP_FLOW_INTEGRITY_UPGRADE.sql`, `ERP_PRODUCTION_GUARDRAILS.sql` and `ERP_ADMIN_CONTROL.sql` must be installed, in the documented dependency order. If they are already present, **do not run them again blindly**. Existing administrator logins must have an approved `ADMIN` role and must use their **personal** Supabase password.
3. Apply **only** the new file `supabase/ERP_INITIAL_LOGIN_PASSWORD_POLICY.sql` to a staging Supabase database, **after** the existing admin migrations. It changes two permission helpers so employee tokens still carrying the initial-password flag cannot read/write ERP business data; it does not delete, reset, or seed records.
4. Configure **server-side** Supabase Function secrets (never `VITE_*` variables):

   ```powershell
   supabase secrets set ERP_INITIAL_PASSWORD=dfabsspl
   supabase secrets set ERP_ALLOWED_ORIGINS=https://YOUR_ERP_DOMAIN,http://localhost:5173
   ```

   Make sure your Supabase Auth project's configured minimum password length **allows the requested eight-character initial password**. The default `dfabsspl` is a **weak, shared temporary credential**: change it to a unique one-time password per employee for production security. Never use it for administrator accounts. Share temporary credentials over a secure channel. Supabase Auth may reject the password if your password policy is stronger; do not weaken a company security policy just to use this value.
5. Deploy the **updated** existing Edge Function with JWT verification enabled (default):

   ```powershell
   supabase functions deploy erp-admin-invite
   ```

   This function requires Supabase-managed `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` secrets, plus `ERP_INITIAL_PASSWORD` and the allowed origins above. The `service_role` key must never be copied into the frontend `.env`.
6. Deploy the new frontend and use an **existing authorized administrator's personal login**. The Admin button remains where it was; other ERP pages remain locked.
7. Go to **Admin → Employees**. Choose **Add employee** for new people, or **Set initial password** on an existing non-admin employee. You can also choose **Initialize team logins** after reviewing the destructive bulk confirmation. **Nothing is reset automatically on deploy.** Existing administrator accounts are excluded, including your own account. This controls access via existing role assignments.
8. New non-admin employees (or specifically reset existing ones) can sign in with their **work email** and the configured temporary password. Before ERP data is loaded, they must choose a distinct password of at least 12 characters with letters and numbers. They then sign in with the personal password.
9. If the old error about missing `public.erp_admin_my_access()` appears, the **Admin Control SQL was not installed, not exposed, or its PostgREST schema cache is stale**. Review migration installation and run `NOTIFY pgrst, 'reload schema';` in the Supabase SQL Editor. Do not bypass the login authorization checks.

## What happens to existing users?

- Users already visible in Admin have a database profile and should have a linked Auth user ID (the database's `erp_profiles.user_id` foreign key requires it), but may have been invited without a password.
- New employee creation uses server-side Supabase Auth account creation; this is distinct from assigning a department/role. If role assignment fails, the new Auth account remains **without ERP access**, and Admin must repair that assignment. It is not auto-promoted.
- Existing employees are **not mass-reset automatically**. The explicit bulk action resets up to 40 active non-admin accounts per operation and reports partial failures; verify successful/failed accounts before retrying.
- Disabling or updating an employee's role uses the existing Admin RPCs. The temporary login flow does not edit or delete their previous ERP records.
- Administrator and other protected system roles use individually issued invitation/password setup rather than a shared initial password.

## Verification / remaining limitations

Automated Node tests cover the first-login flag, employee admin controls, the SQL permission gate, token checks and original ERP rules. TypeScript/JSX parser validation covers the modified source. **This workspace has no complete local Vite dependency tree**, so a full Vite build and live Supabase login/migration test have not been completed here.

Before production: run `npm ci`, `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, then perform staging login scenarios (new user, previously invited user, current admin, disabled user, existing user who is not reset, invalid password, restart/refresh during forced password change, role restrictions). Verify that a temporary-password JWT cannot call `erp_get_ui_state` or write via any ERP RPC. Supabase Auth JWTs already issued before a reset may remain usable until expiry; use Auth session revocation controls for urgent lockout and test your project configuration. Backup/rollback must be confirmed.

**No live Supabase account or credential was modified by generating this ZIP.** Apply the migration/function and explicitly initialize the chosen user accounts to make login work in your deployment.
