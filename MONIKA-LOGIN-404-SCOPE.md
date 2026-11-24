# Employee login 404 – isolated diagnostic release

The source paths are: Admin Add Login -> Edge Function `erp-admin-invite` -> Supabase `auth.users` + ERP `erp_profiles`, `erp_user_roles`; login -> `/auth/v1/token` -> `/auth/v1/user` -> optionally `/functions/v1/erp-admin-invite` for first password change -> `/rest/v1/rpc/erp_admin_my_access` -> `/rest/v1/rpc/erp_get_ui_state`.

## Why Monika can differ
A new non-admin user gets `app_metadata.erp_initial_password_pending=true`, so the first successful sign-in opens password setup. Existing accounts may skip this step. If password setup calls an undeployed or outdated Edge Function, credentials can be valid while that action fails. Other possible causes: mismatched Auth/profile UUID, inactive ERP profile/roles, or unavailable ERP RPC. The live failure was not reproduced.

Run `supabase/ERP_LOGIN_404_READ_ONLY_DIAGNOSTIC.sql` after replacing the placeholder email. It only reads account existence and flags; does not expose password hashes or reset users. Then inspect the browser Network tab for the failed 404 request path. For a missing Edge Function, deploy the project's exact `supabase/functions/erp-admin-invite/index.ts` to the same Supabase project. For a missing RPC, repair only that SQL function.

Only `src/main.jsx`, `src/login-failure.js`, and `src/backend/supabase-rest.js` were changed for precise errors. No other app code, database objects, auth accounts, or passwords were modified.
