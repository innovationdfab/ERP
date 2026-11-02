-- Additive migration. Run AFTER DFAB_ERP_PRODUCTION.sql. No data is deleted.
-- Atomic compatibility writes for transaction header, lines, assignment and lineage.
begin;
create or replace function public.erp_commit_process(p_changes jsonb, p_expected jsonb, p_action text default 'save')
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id(); v_key text; v_current jsonb;
begin
 if auth.uid() is null or v_org is null then raise exception 'Active ERP organization required'; end if;
 if jsonb_typeof(p_changes) is distinct from 'object' or jsonb_typeof(p_expected) is distinct from 'object' then raise exception 'Invalid process payload'; end if;
 if p_action not in ('save','approve','reject','handoff','payment','close','delete') then raise exception 'Invalid process action'; end if;
 if p_action in ('approve','reject','close') and not public.erp_has_permission('ERP.APPROVE') then raise exception 'ERP.APPROVE permission required'; end if;
 if p_action='delete' and not public.erp_has_permission('ERP.DELETE') then raise exception 'ERP.DELETE permission required'; end if;
 if p_action in ('save','handoff','payment') and not (public.erp_has_permission('ERP.CREATE') or public.erp_has_permission('ERP.EDIT')) then raise exception 'ERP.CREATE or ERP.EDIT permission required'; end if;
 if octet_length(p_changes::text)>12000000 then raise exception 'Save is too large. Use fewer or smaller attachments'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text,0));
 for v_key in select jsonb_object_keys(p_changes) loop
  if v_key not like 'dfab-%' or v_key ~* '(session|password|credential)' or not (p_expected ? v_key) then raise exception 'Unsupported process key'; end if;
  select payload into v_current from public.erp_ui_state where organization_id=v_org and storage_key=v_key for update;
  if coalesce(v_current,'null'::jsonb) is distinct from p_expected->v_key then raise exception 'This record changed in another session. Reload before saving'; end if;
 end loop;
 for v_key in select jsonb_object_keys(p_changes) loop
  perform public.erp_put_ui_state(v_key,p_changes->v_key);
 end loop;
end; $$;
revoke all on function public.erp_commit_process(jsonb,jsonb,text) from public, anon;
grant execute on function public.erp_commit_process(jsonb,jsonb,text) to authenticated;
commit;

-- Reserve a document number without replacing an existing compatibility record.
create or replace function public.erp_next_process_no(p_document_type text,p_prefix text,p_financial_year text)
returns text language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id(); v_number text; v_key text; v_index integer; v_used boolean;
begin
 if auth.uid() is null or v_org is null then raise exception 'Active ERP organization required'; end if;
 if not (public.erp_has_permission('ERP.CREATE') or public.erp_has_permission('ERP.EDIT')) then raise exception 'ERP.CREATE or ERP.EDIT permission required'; end if;
 v_key:=case when p_document_type='Sales Invoice' then 'dfab-erp-sales-invoices-v2' else 'dfab-erp-'||p_document_type end;
 v_index:=case when p_document_type='Sales Invoice' then 1 else 0 end;
 for i in 1..10000 loop
  v_number:=public.erp_next_document_no(p_document_type,p_prefix,p_financial_year);
  select exists(select 1 from public.erp_ui_state s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.payload)='array' then s.payload else '[]'::jsonb end) r where s.organization_id=v_org and s.storage_key=v_key and r->>v_index=v_number) into v_used;
  if not v_used then return v_number; end if;
 end loop;
 raise exception 'Number sequence needs reconciliation with existing records';
end; $$;
revoke all on function public.erp_next_process_no(text,text,text) from public,anon;
grant execute on function public.erp_next_process_no(text,text,text) to authenticated;
