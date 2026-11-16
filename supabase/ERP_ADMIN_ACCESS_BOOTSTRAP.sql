-- OPTIONAL, ONE-TIME ADMIN RECOVERY. USE ONLY THROUGH SUPABASE SQL EDITOR
-- WITH A DATABASE OWNER AND AN APPROVED, ALREADY-REGISTERED EMAIL.
-- Never run the original production bootstrap again to restore admin privileges;
-- that bootstrap once assigned ADMIN to every historical user.
-- This cannot create an unauthenticated administrator and must not be exposed to the browser.
begin;
do $$
declare
  v_email text := 'REPLACE_WITH_APPROVED_ADMIN_EMAIL';
  v_org uuid;
  v_user uuid;
  v_role uuid;
begin
  if v_email='REPLACE_WITH_APPROVED_ADMIN_EMAIL' or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+[.][^@[:space:]]+$' then
    raise exception 'Set the trusted admin email inside this script before running';
  end if;
  select id into strict v_org from public.erp_organizations where code='DFAB';
  select id into strict v_user from auth.users where lower(email)=lower(v_email);
  if not exists(select 1 from public.erp_profiles where user_id=v_user and organization_id=v_org) then
    raise exception 'Selected user is not a member of the DFAB organization';
  end if;
  select id into strict v_role from public.erp_roles
  where organization_id=v_org and code='ADMIN' and system_role=true;
  update public.erp_profiles set active=true where user_id=v_user and organization_id=v_org;
  insert into public.erp_role_permissions(role_id,permission_code)
   select v_role,code from public.erp_permissions
   where code in ('ERP.VIEW','ERP.CREATE','ERP.EDIT','ERP.DELETE','ERP.APPROVE','ERP.EXPORT','SYSTEM.ADMIN')
   on conflict do nothing;
  insert into public.erp_user_roles(user_id,role_id) values (v_user,v_role) on conflict do nothing;
  insert into public.erp_admin_events(organization_id,actor_id,event,target,details)
   values(v_org,null,'ADMIN_ACCESS_RECOVERY',v_user::text,
   jsonb_build_object('procedure','manual database-owner recovery','email',lower(v_email)));
end $$;
commit;
