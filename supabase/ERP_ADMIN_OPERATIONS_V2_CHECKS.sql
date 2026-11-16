-- READ-ONLY admin operations staging checklist. Run after ERP_ADMIN_OPERATIONS_V2.sql.
-- SQL Editor's privileged context cannot prove runtime JWT authorization.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments,
 has_function_privilege('anon',p.oid,'EXECUTE') as anonymous_can_execute,
 has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in
 ('erp_admin_delete_template','erp_admin_delete_department','erp_admin_delete_role','erp_admin_unmap_storage')
order by p.proname;
select count(*) as department_count from public.erp_departments;
select count(*) as role_count from public.erp_roles;
select count(*) as workflow_templates from public.erp_admin_flow_templates;
select count(*) as storage_mappings from public.erp_admin_storage_map;
-- Inspect existing admin bootstrap assignments before company-wide use.
select p.email,p.display_name,p.active from public.erp_profiles p
join public.erp_user_roles ur on ur.user_id=p.user_id
join public.erp_roles r on r.id=ur.role_id
where r.code='ADMIN' and r.active order by p.email;
