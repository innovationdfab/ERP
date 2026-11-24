# DFAB OneERP — Admin Operations v2 (controlled update)

## What changed

Built upon `DFAB-OneERP-Admin-Preview-Safe`, with existing business screens and their logic preserved. Adds a **visible Admin Control Center entry from the login screen**. This unauthenticated view is read-only and shows only generic admin areas on a deployed site, never employee names, organization data, credentials, roles or saved workflow records. On localhost developers can still browse the static workflow catalog without logging in.

An **Admin Control** button is always shown in the signed-in ERP sidebar. Non-admin employees see a read-only explanation; logged-in users with an active administrator role can manage the live panel without a second sign-in. SQL enforces the privilege boundary regardless of the frontend UI.

The live panel supports:

- Workflow map, edit/clone draft, validate fields and gates, publish, reset and **delete draft template** (CAS/version checked).
- Add/edit/deactivate/delete **departments**; deletion refused if a user or foreign-key record still depends on the department.
- Add/edit/deactivate/delete **roles**, module-by-module View/Create/Edit/Delete/Approve/Export. Protected system roles and assigned roles cannot be deleted.
- Invite users via Supabase Auth Edge Function; assign department and roles; manage access; **disable users** and revoke active ERP role assignments while preserving financial/audit history. Re-enabling requires restoring authorized roles. Do not delete Auth identities merely to revoke ERP access.
- View/add/edit/remove **storage section ownership**. Removal prohibited while any ERP data exists in that section.
- View database-backed administrative **audit events**, including deletion events.
- Confirmation popups use the existing **in-app dialogs**, not browser confirm()/alert().

## SQL execution order — staging first

Prepare a restorable database snapshot and verify there are at least two authorized administrators. Do not rerun the original production bootstrap on a live project; it grants ADMIN broadly to existing profiles. For a fresh staging project only, run these in order:

1. `supabase/DFAB_ERP_PRODUCTION.sql` — **only on a clean/new project**.
2. `supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql`.
3. `supabase/ERP_PRODUCTION_GUARDRAILS.sql`.
4. `supabase/ERP_ADMIN_CONTROL.sql`.
5. `supabase/ERP_ADMIN_OPERATIONS_V2.sql` — **new, additive**.
6. `supabase/ERP_ADMIN_CONTROL_STAGING_CHECKS.sql` and `supabase/ERP_ADMIN_OPERATIONS_V2_CHECKS.sql` — read-only diagnostics.

For an existing Supabase project, inspect the applied migrations and run only the **missing** scripts in dependency order. Every database SQL file changes real schema or access; test under staging first.

If no approved administrator can sign in, a database owner may deliberately edit and execute `supabase/ERP_ADMIN_ACCESS_BOOTSTRAP.sql` once. It promotes only the explicitly selected existing DFAB Auth account and records the emergency action. **Do not run it with the placeholder email** or give it to frontend users.

Deploy the supplied Edge Function `supabase/functions/erp-admin-invite` with JWT verification enabled, correct origin allowlist and server-only service role secret. Public account self-registration should be disabled by organization policy. Configure `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` only in frontend env.

## Mandatory manual acceptance tests

1. Signed-out website: Admin entry opens the public capabilities section; no Supabase requests to admin dashboard are made; no editing controls or sensitive rows shown.
2. Signed-in nonadmin employee: Admin button opens read-only screen; directly invoking each admin RPC with the employee JWT fails with a permission error.
3. Signed-in admin: Invite staff, activate/deactivate, assign department and role, sign in as staff and verify permitted actions; check disabled user loses all data access even with a cached JWT.
4. Draft workflow: create/edit/save/refresh, delete draft, attempt to delete published (denied), publish test workflow, verify linked handoff, reset to built-in workflow.
5. Try deleting a department with employees and a role assigned to an employee; both must fail with a meaningful in-app error. Deletion of unused records must survive page reload and produce an audit event.
6. Unmap an empty section successfully; attempt to unmap a section containing business data (denied).
7. Two tabs editing same draft: stale deletion blocked on version mismatch.
8. Verify the preexisting Sales/Purchase/Production/Quality/Finance flows still work, and stock/invoice numbers remain unchanged. Confirm old users keep existing access until deliberately changed.
9. Inspect network errors and PostgREST schema-cache refresh after each migration; run full build, lint, tests and browser smoke with dependencies installed.

## Current verification boundary

Offline unit/source-contract tests and syntax parsing are not enough to establish production readiness. This workspace is not connected to the company's real Supabase project. No live database changes or tenant permission tests have been performed. A production build also depends on installing the repository dependencies successfully. The release must not be labeled error-free until the staged SQL migration, authenticated CRUD, concurrency, browser regressions and recovery drill pass.

## Preserved

All preexisting Home, sidebar layout, Sales, Purchase, Job Work, Inventory, Production, QC, Accounts, reports, login session logic, UI styling outside the Admin section, and legacy data migration source remain unchanged. No company data is deleted by code packaging or SQL preparation.
