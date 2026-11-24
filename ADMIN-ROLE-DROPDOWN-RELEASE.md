# Admin Login Role Dropdown — scoped release

## Cause
The Admin Login role dropdown already uses the server-returned `erp_admin_dashboard().roles`. The base production SQL creates only the system `ADMIN` role. The existing Admin Control migration seeds departments, not roles. Thus an ERP database with only the ADMIN role cannot offer Sales, Stores, Production, etc. as selectable roles.

## Change
- Additive SQL: `supabase/ERP_ADMIN_DEPARTMENT_ROLES_SAFE.sql`. Inserts missing DFAB department roles, adds ERP.VIEW/ERP.EDIT permissions needed by the legacy sign-in/persistence checks and scoped page rights. It **does not modify existing roles**, overwrite previously configured rights, create/reset passwords or elevate anyone to Administrator. No deletion, approval, export or SYSTEM.ADMIN privileges are granted automatically.
- Admin Login dropdown continues reading the actual organization role directory; displays selected role's currently configured rights and explains the one-role case.
- Existing Roles & permissions page remains the source of truth for modifying module-level View/Add/Edit/Delete/Approve/Export rights.
- No login, business module, workflow or shared API files changed.

## Deployment
1. Back up your Supabase database and test on staging first.
2. In the exact Supabase project used by this ERP, execute the single new SQL file in SQL Editor. The preceding `ERP_ADMIN_CONTROL.sql` must already be installed.
3. Refresh Admin > Logins. Department roles appear as choices. In Admin > Roles & permissions, customize and save permissions for each role, especially roles showing **0 accessible modules**.
4. Select one department role for a new account, set its individual password, create it, and verify both Supabase Auth and ERP role linkage. Users must sign out/back in after role changes.
5. Existing employee roles/permissions and Auth credentials remain untouched.

## Security considerations
- The new roles do not have Administrator access. A departmental role gets initial create/edit access only to matched module pages; approval/delete/export remains off. Review before production use.
- An existing role is never overwritten even if it has no module permissions.
- Server-side access enforcement remains the existing `erp_admin_my_access` / `erp_admin_can_page` RPC and RLS layer. The frontend dropdown does not grant any rights on its own.
- The `erp_admin_save_role` RPC may update global legacy permissions when an Admin explicitly saves role edits; that existing behavior is unchanged in this release.
