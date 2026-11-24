-- Additive release update. Apply after ERP_PRODUCTION_FLOWS_UPDATE.sql.
-- Retains all business records, permissions and historical invoice dates.
begin;
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
commit;
