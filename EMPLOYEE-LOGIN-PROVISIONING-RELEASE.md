# Employee login provisioning: scoped verification update

Base: DFAB-OneERP-Saved-Employee-Login-Fix.zip.

Changed existing application files:
- `src/main.jsx`: clarify 404 when a new employee has authenticated and is attempting the required first-login password setup.
- `supabase/functions/erp-admin-invite/index.ts`: perform a read-after-write check that the new account exists in Supabase Auth and has an active ERP profile with every requested role before responding with verified creation. No automatic retry or destructive rollback on ambiguous read-back failures.

All other original application files are unchanged.

## Existing employee such as Monika
1. Verify the exact email in Supabase Authentication > Users and Admin > Saved logins matches.
2. Open the existing login in Admin and reset a non-admin employee password if needed. Never create another identity with the same email.
3. On first sign-in, a temporary password requires personal password replacement through `erp-admin-invite`. A 404 on this step means that function is absent from the **same project configured in VITE_SUPABASE_URL**, or the route is not deployed. Redeploy the included function, with valid origins and JWT verification, without changing existing data.
4. If the 404 is from `/rest/v1/rpc/...`, repair the named database function instead. Capture the failed request in browser DevTools > Network to distinguish these cases.

## Deployment
- Frontend: deploy updated app as usual, using existing Vite Supabase environment variables.
- Edge Function: redeploy `supabase/functions/erp-admin-invite/index.ts` to the exact Supabase project the frontend uses.
- No new SQL migration.
- Do not expose the service-role key in browser env.

## Limitations
The live Monika account and live Supabase endpoints were not accessible for verification here. This update improves creation verification and first-login diagnostics; it cannot claim the actual Monika 404 is resolved without observing which request returns 404.
