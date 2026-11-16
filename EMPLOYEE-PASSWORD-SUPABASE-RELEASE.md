# DFAB OneERP — Employee password controls & login-page cleanup

Base: the preceding `DFAB-OneERP-Connected-Data-Login-Fixed.zip` release, which was based on the user's uploaded `DFAB-OneERP-Connected-Data(1).zip`. Existing business modules, document workflows, database schema, login session logic, other UI and data are unchanged.

## Updated employee experience

- **Admin → Employees → Add employee**: work email, name, department, role; now includes **Temporary password**, **Confirm password**, and a show/hide checkbox for non-admin employees. The administrator can supply a unique password of 12–128 characters containing letters and digits, or leave both fields empty to use the previously configured server-side initial password.
- **Admin → Employees → Edit**: active, non-admin employees can receive an explicitly entered temporary password with separate confirmation. Changing department/role with **Save employee** does not change their password. Existing **Set initial password** and **Initialize team logins** controls retain their original actions.
- Admin/system-role identities use individual email invitations rather than a shared known password. Switching to an Admin role clears draft password fields.
- The signed-out **login page Admin button is removed**. The authorized Admin button in the ERP top bar remains.
- Incorrect login and protected Edge Function failures now display more relevant messages. No new fake-success or offline auth fallback was added.

Passwords are not stored in ERP profile tables, localStorage, or a Vite environment variable. They are transmitted over HTTPS to the existing protected Supabase Edge Function, which uses Supabase Auth's server-side Admin API. The password fields are cleared after successful account creation or reset, cancellation, or Admin tab navigation. New accounts that fail ERP permission assignment are rolled back when Supabase allows it; an explicit error is reported if rollback itself fails.

## Required existing Supabase configuration

1. Use a staging Supabase project first. The existing schema plus `ERP_ADMIN_CONTROL.sql` and `ERP_INITIAL_LOGIN_PASSWORD_POLICY.sql` must already be applied in their documented order. **Do not rerun the full fresh database script on a populated project.** The password controls introduce **no new SQL migration**.
2. Update the project's protected `supabase/functions/erp-admin-invite/index.ts` Edge Function and deploy it with JWT verification enabled:
   ```powershell
   supabase functions deploy erp-admin-invite
   ```
3. Ensure function secrets are correctly configured, **only on the server**: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and `ERP_ALLOWED_ORIGINS` (comma-separated site origins). `ERP_INITIAL_PASSWORD` is needed only if the Admin leaves both new-password fields blank, or uses the existing default/bulk reset actions. Do not place secrets in `VITE_*` variables.
4. Keep frontend public values in your local `.env` or deployment configuration: `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` (or the supported anon-key fallback). Set Supabase Auth email/site settings for your deployed domain.
5. Use an authorized administrator session; Admin access still depends on `erp_admin_is_admin`, `erp_admin_dashboard`, and `erp_admin_save_user`. The app cannot give an unauthenticated visitor permission to create users.
6. Staging test: create a normal employee with an individual temporary password, verify Auth account and ERP role appear, log in as that employee, complete the forced personal password change, re-login, check department permissions, reset the employee password and verify the previous password fails. Test administrator invitations, duplicate email, missing Edge Function, and a simulated permission assignment failure.
7. If the Admin dashboard says `erp_admin_my_access()` is missing, apply/repair the Admin Control migration and refresh Supabase PostgREST's schema cache (`NOTIFY pgrst, 'reload schema';`). A frontend update alone cannot install a missing RPC.

**Shared default initial password caution:** A previously requested company-wide initial password can still be used through the protected server secret, but individual strong temporary passwords are preferable. Never set a shared known password for administrators or leave it in place for employees. First-login password change remains mandatory. A password reset does not automatically revoke every previously issued JWT; validate token revocation policy separately if instant lockout is required.

## Verification and limitations

- 96/96 automated Node tests passed, including five new password-specific checks.
- TypeScript compiler's JavaScript/JSX/TypeScript parser reported zero syntax diagnostics in changed source and Edge Function files.
- Full Vite build/lint/typecheck could not be completed in this environment because npm dependencies were incomplete, offline cache was missing packages and online installation timed out. This is **not** a verified production build.
- No live Supabase project credentials were available, so no live account creation, password change or database writes were performed. These remain staging/deployment acceptance tests.
- Only requested identity-related application files were changed; no other ERP source file was edited or deleted.
