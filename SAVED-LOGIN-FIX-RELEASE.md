# Saved employee login — scoped repair

Base: DFAB-OneERP-Employee-Login-404-Diagnostics-Fix (the latest prior login fix).

## Changes
- src/main.jsx: A signed-in employee with an active server-verified ERP role no longer has login rejected merely because the optional published-workflow RPC is unavailable (404). The built-in ERP document routes remain in effect and the warning is logged.
- tests/login-optional-workflow.test.js: Regression checks for server role checks, direct Supabase email/password authentication, initial-password setup, and nonblocking workflow initialization.

## Locked files
All other pre-existing project files are byte-for-byte unchanged. Supabase role verification and ERP data initialization are still required; no authentication bypass, password duplication, or SQL change was introduced.

## Verification
- Focused login tests: 12/12 passed.
- Complete `npm test`: 199 pass, one invoice-email test fails before running because local TypeScript dependency is missing (ERR_MODULE_NOT_FOUND).
- Production Vite build, browser interactive login and live Supabase account logins were not verified in this environment (Node v22, app requires Node v24).

## Deployment
1. Use Node 24; run npm ci, npm run verify, npm run dev.
2. Confirm that the local `.env` uses the same Supabase project as Admin's saved employee accounts.
3. Ensure each employee exists in Supabase Authentication > Users and has an active ERP role.
4. For new employees with `erp_initial_password_pending`, complete the mandatory password change.
5. If login still shows 404, inspect the Network tab: a missing mandatory `erp_admin_my_access` / ERP data RPC requires installing the existing SQL for that project. A missing optional `erp_admin_active_workflow` no longer blocks login.
