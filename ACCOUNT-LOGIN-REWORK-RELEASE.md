# Admin Account Logins — Scoped update (2026-11-24)

## Scope
Base: DFAB-OneERP-Monika-Login-404-Diagnostic. Only these original files changed:
- `src/admin-control.jsx` — replace legacy Saved Logins form with compact account list and email/role/password form; Edit role/password and Delete action.
- `src/admin-api.js` — authenticated revoke and restore calls to existing Edge Function.
- `src/admin-control.css` — scoped form layout.
- `supabase/functions/erp-admin-invite/index.ts` — create with provided password for any chosen role, verify Auth/profile assignment, explicit password reset, account revoke/restore.

All other original files remain byte-identical. None deleted.

## Behavior
- Add Login: email, single active role, explicit password and confirmation (minimum 12 characters, letters and numbers). No administrator shared/default password and no invitation bypass. Supabase Auth holds password securely; ERP role stored via existing `erp_admin_provision_employee` RPC. Display name is derived from email to meet the legacy ERP profile schema.
- Edit: existing email is immutable; role/access changed through existing `erp_admin_save_user` RPC; password set independently through authenticated Edge Function. Explicit confirmation for reset.
- Delete: revokes ERP access and bans Supabase Auth sign-in, preserving ERP records and audit history. Administrator cannot delete self; database last-admin safeguard remains authoritative. Disabled logins can be restored through Edit.
- “Logins” is a saved-account directory, not a live-online-user tracker.
- Existing accounts are not reset, deleted or migrated by this release.

## Deployment
1. Ensure the existing Admin Control SQL and `ERP_ADMIN_EMPLOYEE_PROVISIONING_REPAIR.sql` are installed. No new SQL is introduced here.
2. Redeploy `supabase/functions/erp-admin-invite/index.ts` in the same Supabase project; keep server-side credentials private and JWT + Admin verification enabled.
3. Configure `ERP_ALLOWED_ORIGINS` for the website origin(s). Redeploy the frontend.
4. In staging, test Add Login with employee role and Administrator role; verify in Authentication > Users and Admin > Logins; verify exact password, Edit role, reset password, revoke and restore. Check that records remain and self-delete/last-admin actions are blocked.

## Verification / limits
- New scoped regression tests: 5/5 passed.
- Original full test run before final cleanup: 194 passed, 12 legacy tests failed because they assert the now-retired invitation/3-step form/default-password behavior, and 1 existing invoice-email test failed due to missing local TypeScript package.
- Syntax parsing: modified JSX and TypeScript parse successfully using installed global TypeScript. `src/admin-api.js` checked with Node.
- Full Vite build, lint and live Supabase integration: not verified here. Do not claim production-ready without live integration testing.
