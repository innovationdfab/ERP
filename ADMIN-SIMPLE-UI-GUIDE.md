# DFAB OneERP — Simple Admin User Guide

The **Admin Control** button now opens on **Home**. From there you can open these pages:

1. **Employees** — Invite an employee, select their department and role, save their access, or disable their account.
2. **Departments** — Add or edit a department. You can delete only if no users or business records depend on it.
3. **Permissions** — Create a role, select its allowed modules/actions, and save. Assign the role to an employee from Employees.
4. **Document flows** — View the active connections. To change them, create a draft, edit connections, save, and publish. Advanced status/auto-fill settings remain collapsed until opened.
5. **Activity** — Review administrator changes and the people who made them.
6. **Advanced** — Configure storage ownership. Only technical administrators should use this page.

## Security

The Admin Control button on the login screen is a **read-only tour**, not a second unrestricted administrator login. It shows no real employee records or authenticated permissions. Database changes always require an authorized administrator session. This is intentional: public write access could compromise all departments.

## What changed

Only the authenticated Admin Control UI, the logged-out preview UI, admin-specific CSS, and the Admin Control default landing tab in `src/main.jsx` were edited. The SQL schema, database RPC contracts, authorization rules, all non-admin ERP screens, workflows and saved data remain unchanged.

## Setup and verification

- Existing Supabase Admin SQL and Edge Function setup is still required for live administrator operations. This UI update introduces no new migration.
- `npm test` covers the ERP logic and the new Admin UI contract checks.
- Run `npm ci && npm run verify` when dependencies and an appropriate Node version are available.
- The live Supabase security/CRUD flow has not been tested in this isolated environment.
