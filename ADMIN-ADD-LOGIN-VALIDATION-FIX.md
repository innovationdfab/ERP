# Admin Add Login: outdated Edge Function validation

The screen showed `Valid employee email, name, department and role are required` despite requiring only email, role, password. This exact message is not emitted by the current source Edge Function. It means the function deployed to the Supabase project is an older version.

## Source changes
- Admin Add Login: optional Name field (when blank, display name derived from email), email/role/password still required.
- Admin API: clear message when the old deployed function rejects the new form.
- Edge Function: honors optional Name, derives one if omitted, no required department, verifies role/account.
- No other UI or transaction logic modified; no SQL migration required for this mismatch.

## Essential deployment
1. Check Vercel and local .env point to the Supabase project holding the employee Auth users.
2. Supabase Dashboard -> Edge Functions -> `erp-admin-invite` -> edit its `index.ts` using **the source in this ZIP**; deploy. (Or use Supabase CLI deploy to that exact project.)
3. Ensure `ERP_ALLOWED_ORIGINS` contains exact localhost origin and deployed domain; function JWT and caller authorization checks must remain enabled.
4. Refresh ERP Admin -> Logins, create a test account (email, role, password; name optional), then check Supabase Authentication -> Users and ERP Logins. Do not retry a previously partially saved account without confirming its status.
5. For an existing Auth account like Monika, use Edit -> Update password; Create is not an account reset.

## No SQL required
The prior `ERP_ADMIN_EMPLOYEE_PROVISIONING_REPAIR.sql` must already be installed. The error quoted above comes from the old Edge Function, not an SQL statement. Do not run full ERP setup SQL or change stored users.

## Verification
Static source-level tests only. Live Supabase function deployment and actual sign-in cannot be verified from these local sources.
