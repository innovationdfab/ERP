-- DFAB ERP read-only staging verification. Execute after ERP_ADMIN_CONTROL.sql.
-- Does not change user assignments, tables, roles or business records.
select 'tables' as category, table_name as object_name from information_schema.tables
where table_schema='public' and table_name like 'erp_admin_%' order by table_name;
select 'functions' as category, routine_name as object_name from information_schema.routines
where routine_schema='public' and routine_name like 'erp_admin_%' order by routine_name;
select count(*) as registered_pages from public.erp_admin_page_catalog;
select count(*) as mapped_sections from public.erp_admin_storage_map;
select code, name, active from public.erp_departments where organization_id=(select id from public.erp_organizations where code='DFAB') order by code;
-- Review all ADMIN members; the original bootstrap assigned everyone ADMIN.
select p.display_name,p.email,p.active from public.erp_profiles p
join public.erp_user_roles ur on ur.user_id=p.user_id
join public.erp_roles r on r.id=ur.role_id and r.code='ADMIN'
where p.organization_id=(select id from public.erp_organizations where code='DFAB') order by p.email;
-- Ensure exactly zero or one published templates per organization.
select organization_id,count(*) filter(where status='published') as live_templates from public.erp_admin_flow_templates group by 1;
-- Verify the service role is not accidentally granted to anonymous users. RPCs are run as authenticated users with specific grants.
select 'admin_dashboard_anon' as check_name,has_function_privilege('anon','public.erp_admin_dashboard()','EXECUTE') as anon_can_execute;
select 'admin_dashboard_authenticated' as check_name,has_function_privilege('authenticated','public.erp_admin_dashboard()','EXECUTE') as authorized_can_call;
-- For RLS checks, test as an actual JWT-authenticated staff user. SQL editor uses elevated privileges and does not prove RLS isolation.
