-- DFAB OneERP / temporary-login enforcement — EXISTING DATABASE ADDITIVE UPGRADE
-- Apply only after ERP_ADMIN_CONTROL.sql. Run in staging and test with a pilot employee first.
-- Does NOT create accounts, change user passwords, assign roles, alter records or reset data.
-- IMPORTANT: a password set by the server-managed Auth function carries the trusted
-- app_metadata.erp_initial_password_pending claim. The temporary Auth JWT cannot
-- access ERP organization data until the employee replaces the password and signs in again.
BEGIN;
CREATE OR REPLACE FUNCTION public.erp_current_org_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT p.organization_id
  FROM public.erp_profiles p
  WHERE p.user_id=auth.uid()
    AND p.active=true
    AND COALESCE(auth.jwt()->'app_metadata'->>'erp_initial_password_pending','false') <> 'true'
  LIMIT 1;
$$;
-- The existing ERP_ADMIN_CONTROL.sql implementation checks the organization
-- returned above. This additionally protects the base schema's ERP.VIEW helper.
CREATE OR REPLACE FUNCTION public.erp_has_permission(p_permission text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT public.erp_current_org_id() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.erp_user_roles ur
    JOIN public.erp_roles r ON r.id=ur.role_id AND r.active
    JOIN public.erp_role_permissions rp ON rp.role_id=r.id
    JOIN public.erp_profiles p ON p.user_id=ur.user_id AND p.active
      AND p.organization_id=r.organization_id
    WHERE ur.user_id=auth.uid()
      AND r.organization_id=public.erp_current_org_id()
      AND rp.permission_code=p_permission
  );
$$;
COMMIT;
NOTIFY pgrst, 'reload schema';
