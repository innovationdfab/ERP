# DFAB OneERP — Admin Control Center deployment and acceptance

## Scope delivered

A single **Admin Control** launch in the existing left navigation (visible only to authenticated administrators) opens six integrated areas:

1. **Connections & templates** — read the built-in document flow map; copy it into a draft, add/remove links, choose approval gates and field auto-fetch mappings; validate and publish. Publishing is explicit and reversible to the original built-in workflow. Existing documents are not migrated or rewritten.
2. **Users & logins** — invite users by secure email, select active company roles, assign departments, enable/disable accounts, view existing roles. Passwords are never generated, displayed or stored in this panel.
3. **Role access** — assign per-page View, Create, Edit, Delete, Approve and Export rights; includes existing reports and custom pages.
4. **Departments** — add/edit departments and cost centres with staff dependency checks.
5. **Database access** — inspect existing UI section → owning module mappings; map additional legacy data sections with explicit admin confirmation.
6. **Audit trail** — review the last 120 administrative changes, with actor and timestamp.

The admin tables and functions are **new** and scoped to the existing DFAB organization. Existing transaction schemas, saved data, logo, Home, navigation and form layouts were not replaced.

## One-time staging rollout (required)

**Do not run in production before staging validation and a restorable database backup.** Confirm the same source version and SQL version are deployed together. Existing users may have broad ADMIN roles from an earlier bootstrap; review and demote excess administrators before department-wide rollout.

1. Back up the entire staging Supabase database. Confirm at least two trusted administrators exist, and their addresses are controlled by DFAB.
2. Use the existing migrations in their original order (skip any already applied to the same environment, after inspecting migration history):

   ```text
   supabase/DFAB_ERP_PRODUCTION.sql
   supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql
   supabase/ERP_PRODUCTION_GUARDRAILS.sql
   supabase/ERP_ADMIN_CONTROL.sql       <-- NEW, run once after the other three
   ```

   `ERP_ADMIN_CONTROL.sql` wraps its changes in one transaction. It creates catalog, role-permission, workflow-template, storage-map and audit tables, reuses the existing profile/role/department tables, and installs permission-checking RPCs and database write protections. Its `INSERT ... ON CONFLICT` seeds do not delete existing business rows. **Do not rerun the original production bootstrap blindly in production**, because that historical file assigns the ADMIN role to all profiles.
3. In Supabase **Auth**, disable public self-signup unless company policy explicitly requires and secures it.
4. Configure the Edge Function environment (server-side, not Vite):

   ```text
   ERP_ALLOWED_ORIGINS=https://your-vercel-domain.example,https://your-custom-domain.example
   ERP_INVITE_EMAIL_DOMAINS=dfab-company-domain.example  # optional; enter real approved domains
   ```

   The Supabase project supplies `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` to the Edge runtime. Never put the service role key in `.env` used by Vite, browser code, Git or this ZIP.
5. Deploy invitation service with JWT verification **enabled** (default):

   ```bash
   supabase functions deploy erp-admin-invite
   ```

6. Frontend environment uses only the existing `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` values. Build the exact ZIP revision and deploy it to staging.
7. Sign in as an authorized admin. Open **Admin Control** from the sidebar. Make a `PRODUCTION` role and a `QUALITY` role with different module access, create each relevant department, and invite a test account.
8. Verify an invited account sets its own password, sees only assigned screens, cannot create without Create permission, cannot change status without Approve permission, and receives a database 403/42501 if it attempts the same operation directly. Check RLS against a second test organization where available.
9. Save a workflow **draft** and confirm the live flow is unchanged. Publish it only after review, refresh the staff session, complete a permitted document handoff, then use **Restore built-in flow** and confirm the original next stage returns.
10. Create/update/delete permitted test records, inspect audit entries, open/refresh, verify records persisted, and test parallel edits from two separate sessions. Confirm the second conflicting save is rejected rather than overwritten.
11. Apply the rollout to production **only** when all staging checks pass. Take another backup, apply the admin SQL, deploy the Edge Function and matching UI, review preexisting ADMIN assignments and notify users of the rollout.

## Critical operating rules

- **Access enforcement lives in PostgreSQL**, not only in hidden buttons. Role access is evaluated for each authenticated request. Additional normalization is recommended before cross-department financial or warehouse posting.
- Changes to roles/templates take effect for active sessions after refresh. Server-side checks use the latest database privileges immediately.
- A template is a single forward-only successor per source module; publishing never performs stock posting or executes historical documents. The existing transaction implementation and status gates still apply.
- Admin catalog entries are not new business screens. Creating a workflow connection never creates an unrelated page.
- Database storage mapping is sensitive; only remap a section when its data shape, record identifier and status column are confirmed.
- Do not remove the last active Administrator. Do not use service-role credentials in the browser.
- The old UI-state JSON compatibility store remains for existing screens. It is **not** equivalent to normalized row-level ledger enforcement for accounting/inventory, and it can contain multi-module legacy data. A security review of those legacy collections remains a prerequisite for broad multi-department production use.

## Automated checks and limitations

- `npm test` tests existing ERP calculations and new role/template/security behaviors.
- `npm run verify` additionally requires installed npm dependencies, and runs ESLint, type checking and Vite production build.
- SQL needs a **real staging Supabase execution** to confirm grants, constraints, RLS, current data and Edge Function behavior. The container does not have the user's Supabase credentials; no live SQL was executed by ChatGPT.
- A release cannot be certified "error-free" based solely on unit tests. Staging end-to-end flows, multi-user/security probes and a successful build are required.

## Review & recovery

- For a bad published workflow: **Admin Control → Connections & templates → Restore built-in flow**. This does not delete data or users.
- For a bad role permission: sign in with a *different authorized admin* and correct the role. Do not use raw database edits unless an emergency runbook and database backup are available.
- For a failed SQL rollout: the admin migration is transactional; inspect the precise error before reattempting in staging. Restore the predeployment backup if later changes have been applied and cannot be safely rolled back. Do not drop production tables as a shortcut.

## Preserved features

All existing Home modules, Sales, Purchase, Production, Quality, Stores, Job Work, finance workflows, i-MANTRA features, styling, logo, responsive navigation and native in-app dialogs are retained from the supplied release-candidate source. Only Admin Control integration and necessary authorization hooks are added.
