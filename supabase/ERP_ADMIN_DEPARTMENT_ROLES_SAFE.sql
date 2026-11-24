-- DFAB OneERP: one-time, additive Admin departmental roles bootstrap.
-- Run ONLY on the existing DFAB Supabase project AFTER ERP_ADMIN_CONTROL.sql.
-- Existing users, existing roles, and ALL existing custom role permissions are preserved.
-- This does not alter Auth users or passwords and does not grant SYSTEM.ADMIN.
-- Review the created permissions in Admin > Roles & permissions before assigning staff.
BEGIN;

DO $$
BEGIN
  IF to_regclass('public.erp_roles') IS NULL
     OR to_regclass('public.erp_departments') IS NULL
     OR to_regclass('public.erp_admin_page_catalog') IS NULL
     OR to_regclass('public.erp_admin_module_rights') IS NULL
     OR to_regclass('public.erp_role_permissions') IS NULL THEN
    RAISE EXCEPTION 'ERP Admin prerequisite tables are missing; apply the existing Admin Control migration first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.erp_organizations WHERE code='DFAB') THEN
    RAISE EXCEPTION 'DFAB organization is missing. This safe migration does not create organizations.';
  END IF;
END $$;

-- Track ONLY roles inserted by this migration. Existing role settings will never
-- be overwritten, including when this script is safely rerun.
CREATE TEMP TABLE _erp_new_department_roles (
  id uuid PRIMARY KEY,
  code text NOT NULL
) ON COMMIT DROP;

WITH created AS (
  INSERT INTO public.erp_roles(organization_id, code, name, description, system_role, active)
  SELECT d.organization_id, d.code, d.name || ' Team',
         'Department-based access. Review module rights in Admin > Roles & permissions.',
         false, true
  FROM public.erp_departments d
  JOIN public.erp_organizations o ON o.id=d.organization_id AND o.code='DFAB'
  WHERE d.code IN ('RND','SALES','MARKETING','PURCHASE','STORES','PRODUCTION',
                   'QUALITY','OUTSOURCING','ACCOUNTS','NPD','PLANNING')
    AND d.active
  ON CONFLICT (organization_id,code) DO NOTHING
  RETURNING id,code
)
INSERT INTO _erp_new_department_roles(id,code)
SELECT id,code FROM created;

-- ERP.VIEW is required for successful non-admin sign-in. ERP.EDIT is used by
-- the existing guarded ERP persistence layer; it does not bypass page rights.
-- In particular, SYSTEM.ADMIN is never inserted for departmental roles.
INSERT INTO public.erp_role_permissions(role_id,permission_code)
SELECT r.id, perm.code
FROM _erp_new_department_roles r
JOIN public.erp_permissions perm ON perm.code IN ('ERP.VIEW','ERP.EDIT')
ON CONFLICT (role_id,permission_code) DO NOTHING;

-- Scoped initial rights: view/create/edit only for the role's matching modules.
-- Approval, deletion and export are NOT granted automatically. They can be
-- reviewed and explicitly enabled in Admin > Roles & permissions.
INSERT INTO public.erp_admin_module_rights
  (role_id,page,can_view,can_create,can_edit,can_delete,can_approve,can_export)
SELECT r.id,c.page,true,true,true,false,false,false
FROM _erp_new_department_roles r
JOIN public.erp_admin_page_catalog c ON c.active
WHERE (r.code='SALES' AND c.module_group='Sales')
   OR (r.code='PURCHASE' AND c.module_group='Purchase')
   OR (r.code='STORES' AND c.module_group='Stores')
   OR (r.code='PRODUCTION' AND c.module_group='Production')
   OR (r.code='QUALITY' AND c.module_group='Quality')
   OR (r.code='PLANNING' AND c.module_group='Planning')
   OR (r.code='OUTSOURCING' AND c.page ~* 'outsource|job[ -]?work')
   OR (r.code='MARKETING' AND c.page IN ('CRM Pipeline','Sales Enquiries'))
   OR (r.code='ACCOUNTS' AND c.page ~* 'invoice|payments|credit note|debit note|ledger|journal|bank')
   OR (r.code='NPD' AND c.page ~* 'new product|product development|production bom')
   OR (r.code='RND' AND c.page ~* 'research|innovation|new product')
ON CONFLICT (role_id,page) DO NOTHING;

-- Results: a role may legitimately have zero page rights when its department
-- has no matching registered screens; configure that role in Admin first.
SELECT r.code, r.name, r.active,
       COUNT(m.page) FILTER (WHERE m.can_view) AS viewable_pages,
       COUNT(m.page) FILTER (WHERE m.can_create) AS creatable_pages,
       COUNT(m.page) FILTER (WHERE m.can_approve) AS approvable_pages
FROM public.erp_roles r
JOIN public.erp_organizations o ON o.id=r.organization_id AND o.code='DFAB'
LEFT JOIN public.erp_admin_module_rights m ON m.role_id=r.id
GROUP BY r.id,r.code,r.name,r.active
ORDER BY r.code;
COMMIT;

-- After running, refresh ERP Admin. If the API schema cache is stale, run:
-- NOTIFY pgrst, 'reload schema';
