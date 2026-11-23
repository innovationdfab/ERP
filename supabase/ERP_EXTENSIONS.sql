-- Run after ERP_WORKSPACE_INTEGRITY.sql. Safe to reapply on an existing workspace.
begin;
insert into public.erp_admin_page_catalog(page,module_group,columns,fields,statuses,default_next) values
 ('Reorder Planning','ERP Extensions','["Product","Minimum","Target","Vendor","Lead days"]','[]','[]',null),
 ('Receivables Ageing','ERP Extensions','["Invoice","Customer","Currency","Due date","Balance"]','[]','[]',null),
 ('Collection Follow-ups','ERP Extensions','["Invoice","Next date","Owner","Method","Status","Note"]','[]','[]',null),
 ('Customer Statements','ERP Extensions','["Customer","Invoice","Currency","Received","Credits","Balance"]','[]','[]',null)
on conflict(page) do nothing;
insert into public.erp_admin_storage_map(storage_key,page,record_key_index,status_index) values
 ('dfab-erp-reorder-policies-v1','Reorder Planning',0,-1),
 ('dfab-erp-collection-followups-v1','Collection Follow-ups',0,-1)
on conflict(storage_key) do nothing;

create or replace function public.erp_extensions_validate_payload()
returns trigger language plpgsql security definer set search_path=public as $$
declare r jsonb;old_record jsonb;products jsonb;vendors jsonb;invoices jsonb;page_name text;invoice_status text;
begin
 if new.storage_key not in ('dfab-erp-reorder-policies-v1','dfab-erp-collection-followups-v1') then return new;end if;
 page_name:=case new.storage_key when 'dfab-erp-reorder-policies-v1' then 'Reorder Planning' else 'Collection Follow-ups' end;
 if not public.erp_admin_can_page(page_name,'view') then raise exception 'View permission required on %',page_name using errcode='42501';end if;
 if jsonb_typeof(new.payload) is distinct from 'array' then raise exception 'Extension records must be an array' using errcode='22023';end if;
 if jsonb_array_length(new.payload)>10000 then raise exception 'At most 10000 extension records are supported';end if;
 if exists(select 1 from jsonb_array_elements(new.payload) value where jsonb_typeof(value)<>'object'
   or nullif(btrim(value->>'id'),'') is null or length(value->>'id')>160)
   or (select count(*) from jsonb_array_elements(new.payload)) <>
      (select count(distinct lower(btrim(value->>'id'))) from jsonb_array_elements(new.payload)) then
   raise exception 'Extension records need unique nonempty IDs' using errcode='22023';end if;
 if new.storage_key='dfab-erp-reorder-policies-v1' then
   select payload into products from public.erp_ui_state where organization_id=new.organization_id and storage_key='dfab-erp-products-v3';
   select payload into vendors from public.erp_ui_state where organization_id=new.organization_id and storage_key='dfab-erp-vendors-v2';
 else
   select payload into invoices from public.erp_ui_state where organization_id=new.organization_id and storage_key='dfab-erp-sales-invoices-v2';
 end if;
 for r in select value from jsonb_array_elements(new.payload) loop
   old_record:=null;
   if tg_op='UPDATE' then
     select value into old_record from jsonb_array_elements(old.payload) value where value->>'id'=r->>'id';
     if old_record is not distinct from r then continue;end if;
   end if;
   if new.storage_key='dfab-erp-reorder-policies-v1' then
     if not public.erp_admin_can_page('Products','view') or not public.erp_admin_can_page('Vendors','view') then
       raise exception 'Product and vendor view access is required' using errcode='42501';end if;
     if not exists(select 1 from jsonb_array_elements(coalesce(products,'[]')) value where value->>0=r->>'id' and value->>6='ACTIVE')
       or not exists(select 1 from jsonb_array_elements(coalesce(vendors,'[]')) value where value->>0=r->>'vendor' and value->>8='ACTIVE') then
       raise exception 'Select an active product and vendor' using errcode='22023';end if;
     if jsonb_typeof(r->'minimum') is distinct from 'number' or jsonb_typeof(r->'target') is distinct from 'number'
       or jsonb_typeof(r->'leadDays') is distinct from 'number' or jsonb_typeof(r->'enabled') is distinct from 'boolean' then
       raise exception 'Invalid reorder policy types' using errcode='22023';end if;
     if (r->>'minimum')::numeric<0 or (r->>'target')::numeric<=(r->>'minimum')::numeric
       or (r->>'leadDays')::numeric<0 or (r->>'leadDays')::numeric>365 or mod((r->>'leadDays')::numeric,1)<>0 then
       raise exception 'Invalid reorder threshold, target or lead time' using errcode='22023';end if;
   else
     if not public.erp_admin_can_page('Sales Invoice','view') then raise exception 'Invoice view permission required' using errcode='42501';end if;
     select value->>6 into invoice_status from jsonb_array_elements(coalesce(invoices,'[]')) value where value->>1=r->>'invoice';
     if invoice_status is distinct from 'APPROVED' then raise exception 'Follow-up requires an approved invoice' using errcode='22023';end if;
     if nullif(btrim(r->>'owner'),'') is null or length(r->>'owner')>120
       or nullif(btrim(r->>'note'),'') is null or length(r->>'note')>2000
       or coalesce(r->>'channel','') not in ('Phone','Email','Meeting','Other')
       or coalesce(r->>'status','') not in ('Open','Done')
       or coalesce(r->>'nextDate','') !~ '^\d{4}-\d{2}-\d{2}$' then
       raise exception 'Complete the follow-up date, owner, method, status and note' using errcode='22023';end if;
     perform (r->>'nextDate')::date;
     if old_record is not null and old_record->>'invoice' is distinct from r->>'invoice' then
       raise exception 'The invoice on an existing follow-up cannot be changed' using errcode='22023';end if;
   end if;
 end loop;
 return new;
end; $$;
revoke all on function public.erp_extensions_validate_payload() from public;
drop trigger if exists erp_extensions_validate on public.erp_ui_state;
create trigger erp_extensions_validate before insert or update of payload on public.erp_ui_state
for each row execute function public.erp_extensions_validate_payload();
commit;
