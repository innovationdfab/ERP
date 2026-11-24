-- DFAB OneERP: Admin-only employee provisioning repair (additive, non-destructive)
-- Run once in the SAME Supabase project as your ERP and erp-admin-invite Edge Function.
-- Prerequisite: ERP_ADMIN_CONTROL.sql already installed. No existing rows are deleted.
-- This migration does not create auth.users: only the secured Edge Function does that.
begin;

DO $$
BEGIN
  IF to_regclass('public.erp_profiles') IS NULL
     OR to_regclass('public.erp_roles') IS NULL
     OR to_regclass('public.erp_departments') IS NULL
     OR to_regclass('public.erp_user_roles') IS NULL
     OR to_regprocedure('public.erp_admin_save_user(uuid,uuid,text,boolean,uuid[])') IS NULL
     OR to_regprocedure('public.erp_admin_is_admin()') IS NULL THEN
    RAISE EXCEPTION 'ERP Admin prerequisite missing. Install the existing ERP Admin Control SQL before this repair; no changes were applied.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.erp_admin_provision_employee(
  p_user_id uuid, p_email text, p_display_name text,
  p_department_id uuid, p_role_ids uuid[]
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
  v_org uuid;
  v_auth_email text;
  v_profile_org uuid;
  v_inserted boolean := false;
BEGIN
  IF NOT public.erp_admin_is_admin() THEN
    RAISE EXCEPTION 'Administrator authorization required' USING ERRCODE='42501';
  END IF;
  v_org := public.erp_current_org_id();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Administrator ERP organization is not configured' USING ERRCODE='42501';
  END IF;
  IF p_user_id IS NULL OR p_email IS NULL OR p_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     OR length(p_email)>254 OR length(trim(coalesce(p_display_name,''))) NOT BETWEEN 2 AND 100
     OR coalesce(cardinality(p_role_ids),0) NOT BETWEEN 1 AND 20 THEN
    RAISE EXCEPTION 'Enter a valid employee name, email and at least one role' USING ERRCODE='22023';
  END IF;
  -- Verify the Auth record actually exists and is the intended email, before linking it.
  SELECT lower(email) INTO v_auth_email FROM auth.users WHERE id=p_user_id;
  IF v_auth_email IS NULL THEN
    RAISE EXCEPTION 'Supabase Auth user was not created; no ERP profile was saved' USING ERRCODE='22023';
  END IF;
  IF v_auth_email<>lower(trim(p_email)) THEN
    RAISE EXCEPTION 'Supabase Auth email does not match employee email' USING ERRCODE='22023';
  END IF;
  -- Serialize concurrent provisioning for the same Auth user. Never move profiles across organizations.
  PERFORM pg_advisory_xact_lock(hashtextextended('erp-provision:'||p_user_id::text,0));
  SELECT organization_id INTO v_profile_org FROM public.erp_profiles WHERE user_id=p_user_id FOR UPDATE;
  IF v_profile_org IS NOT NULL AND v_profile_org<>v_org THEN
    RAISE EXCEPTION 'User already belongs to another ERP organization' USING ERRCODE='42501';
  END IF;
  IF v_profile_org IS NULL THEN
    INSERT INTO public.erp_profiles(user_id,organization_id,display_name,email,active)
    VALUES (p_user_id,v_org,trim(p_display_name),v_auth_email,false)
    ON CONFLICT(user_id) DO NOTHING;
    v_inserted := true;
  END IF;
  -- All role/department validation, last-admin protection and audit logging
  -- are delegated to the EXISTING ERP Admin function (single transaction).
  PERFORM public.erp_admin_save_user(p_user_id,p_department_id,trim(p_display_name),true,p_role_ids);
  RETURN jsonb_build_object('provisioned',true,'user_id',p_user_id,'email',v_auth_email,'profile_created',v_inserted);
END;
$$;

REVOKE ALL ON FUNCTION public.erp_admin_provision_employee(uuid,text,text,uuid,uuid[]) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.erp_admin_provision_employee(uuid,text,text,uuid,uuid[]) TO authenticated;

COMMIT;
NOTIFY pgrst, 'reload schema';
