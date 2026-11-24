# Employee login 404 — scoped diagnostic fix

Base: `DFAB-OneERP-Admin-Fixed-Supabase-UI` from the immediately preceding delivery.

Changes: `src/main.jsx` (only login catch and stage tracking), `src/login-failure.js`, `tests/login-failure.test.js`.

- Distinguishes successful Supabase Auth authentication from errors loading ERP profile/workflows/data.
- Keeps a verified employee session on post-login database failures; does not misreport a valid password as incorrect.
- Identifies a 404 from a missing PostgREST RPC or a wrong Auth project URL.
- **Does not** skip ERP role checks, grant access to unregistered employees, or change passwords or account data.
- Existing employee records must still have corresponding Supabase Authentication users, active ERP profiles, and assigned roles; the application cannot manufacture these in the browser.

Deployment diagnosis: In DevTools → Network inspect `/auth/v1/token?grant_type=password`, `/rest/v1/rpc/erp_admin_my_access`, `/rest/v1/rpc/erp_admin_active_workflow`, and `/rest/v1/rpc/erp_get_ui_state`. If Auth succeeds but an RPC returns 404/PGRST202, verify the existing SQL migration on the **same Supabase project** and run `NOTIFY pgrst, 'reload schema';` in SQL Editor. No new SQL was added by this UI/auth diagnostic fix.

To validate live credentials, use a test employee and verify Authentication → Users contains the same email as Admin → Saved logins. A profile row alone is not a password login.
