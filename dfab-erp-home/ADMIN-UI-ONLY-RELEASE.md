# DFAB OneERP — Admin-only user interface update

## Base and preservation
- Base archive: `DFAB-OneERP-Live-Fixes-Updated (1).zip` (user-supplied).
- Existing application files modified: **only** `src/admin-control.jsx` and `src/admin-control.css`.
- All other original files, including `src/main.jsx`, authentication, Supabase API adapters, production flows, calculations, SQL migrations, Home/dashboard styling and department screens, are unmodified.
- New file: `tests/admin-editor-ux.test.js` (Admin UI regression tests).

## Admin UX changes
- Reworked the existing Admin navigation into readable full-width groups without adding extra sections.
- Add/Edit Employee uses a focused full-width editor with three always-visible steps: employee details, role permissions and login credentials.
- Better labels and required-field markers, phone/tablet layouts, readable role choices, and inline password validation.
- Existing employee list stays accessible via Back to list and Cancel; it no longer crowds the editor.
- Existing employee passwords can be reset using a chosen temporary password or the server-configured initial password, both through the existing protected Supabase Auth function. No passwords are saved in ERP records.
- Bulk password initialization remains available under Advanced inside Employees, to avoid accidental use.
- Department and role editing use the same full-width focused layout; workflow-draft editing expands to use the available workspace.
- In-app validation errors are displayed in the active editor. Existing confirmations, save handlers, permission checks, and audit behavior remain in use.

## Verification completed
- 190/190 Node automated tests passed (including new Admin editor UI checks). The local test environment used a temporary link to an already installed system TypeScript package; no dependencies are bundled in this release.
- Admin/other React JSX syntax: parsed without diagnostics using TypeScript's JSX parser.
- CSS syntax: parsed using tinycss2 without top-level syntax errors.
- ZIP archive integrity and unchanged-file comparison: verified during packaging.

## Not verified in this environment
- Full Vite production build, ESLint and project TypeScript check: dependencies could not be installed (npm installation failed; Vite and ESLint were unavailable, and `vite/client` typings were missing).
- Live Supabase Auth / admin RPC operations and browser click-through testing: no live credentials/session or runnable installed frontend were available.

## Local verification and rollout
1. Extract the project and retain your existing environment configuration.
2. On a Windows machine with Node 24.x, run `npm ci`, `npm run verify`, and `npm run dev`.
3. Sign in with an authorized administrator; open **Admin** from the existing top bar.
4. Test Employees: Add Employee, Edit, Reset Password (individual/server initial), Disable/Re-enable, Cancel and search.
5. Test Departments: Add/Edit/Delete with dependency safeguards; Permissions: Create/Edit; Document Flows: Draft/Save/Publish/Restore; Activity and Data Connections.
6. Confirm newly created users exist in Supabase Auth and assigned department/role records are reflected in the Admin list. Do not deploy until browser and staging database tests pass.

**No SQL changes or migrations are required for this Admin UI-only update.** Existing Admin RPC functions and the `erp-admin-invite` Edge Function must already be configured for live actions.
