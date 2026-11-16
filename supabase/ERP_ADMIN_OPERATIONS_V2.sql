-- DFAB OneERP Admin Control — safe management operations (additive release v2).
-- REQUIRED FIRST: DFAB_ERP_PRODUCTION.sql, ERP_FLOW_INTEGRITY_UPGRADE.sql,
-- ERP_PRODUCTION_GUARDRAILS.sql, ERP_ADMIN_CONTROL.sql (in their documented order).
-- Requires an authenticated organization Administrator. No anonymous write path.
-- Apply to staging and run ERP_ADMIN_OPERATIONS_V2_CHECKS.sql before production.
begin;

create or replace function public.erp_admin_delete_template(p_id uuid,p_expected_version integer)
returns void language plpgsql security definer set search_path=public as $$
declare v_template public.erp_admin_flow_templates%rowtype;
begin
  if not public.erp_admin_is_admin() then
    raise exception 'Administrator required' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(public.erp_current_org_id()::text||':flow-template',0));
  select * into v_template from public.erp_admin_flow_templates
  where id=p_id and organization_id=public.erp_current_org_id() for update;
  if not found then raise exception 'Workflow template not found' using errcode='P0002'; end if;
  if v_template.status<>'draft' then
    raise exception 'Published workflows cannot be deleted. Reset the live flow first' using errcode='42501';
  end if;
  if p_expected_version is distinct from v_template.version then
    raise exception 'Workflow changed in another session. Refresh before deleting' using errcode='40001';
  end if;
  delete from public.erp_admin_flow_templates where id=p_id and organization_id=public.erp_current_org_id();
  perform public.erp_admin_event('TEMPLATE_DELETED',p_id::text,jsonb_build_object('name',v_template.name,'version',v_template.version));
end; $$;

create or replace function public.erp_admin_delete_department(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_department public.erp_departments%rowtype;
begin
  if not public.erp_admin_is_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
  select * into v_department from public.erp_departments
  where id=p_id and organization_id=public.erp_current_org_id() for update;
  if not found then raise exception 'Department not found' using errcode='P0002'; end if;
  if exists(select 1 from public.erp_profiles where department_id=p_id and organization_id=public.erp_current_org_id()) then
    raise exception 'Department has employee records. Reassign employees first, or set the department inactive' using errcode='23503';
  end if;
  begin
    delete from public.erp_departments where id=p_id and organization_id=public.erp_current_org_id();
  exception when foreign_key_violation then
    raise exception 'Department is referenced by ERP records. Deactivate it instead of deleting' using errcode='23503';
  end;
  perform public.erp_admin_event('DEPARTMENT_DELETED',p_id::text,jsonb_build_object('code',v_department.code,'name',v_department.name));
end; $$;

create or replace function public.erp_admin_delete_role(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.erp_roles%rowtype;
begin
  if not public.erp_admin_is_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
  select * into v_role from public.erp_roles
  where id=p_id and organization_id=public.erp_current_org_id() for update;
  if not found then raise exception 'Access role not found' using errcode='P0002'; end if;
  if v_role.system_role or v_role.code='ADMIN' then
    raise exception 'Protected ERP system roles cannot be deleted' using errcode='42501';
  end if;
  if exists(select 1 from public.erp_user_roles where role_id=p_id) then
    raise exception 'Role is assigned to employees. Reassign them before deletion' using errcode='23503';
  end if;
  begin
    delete from public.erp_admin_module_rights where role_id=p_id;
    delete from public.erp_role_permissions where role_id=p_id;
    delete from public.erp_roles where id=p_id and organization_id=public.erp_current_org_id();
  exception when foreign_key_violation then
    raise exception 'Role is referenced by other ERP records; deactivate it instead' using errcode='23503';
  end;
  perform public.erp_admin_event('ROLE_DELETED',p_id::text,jsonb_build_object('code',v_role.code,'name',v_role.name));
end; $$;

create or replace function public.erp_admin_unmap_storage(p_key text)
returns void language plpgsql security definer set search_path=public as $$
declare v_page text;
begin
  if not public.erp_admin_is_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
  if p_key is null or p_key='dfab-workflow-links-v1' then
    raise exception 'Core workflow storage cannot be removed' using errcode='42501';
  end if;
  select page into v_page from public.erp_admin_storage_map where storage_key=p_key for update;
  if v_page is null then raise exception 'Storage mapping not found' using errcode='P0002';end if;
  -- Storage mapping is GLOBAL. Never unmap while *any* organization has data in that section.
  if exists(select 1 from public.erp_ui_state where storage_key=p_key) or
     exists(select 1 from public.erp_ui_records where storage_key=p_key) then
    raise exception 'This section contains ERP data. Re-map it; do not remove its access policy' using errcode='23503';
  end if;
  delete from public.erp_admin_storage_map where storage_key=p_key;
  perform public.erp_admin_event('STORAGE_UNMAPPED',p_key,jsonb_build_object('previous_page',v_page));
end; $$;

-- PostgreSQL grants are explicit: authenticated users can call the functions,
-- but each one re-checks administrator privileges inside the database.
revoke all on function public.erp_admin_delete_template(uuid,integer) from PUBLIC,anon,authenticated;
revoke all on function public.erp_admin_delete_department(uuid) from PUBLIC,anon,authenticated;
revoke all on function public.erp_admin_delete_role(uuid) from PUBLIC,anon,authenticated;
revoke all on function public.erp_admin_unmap_storage(text) from PUBLIC,anon,authenticated;
grant execute on function public.erp_admin_delete_template(uuid,integer),
 public.erp_admin_delete_department(uuid),public.erp_admin_delete_role(uuid),
 public.erp_admin_unmap_storage(text) to authenticated;
commit;
notify pgrst, 'reload schema';
