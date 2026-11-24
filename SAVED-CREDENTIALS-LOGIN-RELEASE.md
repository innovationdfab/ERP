# DFAB OneERP — Account creation and invitation login update

## Scope
Only the employee login UI/creation path, Supabase identity Edge Function, and related credential tests were modified. No departmental ERP forms, business workflows, schemas, or existing records were changed.

## Behavior
- New non-admin logins require an explicit 12–128-character alphanumeric-containing temporary password and confirmation. The server writes that exact supplied value to Supabase Auth, not to ERP employee tables. The new employee changes it on first sign-in.
- New administrators are invited individually by email; their invitation redirects to an allowed ERP origin and opens the existing password-setup view. Admins then log in with their own new password. Shared default administrator passwords are deliberately prohibited.
- Existing employee Auth accounts/passwords remain unchanged. The employee login continues to verify Auth identity and database ERP role.
- Supabase Auth invitation URL tokens are removed from the browser address immediately and not persisted.

## Deploy and configuration
1. Redeploy `supabase/functions/erp-admin-invite/index.ts` to the **same Supabase project** as the frontend. Do not delete the function or redeploy Hello World. Keep authenticated/admin server-side checks enabled.
2. In Supabase Edge Function secrets, set `ERP_ALLOWED_ORIGINS` to the comma-separated exact localhost and production origins, e.g. `http://localhost:5173,https://erp-lyart-beta.vercel.app`.
3. Recommended: set `ERP_AUTH_REDIRECT_URL=https://erp-lyart-beta.vercel.app`. The origin must also be included in `ERP_ALLOWED_ORIGINS`.
4. In Supabase Authentication → URL Configuration, add `https://erp-lyart-beta.vercel.app/**` to the permitted Redirect URLs. Confirm your deployed domain is correct.
5. Keep `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` aimed at this same project. Never put the service role key in Vercel.
6. Test new employee: Add Login with explicit password, verify Auth Users and Admin Saved Logins, sign in, change temporary password, sign in again. Test new administrator: Add Login role Admin, open invitation email, set a unique password, then sign in.
7. If an older employee still gets 404, inspect the failing Network URL. Auth login, Admin RPC, and `erp-admin-invite` are separate endpoints; an undeployed function or missing SQL is not repairable by a frontend-only fix. Existing employees were not silently reset.

## Verification
- 202/203 automated tests passed; `tests/invoice-email.test.js` was blocked by missing local TypeScript dependency.
- JSX, JavaScript and Edge Function TypeScript passed syntax parsing.
- Full Vite build, browser sign-in, live Supabase Auth, invitation email delivery, and ERP RPCs were **not** verified in this environment.
- No new SQL migrations.
