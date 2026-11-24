# DFAB OneERP — Admin Control Center: Navigation and Logins

## Locked scope

Base: `DFAB-OneERP-Admin-Premium-UX-Locked.zip` (the previous confirmed Admin-UI-only project).

Modified existing project files:
- `src/admin-control.jsx` — Admin-internal navigation and visual feedback; same existing Admin create/edit/save/reset handlers.
- `src/admin-control.css` — responsive Admin-only sidebar, saved-logins and editor styling, in-app animated notices.

Added files:
- `tests/admin-console-navigation-v3.test.js`
- This release note.

**No non-Admin application file, ERP module, existing business flow, auth service, DB migration, or SQL schema is modified.**

## Admin UI

A left Admin control menu has Dashboard and expandable sections:
- Team & Access → Saved logins, Departments, Roles & permissions
- Document Connections → Document flows, Data connections
- Oversight → Activity history, Advanced settings

Saved logins reads the already existing Supabase-backed `erp_admin_dashboard()` employee profiles. It shows whether ERP access is **enabled/disabled**. It **does not claim employees are online**, because the existing admin database endpoint does not report authenticated active browser sessions.

The `Add login` action uses the existing protected `erp-admin-invite` Edge Function with the new account name/email, department, selected role(s), and optional initial password. After successful creation, the existing Admin dashboard re-reads saved profiles and the new account appears in the list. `Edit` shows the same account editor with editable name/department/role/access and password reset actions; email is read-only because changing Auth identities requires a separate verified identity change workflow. Passwords are never written into profile records.

For an Administrator role, the existing protected invitation flow intentionally hides password entry. It **does not assign a company-wide known password to an administrator account**. Non-admin employees can use the server-configured initial password only when deployed on the secure server; they must change it at first login.

Save, Delete, Disable and other confirmations retain the pre-existing ERP in-app dialog mechanism. Saved/error feedback uses the ERP's existing animated in-app operation feedback. Account-creation and password-reset results that do not emit that event show a matching Admin-scoped animated notice, with reduced-motion support and no duplicate save notifications. No browser-native `alert()` or `confirm()` was added.

## Verification

- Automated ERP suite: **194/194 passed**, including new Admin navigation and account-flow tests.
- Admin React JSX parse: **passed**.
- Admin CSS parse: **passed**.
- Scope diff: **exactly two existing application files changed; zero original files deleted**.
- Full Vite build, ESLint and live Supabase CRUD: **not verified**. The environment uses Node 22, while the project declares Node 24, and `npm ci` failed. Run against Node 24 and your staging Supabase project before publishing.

## Required setup / rollout

No new SQL is required by this Admin-only UI change. The existing Admin Control SQL, employee Auth function, `ERP_INITIAL_PASSWORD` (only if used for non-admin initial accounts), and authorized Administrator identity must already be configured. In a staging Supabase project, verify: Add non-admin employee, create Administrator invitation, return to Saved logins, Edit/Save role, disable/enable, temporary-password reset, logout and sign-in. Do not expose service-role keys to the frontend.
