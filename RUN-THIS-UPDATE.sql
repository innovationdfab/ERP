-- Existing production-flow installations: apply this one update file.
-- Includes previous audit fixes and cross-source invoice protection.
BEGIN;
-- Additive release update. Apply after ERP_PRODUCTION_FLOWS_UPDATE.sql.
-- Retains all business records, permissions and historical invoice dates.
create or replace function public.erp_validate_invoice_terms()
returns trigger language plpgsql set search_path=public as $$
declare n text; d jsonb; previous jsonb; due text; days text;
begin
 if new.storage_key<>'dfab-process-Sales Invoice' then return new;end if;
 if jsonb_typeof(new.payload)<>'object' then return new;end if;
 for n,d in select * from jsonb_each(new.payload) loop
  previous:=case when tg_op='UPDATE' then old.payload->n else null end;
  if d is not distinct from previous or coalesce((d->>'legacy')::boolean,false) then continue;end if;
  -- Existing pre-update invoices remain usable. A newly entered/edited terms
  -- field activates the new validation; old missing dates are never invented.
  if previous is not null and not (d->'header' ? 'Due Date') and not (previous->'header' ? 'Due Date') then continue;end if;
  days:=coalesce(d->'header'->>'Credit Days','');
  if days<>'' and (days !~ '^[0-9]{1,4}$' or days::numeric>3650) then raise exception 'Credit Days must be a whole number from 0 to 3650';end if;
  if d->>'status' in ('DRAFT','REJECTED') then continue;end if;
  due:=coalesce(d->'header'->>'Due Date','');
  if due !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Invoice due date is required before release';end if;
  if due::date<(d->>'date')::date then raise exception 'Invoice due date cannot precede the invoice date';end if;
 end loop;
 return new;
end; $$;
drop trigger if exists trg_erp_invoice_terms on public.erp_ui_state;
create trigger trg_erp_invoice_terms before insert or update on public.erp_ui_state
for each row execute function public.erp_validate_invoice_terms();
update public.erp_admin_page_catalog set fields=fields||'"Credit Days"'::jsonb where page='Sales Invoice' and not (fields ? 'Credit Days');
update public.erp_admin_page_catalog set fields=fields||'"Due Date"'::jsonb where page='Sales Invoice' and not (fields ? 'Due Date');
notify pgrst,'reload schema';

-- Apply after ERP_AUDIT_FIXES_UPDATE.sql. Additive; no business data is rewritten.
-- Private helper: resolve each item through saved source-line ancestry.
-- Sales-order items define the shared commercial budget across invoice paths.
create or replace function public.erp_invoice_line_scope(p_doc jsonb,p_line jsonb)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare d jsonb:=p_doc;l jsonb:=p_line;parent jsonb;original jsonb;seen jsonb:='[]'::jsonb;identity jsonb;
begin
 for depth in 1..64 loop
  identity:=jsonb_build_array(d->>'module',d->>'number',l->>'id');
  if seen @> jsonb_build_array(identity) then raise exception 'Circular invoice item ancestry';end if;
  seen:=seen||jsonb_build_array(identity);
  if d->>'module'='Sales Orders' or d->'source' is null or d->'source'='null'::jsonb then
   return jsonb_build_object('identity',identity,'quantity',(l->>'quantity')::numeric);
  end if;
  parent:=public.erp_process_payload('dfab-process-'||(d->'source'->>'module'),'{}'::jsonb)->(d->'source'->>'number');
  select value into original from jsonb_array_elements(coalesce(parent->'lines','[]'::jsonb)) where value->>'id'=l->>'sourceLineId' or value->>'id'=l->>'id' order by case when value->>'id'=l->>'sourceLineId' then 0 else 1 end limit 1;
  if parent is null or original is null then raise exception 'Invoice item ancestry is incomplete. Reconcile the original source lines';end if;
  d:=parent;l:=original;
 end loop;
 raise exception 'Invoice item ancestry exceeds the supported depth';
end; $$;
revoke all on function public.erp_invoice_line_scope(jsonb,jsonb) from public,anon,authenticated;

create or replace function public.erp_validate_invoice_reservations(p_changes jsonb,p_expected jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare n text;d jsonb;l jsonb;other jsonb;item jsonb;scope jsonb;other_scope jsonb;reserved numeric;invoices jsonb;totals jsonb:='{}'::jsonb;scope_key text;
begin
 if not(p_changes ? 'dfab-process-Sales Invoice') then return;end if;
 invoices:=coalesce(public.erp_process_payload('dfab-process-Sales Invoice','{}'::jsonb),'{}'::jsonb);
 for other in select value from jsonb_each(invoices) where value->>'status'<>'REJECTED' loop
  for item in select * from jsonb_array_elements(other->'lines') loop
   other_scope:=public.erp_invoice_line_scope(other,item);scope_key:=(other_scope->'identity')::text;
   totals:=jsonb_set(totals,array[scope_key],to_jsonb(coalesce((totals->>scope_key)::numeric,0)+(item->>'quantity')::numeric));
  end loop;
 end loop;
 for n,d in select * from jsonb_each(invoices) loop
  if d is not distinct from p_expected->'dfab-process-Sales Invoice'->n or d->>'status'='REJECTED' then continue;end if;
  for l in select * from jsonb_array_elements(d->'lines') loop
   scope:=public.erp_invoice_line_scope(d,l);reserved:=coalesce((totals->>((scope->'identity')::text))::numeric,0);
   if reserved>(scope->>'quantity')::numeric+0.000001 then raise exception 'Invoice quantity exceeds the remaining sales-order quantity across all source paths';end if;
  end loop;
 end loop;
end; $$;
revoke all on function public.erp_validate_invoice_reservations(jsonb,jsonb) from public,anon,authenticated;

-- Preserve all existing validation/permission/projection rules behind the public
-- RPC. Its org-wide advisory lock remains held until this entire call commits.
do $$ begin
 if to_regprocedure('public.erp_commit_process_base_v2(jsonb,jsonb,text)') is null then
  alter function public.erp_commit_process(jsonb,jsonb,text) rename to erp_commit_process_base_v2;
 end if;
end; $$;
revoke all on function public.erp_commit_process_base_v2(jsonb,jsonb,text) from public,anon,authenticated;
create or replace function public.erp_commit_process(p_changes jsonb,p_expected jsonb,p_action text default 'save')
returns void language plpgsql security definer set search_path=public as $$
begin
 perform public.erp_commit_process_base_v2(p_changes,p_expected,p_action);
 -- Failure rolls back every write performed by the base call atomically.
 perform public.erp_validate_invoice_reservations(p_changes,p_expected);
end; $$;
revoke all on function public.erp_commit_process(jsonb,jsonb,text) from public,anon;
grant execute on function public.erp_commit_process(jsonb,jsonb,text) to authenticated;

-- Authenticated, read-only deployment check; returns no credentials or records.
create or replace function public.erp_release_readiness()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if auth.uid() is null or public.erp_current_org_id() is null or not public.erp_has_permission('ERP.VIEW') then raise exception 'Active ERP view session required' using errcode='42501';end if;
 return jsonb_build_object('invoice_terms',exists(select 1 from pg_trigger where tgname='trg_erp_invoice_terms' and tgrelid='public.erp_ui_state'::regclass and not tgisinternal and tgenabled<>'D'),
  'invoice_reservations',position('erp_validate_invoice_reservations' in pg_get_functiondef('public.erp_commit_process(jsonb,jsonb,text)'::regprocedure))>0
   and not has_function_privilege('authenticated','public.erp_commit_process_base_v2(jsonb,jsonb,text)','EXECUTE')
   and not has_function_privilege('anon','public.erp_commit_process_base_v2(jsonb,jsonb,text)','EXECUTE'));
end; $$;
revoke all on function public.erp_release_readiness() from public,anon;
grant execute on function public.erp_release_readiness() to authenticated;
notify pgrst,'reload schema';

COMMIT;
SELECT 'Invoice terms and cross-source invoice guard installed' AS database_update;
