-- Additive workspace audit repair. No transaction rows or employee accounts are rewritten.
begin;

insert into public.erp_admin_storage_map(storage_key,page,record_key_index,status_index) values
 ('dfab-erp-hsn-master','HSN Master',0,-1),
 ('dfab-erp-uoms','UOM',0,-1),
 ('dfab-erp-product-types','Types',0,-1),
 ('dfab-erp-product-categories','Categories',0,-1),
 ('dfab-erp-products-details-v1','Products',0,-1),
 ('dfab-erp-production-bom-v2','Production BOM',0,5),
 ('dfab-erp-bom-details-v1','Production BOM',0,-1),
 ('dfab-erp-route-card-v2','Route Card',0,5),
 ('dfab-erp-route-details-v1','Route Card',0,-1),
 ('dfab-erp-customers-v2-details','Customers',0,-1),
 ('dfab-erp-vendors-v2-details','Vendors',0,-1),
 ('dfab-erp-prospects-v2','Prospects',0,-1),
 ('dfab-erp-prospects-v2-details','Prospects',0,-1),
 ('dfab-erp-seal-uploads','Seal Uploads',0,-1),
 ('dfab-erp-seal-files-v1','Seal Uploads',0,-1),
 ('dfab-live-instruments','Instrument Master',0,-1),
 ('dfab-live-assets','Asset Allocation',0,-1),
 ('dfab-live-asset-allocations','Asset Allocation',0,-1),
 ('dfab-live-department-users','Department Master',0,-1),
 ('dfab-live-kind-attention','Kind Attention',0,-1),
 ('dfab-live-general-task','General Task',0,-1),
 ('dfab-live-remarks','Remark Master',0,-1),
 ('dfab-live-quality-electrodes','Quality Master',0,-1),
 ('dfab-live-quality-materials','Quality Master',0,-1),
 ('dfab-live-quality-wps','Quality Master',0,-1),
 ('dfab-live-subprocesses','Process Master',0,-1),
 ('dfab-workspace-settings','Settings',0,-1),
 ('dfab-system-modules','Modules',0,-1),
 ('dfab-system-masters','Masters',0,-1),
 ('dfab-system-transactions','Transactions',0,-1),
 ('dfab-system-reports','Reports',0,-1),
 ('dfab-system-menu','Menu',0,-1),
 ('dfab-erp-process-price-records-v1','Process Price List',0,-1),
 ('dfab-erp-vendor-price-records-v1','Vendor Price List',0,-1),
 ('dfab-erp-customer-price-records-v1','Customer Price List',0,-1)
on conflict(storage_key) do nothing;

-- Restore status indexes for rows with nonstandard status column labels.
update public.erp_admin_storage_map set status_index=5 where storage_key='dfab-erp-GRN' and page='GRN';
update public.erp_admin_storage_map set status_index=4 where storage_key='dfab-erp-Indent To Order' and page='Indent To Order';
update public.erp_admin_storage_map set status_index=5 where (storage_key,page) in
 (('dfab-erp-production-bom-v2','Production BOM'),('dfab-erp-route-card-v2','Route Card'));
update public.erp_admin_storage_map set status_index=6 where storage_key='dfab-erp-products-v3' and page='Products';
update public.erp_admin_storage_map set status_index=8 where (storage_key,page) in
 (('dfab-erp-customers-v2','Customers'),('dfab-erp-vendors-v2','Vendors'),('dfab-erp-prospects-v2','Prospects'));
update public.erp_admin_page_catalog set statuses='["DRAFT","APPROVAL PENDING","ACTIVE","DEACTIVATED","REJECTED"]'::jsonb
 where page in ('Products','Customers','Vendors','Prospects','Production BOM','Route Card');
update public.erp_admin_page_catalog set statuses='["DRAFT","APPROVAL PENDING","APPROVED","REJECTED"]'::jsonb where page='Sales Invoice';

create or replace function public.erp_admin_can_key(p_storage_key text,p_action text default 'view')
returns boolean language plpgsql stable security definer set search_path=public as $$
declare v_page text;
begin
 if public.erp_admin_is_admin() then return true; end if;
 if p_storage_key='dfab-workflow-links-v1' then
   return public.erp_has_permission(case when p_action='view' then 'ERP.VIEW' else 'ERP.EDIT' end);
 end if;
 select page into v_page from public.erp_admin_storage_map where storage_key=p_storage_key;
 if v_page is null and p_action='view' then
   v_page:=case
    when left(p_storage_key,24)='dfab-live-vendor-prices-' then 'Vendor Price List'
    when left(p_storage_key,26)='dfab-live-customer-prices-' then 'Customer Price List'
    when left(p_storage_key,25)='dfab-live-process-prices-' then 'Process Price List'
   end;
 end if;
 return v_page is not null and public.erp_admin_can_page(v_page,p_action);
end; $$;

-- Stable keys for current custom master formats and older text-only lists.
create or replace function public.erp_workspace_record_key(p_section text,p_record jsonb,p_index integer)
returns text language sql immutable set search_path=public as $$
 select nullif(case jsonb_typeof(p_record)
   when 'array' then p_record->>p_index
   when 'string' then p_record#>>'{}'
   when 'object' then coalesce(nullif(p_record->>'id',''),nullif(p_record->>'code',''),
     case p_section
        when 'dfab-live-department-users' then jsonb_build_array(p_record->>'department',p_record->>'username')::text
        when 'dfab-live-asset-allocations' then jsonb_build_array(p_record->>'asset',p_record->>'to',p_record->>'on')::text
        when 'dfab-live-subprocesses' then jsonb_build_array(p_record->>'parent',p_record->>'name')::text
        when 'dfab-live-quality-wps' then jsonb_build_array(p_record->>'material',p_record->>'name')::text
        when 'dfab-live-quality-electrodes' then jsonb_build_array(p_record->>'material',p_record->>'wps',p_record->>'name')::text
        when 'dfab-live-daily-tasks' then jsonb_build_array(p_record->>'user',p_record->>'task',p_record->>'date')::text
        when 'dfab-live-general-task' then jsonb_build_array(p_record->>'user',p_record->>'task',p_record->>'date')::text
        else coalesce(p_record->>'name',p_record->>'remark')
     end)
   end,'')
$$;
revoke all on function public.erp_workspace_record_key(text,jsonb,integer) from public;

create or replace function public.erp_admin_assert_change(p_key text,p_old jsonb,p_new jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_page text;v_key_index integer;v_status_index integer;v_added boolean:=false;v_removed boolean:=false;
        v_modified boolean:=false;v_approval boolean:=false;v_bad boolean:=false;v_initial text;v_has_pending boolean;v_old_rows jsonb;
begin
 if public.erp_admin_is_admin() then return;end if;
 if p_key='dfab-workflow-links-v1' then
   if current_setting('erp.verified_batch',true) is distinct from '1'
     or not public.erp_has_permission('ERP.EDIT') then
     raise exception 'Workflow links may be edited only as part of a verified connected-document commit' using errcode='42501';
   end if;
   return;
 end if;
 select page,record_key_index,status_index into v_page,v_key_index,v_status_index from public.erp_admin_storage_map where storage_key=p_key;
 if v_page is null then raise exception 'This ERP data section is not mapped to a module. Ask an administrator to map % before editing.',p_key using errcode='42501';end if;
 if p_old is not distinct from p_new then return;end if;
 if p_new is not null and (
    (v_status_index>=0 and (jsonb_typeof(p_new)<>'array'
      or exists(select 1 from jsonb_array_elements(case when jsonb_typeof(p_new)='array' then p_new else '[]'::jsonb end) entry(row) where jsonb_typeof(entry.row)<>'array')))
    or (p_old is not null and jsonb_typeof(p_old)<>jsonb_typeof(p_new))
 ) then raise exception 'Invalid data shape for %',v_page using errcode='22023';end if;
 if v_status_index>=0 then
   select statuses->>0,exists(select 1 from jsonb_array_elements_text(statuses) as status(value)
     where lower(status.value)='approval pending')
     into v_initial,v_has_pending from public.erp_admin_page_catalog where page=v_page;
 end if;
 if v_status_index>=0 and jsonb_typeof(p_new)='array'
    and not public.erp_admin_can_page(v_page,'approve') then
   v_old_rows:=case when jsonb_typeof(p_old)='array' then p_old else '[]'::jsonb end;
   if v_initial is not null and exists(
     select 1 from jsonb_array_elements(p_new) new_record(row)
     where jsonb_typeof(new_record.row)='array'
       and not exists(select 1 from jsonb_array_elements(v_old_rows) old_record(row)
         where old_record.row->>v_key_index=new_record.row->>v_key_index)
       and lower(coalesce(new_record.row->>v_status_index,''))<>lower(v_initial)
       and not (v_has_pending and lower(coalesce(new_record.row->>v_status_index,''))='approval pending')
   ) then raise exception 'New % records must start in % unless you have approval rights',v_page,v_initial using errcode='42501';end if;
 end if;
 if p_old is null then
   if not public.erp_admin_can_page(v_page,'create') then raise exception 'Create permission required on %',v_page using errcode='42501';end if;
   if jsonb_typeof(p_new)='array' then p_old:='[]'::jsonb;
   elsif jsonb_typeof(p_new)='object' then p_old:='{}'::jsonb;
   else return;
   end if;
 end if;
 if p_new is null then
   if not public.erp_admin_can_page(v_page,'delete') then raise exception 'Delete permission required on %',v_page using errcode='42501';end if;
   return;
 end if;
 if jsonb_typeof(p_old)='array' and jsonb_typeof(p_new)='array' then
   -- Arrays must have stable unique reference keys for permission-safe diffing.
   select exists(select 1 from jsonb_array_elements(p_old) r(value) where public.erp_workspace_record_key(p_key,r.value,v_key_index) is null)
     or exists(select 1 from jsonb_array_elements(p_new) r(value) where public.erp_workspace_record_key(p_key,r.value,v_key_index) is null)
     into v_bad;
   if not v_bad then
     select exists(select 1 from (select public.erp_workspace_record_key(p_key,r.value,v_key_index) k from jsonb_array_elements(p_old) r(value) group by 1 having count(*)>1) d)
       or exists(select 1 from (select public.erp_workspace_record_key(p_key,r.value,v_key_index) k from jsonb_array_elements(p_new) r(value) group by 1 having count(*)>1) d)
       into v_bad;
   end if;
   if v_bad then raise exception 'This collection needs unique reference IDs before non-admin editing. Ask an administrator to repair it.' using errcode='23505';end if;
   with old_rows as (select public.erp_workspace_record_key(p_key,r.value,v_key_index) k,r.value val from jsonb_array_elements(p_old) r(value)),
        new_rows as (select public.erp_workspace_record_key(p_key,r.value,v_key_index) k,r.value val from jsonb_array_elements(p_new) r(value)),
        diff as (select o.val oldval,n.val newval from old_rows o full join new_rows n using(k))
   select coalesce(bool_or(oldval is null),false),coalesce(bool_or(newval is null),false),
       coalesce(bool_or(oldval is not null and newval is not null and oldval<>newval),false),
       coalesce(bool_or(v_status_index>=0 and oldval is not null and newval is not null
         and oldval->v_status_index is distinct from newval->v_status_index
         and not (coalesce(v_has_pending,false)
           and lower(coalesce(oldval->>v_status_index,''))=coalesce(lower(v_initial),'')
           and lower(coalesce(newval->>v_status_index,''))='approval pending')),false)
   into v_added,v_removed,v_modified,v_approval from diff;
 elsif jsonb_typeof(p_old)='object' and jsonb_typeof(p_new)='object' then
   with o as (select key,val from jsonb_each(p_old) as p(key,val)),
        n as (select key,val from jsonb_each(p_new) as p(key,val)),
        diff as (select o.val oldval,n.val newval from o full join n using(key))
   select coalesce(bool_or(oldval is null),false),coalesce(bool_or(newval is null),false),
      coalesce(bool_or(oldval is not null and newval is not null and oldval<>newval),false)
   into v_added,v_removed,v_modified from diff;
 else
   v_modified:=true;
 end if;
 if v_added and not public.erp_admin_can_page(v_page,'create') then raise exception 'Create permission required on %',v_page using errcode='42501';end if;
 if v_removed and not public.erp_admin_can_page(v_page,'delete') then raise exception 'Delete permission required on %',v_page using errcode='42501';end if;
 if v_modified and not public.erp_admin_can_page(v_page,'edit') then raise exception 'Edit permission required on %',v_page using errcode='42501';end if;
 if v_approval and not public.erp_admin_can_page(v_page,'approve') then raise exception 'Status/approval permission required on %',v_page using errcode='42501';end if;
end; $$;

create or replace function public.erp_guard_ui_state_mutation()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_org uuid;v_key text;
begin
 v_org:=case when TG_OP='DELETE' then OLD.organization_id else NEW.organization_id end;
 v_key:=case when TG_OP='DELETE' then OLD.storage_key else NEW.storage_key end;
 if auth.uid() is null or v_org is distinct from public.erp_current_org_id()
   or not public.erp_has_permission('ERP.EDIT') then
   raise exception 'ERP write access denied for this user and organization' using errcode='42501';
 end if;
 if TG_OP='INSERT' then
   -- PostgreSQL fires BEFORE INSERT for an UPSERT even if it later updates.
   -- Let the UPDATE phase check the existing section and the actual row diff.
   if not exists(select 1 from public.erp_ui_state where organization_id=v_org and storage_key=v_key) then
     perform public.erp_admin_assert_change(v_key,null,NEW.payload);
   end if;
   return NEW;
 end if;
 if TG_OP='DELETE' then perform public.erp_admin_assert_change(v_key,OLD.payload,null);return OLD;end if;
 if NEW.organization_id<>OLD.organization_id or NEW.storage_key<>OLD.storage_key then raise exception 'ERP section identity cannot be changed';end if;
 perform public.erp_admin_assert_change(v_key,OLD.payload,NEW.payload);
 return NEW;
end; $$;


create or replace function public.erp_commit_ui_state_batch(p_changes jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_item jsonb;v_key text;v_old jsonb;
 v_expected jsonb;v_new jsonb;v_links_old jsonb;v_links_new jsonb;v_link jsonb;
 v_from text;v_to text;v_reference text;v_created text;v_target_key text;v_target_payload jsonb;
 v_target_old jsonb;v_source_key text;v_source_doc jsonb;v_source_rows jsonb;
 v_source_status text;v_status_idx integer;v_gates text[];v_active_target text;
begin
 if auth.uid() is null or v_org is null or not public.erp_has_permission('ERP.EDIT') then
   raise exception 'ERP session or edit permission is missing' using errcode='42501';end if;
 if jsonb_typeof(p_changes)<>'array' or jsonb_array_length(p_changes) not between 2 and 3 then
   raise exception 'Connected save needs two or three ERP sections';end if;
 if (select count(distinct entry.value->>'key') from jsonb_array_elements(p_changes) as entry(value))<>jsonb_array_length(p_changes) then
   raise exception 'Duplicate workflow section keys';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||':flow',0));
 -- Validate all CAS expectations before any writes.
 for v_item in select value from jsonb_array_elements(p_changes) loop
   v_key:=v_item->>'key';
   if v_key is null or (v_key not like 'dfab-erp-%' and v_key not in ('dfab-workflow-links-v1','dfab-invoice-details-v1'))
       or not (v_item ? 'expected' and v_item ? 'payload') then
     raise exception 'Invalid connected document payload';end if;
   v_expected:=v_item->'expected';v_new:=v_item->'payload';
   if v_new is null or jsonb_typeof(v_new)='null' then raise exception 'Null workflow payload is not allowed';end if;
   perform pg_advisory_xact_lock(hashtextextended(v_org::text||':'||v_key,0));
   select payload into v_old from public.erp_ui_state where organization_id=v_org and storage_key=v_key for update;
   if v_old is distinct from (case when jsonb_typeof(v_expected)='null' then null else v_expected end) then
     raise exception 'ERP section % changed in another session. Reload and retry.',v_key using errcode='40001';end if;
 end loop;
 if exists(select 1 from jsonb_array_elements(p_changes) as entry(value) where entry.value->>'key'='dfab-workflow-links-v1')
    and not public.erp_admin_is_admin() then
   select payload into v_links_old from public.erp_ui_state where organization_id=v_org and storage_key='dfab-workflow-links-v1';
   v_links_old:=coalesce(v_links_old,'[]'::jsonb);
   select entry.value->'payload' into v_links_new from jsonb_array_elements(p_changes) as entry(value) where entry.value->>'key'='dfab-workflow-links-v1';
   if jsonb_typeof(v_links_old)<>'array' or jsonb_typeof(v_links_new)<>'array'
     or jsonb_array_length(v_links_new)<>jsonb_array_length(v_links_old)+1
     or v_links_new - (jsonb_array_length(v_links_new)-1) <> v_links_old then
     raise exception 'Only one appended workflow connection may be saved at a time' using errcode='42501';end if;
   v_link:=v_links_new->(jsonb_array_length(v_links_new)-1);
   v_from:=v_link->>'from';v_to:=v_link->>'to';v_reference:=v_link->>'reference';v_created:=v_link->>'created';
   if nullif(v_from,'') is null or nullif(v_to,'') is null or nullif(v_reference,'') is null or nullif(v_created,'') is null
     or not public.erp_admin_can_page(v_from,'view') or not public.erp_admin_can_page(v_to,'create') then
     raise exception 'Missing source, destination or authorization for workflow link' using errcode='42501';end if;
   if exists(select 1 from jsonb_array_elements(v_links_old) as old_link(value)
       where old_link.value->>'from'=v_from and old_link.value->>'to'=v_to and old_link.value->>'reference'=v_reference) then
     raise exception 'This document has already been linked to the selected next stage';end if;
   select e.target_page,e.gate_statuses into v_active_target,v_gates
   from public.erp_admin_flow_templates t join public.erp_admin_flow_edges e on e.template_id=t.id
   where t.organization_id=v_org and t.status='published' and e.source_page=v_from limit 1;
   if v_active_target is null then
     select default_next into v_active_target from public.erp_admin_page_catalog where page=v_from;
     select default_gate_statuses into v_gates from public.erp_admin_page_catalog where page=v_from;
   end if;
   if v_active_target is distinct from v_to then raise exception 'Workflow link is not allowed by the active process template';end if;
   if coalesce(array_length(v_gates,1),0)=0 then
     select default_gate_statuses into v_gates from public.erp_admin_page_catalog where page=v_from;
   end if;
   v_source_key:=case when v_from='Sales Invoice' then 'dfab-erp-sales-invoices-v2' else 'dfab-erp-'||v_from end;
   select payload into v_source_rows from public.erp_ui_state where organization_id=v_org and storage_key=v_source_key for share;
   if jsonb_typeof(v_source_rows)<>'array' then raise exception 'Source document has not been saved';end if;
   select m.status_index into v_status_idx from public.erp_admin_storage_map m where m.storage_key=v_source_key;
   select source_row.value into v_source_doc from jsonb_array_elements(v_source_rows) as source_row(value)
   where source_row.value->>(case when v_from='Sales Invoice' then 1 else 0 end)=v_reference limit 1;
   if v_source_doc is null then raise exception 'Source reference does not exist in Supabase';end if;
   if coalesce(array_length(v_gates,1),0)>0 and (v_status_idx is null or v_status_idx<0 or
     not (v_source_doc->>v_status_idx = any(v_gates))) then
       raise exception 'Source status does not satisfy the published workflow approval gate';end if;
   v_target_key:=case when v_to='Sales Invoice' then 'dfab-erp-sales-invoices-v2' else 'dfab-erp-'||v_to end;
   select entry.value->'payload' into v_target_payload from jsonb_array_elements(p_changes) as entry(value) where entry.value->>'key'=v_target_key;
   select payload into v_target_old from public.erp_ui_state where organization_id=v_org and storage_key=v_target_key;
   if jsonb_typeof(v_target_payload) is distinct from 'array'
     or v_target_payload - 0 is distinct from coalesce(v_target_old,'[]'::jsonb)
     or v_target_payload->0->>(case when v_to='Sales Invoice' then 1 else 0 end) is distinct from v_created then
     raise exception 'Connected document payload must create exactly the referenced destination record';end if;
 end if;
 -- The trigger will accept shared link writes only during this validated batch.
 perform set_config('erp.verified_batch','1',true);
 for v_item in select value from jsonb_array_elements(p_changes) loop
   v_key:=v_item->>'key';v_new:=v_item->'payload';
   insert into public.erp_ui_state(organization_id,storage_key,payload,updated_by)
   values(v_org,v_key,v_new,auth.uid())
   on conflict(organization_id,storage_key) do update
   set payload=excluded.payload,updated_by=auth.uid(),updated_at=timezone('utc',now());
 end loop;
 perform set_config('erp.verified_batch','0',true);
end; $$;



-- Activity exposes event metadata only, with an organization and module check.
create or replace function public.erp_workspace_activity()
returns table(occurred_at timestamptz,actor text,operation text,reference text,module text)
language plpgsql stable security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();
begin
 if v_org is null or not public.erp_admin_can_page('Activity Log','view') then
   raise exception 'Activity Log access is required' using errcode='42501';
 end if;
 return query
 select a.occurred_at,coalesce(p.display_name,p.email,'System'),a.action,
   coalesce(a.new_data->>'storage_key',a.old_data->>'storage_key',nullif(a.row_id,''),''),
   coalesce(m.page,a.table_name)
 from public.erp_audit_log a
 left join public.erp_profiles p on p.organization_id=v_org and p.user_id=a.user_id
 left join public.erp_admin_storage_map m on m.storage_key=coalesce(a.new_data->>'storage_key',a.old_data->>'storage_key')
 where a.organization_id=v_org
   and (public.erp_admin_is_admin() or (m.page is not null and public.erp_admin_can_page(m.page,'view')))
 order by a.occurred_at desc,a.id desc limit 250;
end;
$$;
revoke all on function public.erp_workspace_activity() from public;
grant execute on function public.erp_workspace_activity() to authenticated;

-- Restore a backup as one administrator-only transaction with conflict checking.
create or replace function public.erp_restore_ui_state(p_changes jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_item jsonb;v_key text;v_previous jsonb;v_expected jsonb;
begin
 if v_org is null or not public.erp_admin_is_admin() then
   raise exception 'Administrator access is required to restore a workspace' using errcode='42501';
 end if;
 if jsonb_typeof(p_changes) is distinct from 'array' or pg_column_size(p_changes)>45000000 then
   raise exception 'Invalid or oversized backup';
 end if;
 if jsonb_array_length(p_changes) not between 1 and 500
    or (select count(distinct value->>'key') from jsonb_array_elements(p_changes))<>jsonb_array_length(p_changes) then
   raise exception 'Backup must contain 1 to 500 distinct ERP sections';
 end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||':flow',0));
 for v_item in select value from jsonb_array_elements(p_changes) order by value->>'key' loop
   v_key:=v_item->>'key';
   if v_key !~ '^dfab-[a-zA-Z0-9 /_.-]+$' or v_key ~* 'session|password|credential|token|secret|private.key'
      or not (v_item ? 'payload' and v_item ? 'expected') then
     raise exception 'Unsupported backup key';
   end if;
   perform pg_advisory_xact_lock(hashtextextended(v_org::text||':'||v_key,0));
   select payload into v_previous from public.erp_ui_state where organization_id=v_org and storage_key=v_key for update;
   v_expected:=nullif(v_item->'expected','null'::jsonb);
   if v_previous is distinct from v_expected then
     raise exception 'ERP section % changed in another session. Reload before restoring.',v_key using errcode='40001';
   end if;
   insert into public.erp_ui_state(organization_id,storage_key,payload,updated_by)
   values(v_org,v_key,v_item->'payload',auth.uid())
   on conflict(organization_id,storage_key) do update
     set payload=excluded.payload,updated_by=excluded.updated_by,updated_at=now();
 end loop;
end;
$$;
revoke all on function public.erp_restore_ui_state(jsonb) from public;
grant execute on function public.erp_restore_ui_state(jsonb) to authenticated;

-- Return per-document audit changes for a selected workspace date with source permissions.
create or replace function public.erp_workspace_transactions(p_day date)
returns table(occurred_at timestamptz,actor text,module text,operation text,reference text,status text)
language plpgsql stable security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();
begin
 if v_org is null or not public.erp_admin_can_page('User Wise Transactions List','view') then
   raise exception 'Transaction report access is required' using errcode='42501';
 end if;
 if p_day is null then raise exception 'Select a transaction date';end if;
 return query
 with events as (
   select a.id,a.occurred_at,a.user_id,a.action,a.old_data,a.new_data,m.storage_key,m.page,m.record_key_index,m.status_index
   from public.erp_audit_log a
   join public.erp_admin_storage_map m on m.storage_key=coalesce(a.new_data->>'storage_key',a.old_data->>'storage_key')
   where a.organization_id=v_org and m.status_index>=0 and public.erp_admin_can_page(m.page,'view')
     and a.occurred_at>=p_day::timestamp at time zone 'Asia/Kolkata'
     and a.occurred_at<(p_day+1)::timestamp at time zone 'Asia/Kolkata'
   order by a.id desc limit 500
 )
 select e.occurred_at,coalesce(p.display_name,p.email,'System'),e.page,
   case when d.previous is null then 'Created' when d.current is null then 'Deleted' else 'Updated' end,
   d.ref,coalesce(d.current,d.previous)->>e.status_index
 from events e
 left join public.erp_profiles p on p.organization_id=v_org and p.user_id=e.user_id
 cross join lateral (
   select coalesce(o.ref,n.ref) ref,o.row previous,n.row current
   from (
     select public.erp_workspace_record_key(e.storage_key,value,e.record_key_index) ref,value row
     from jsonb_array_elements(case when jsonb_typeof(e.old_data->'payload')='array' then e.old_data->'payload' else '[]'::jsonb end)
   ) o full join (
     select public.erp_workspace_record_key(e.storage_key,value,e.record_key_index) ref,value row
     from jsonb_array_elements(case when jsonb_typeof(e.new_data->'payload')='array' then e.new_data->'payload' else '[]'::jsonb end)
   ) n on n.ref=o.ref
   where o.row is distinct from n.row
 ) d
 where d.ref is not null
 order by e.id desc,d.ref limit 500;
end;
$$;
revoke all on function public.erp_workspace_transactions(date) from public;
grant execute on function public.erp_workspace_transactions(date) to authenticated;

commit;
