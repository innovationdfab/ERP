-- DFAB OneERP optional additive integrity upgrade.
-- Apply in staging first. No existing tables, rows, policies, or functions are removed.
-- The existing legacy UI-state RPCs remain intact for backward compatibility.

begin;

-- Compare-and-swap write: an edited transaction cannot silently overwrite another
-- user's newer version of the same UI-state section.
create or replace function public.erp_put_ui_state_if_unchanged(
  p_storage_key text, p_expected jsonb, p_payload jsonb
) returns void
language plpgsql security definer set search_path=public as $$
declare v_org uuid := public.erp_current_org_id(); v_previous jsonb;
begin
  if auth.uid() is null or v_org is null then raise exception 'ERP session/organization is missing'; end if;
  if p_storage_key is null or p_storage_key !~ '^dfab-[a-zA-Z0-9 /_.-]+$' then raise exception 'Invalid storage key'; end if;
  if p_payload is null then raise exception 'ERP payload cannot be null'; end if;
  -- Shared lock with batch operations. Row lock alone is not enough for absent keys.
  perform pg_advisory_xact_lock(hashtextextended(v_org::text || ':' || p_storage_key, 0));
  select payload into v_previous from public.erp_ui_state
   where organization_id=v_org and storage_key=p_storage_key for update;
  if v_previous is distinct from p_expected then
    raise exception 'ERP record changed in another session. Reload the page before saving.' using errcode='40001';
  end if;
  insert into public.erp_ui_state(organization_id,storage_key,payload,updated_by)
  values(v_org,p_storage_key,p_payload,auth.uid())
  on conflict (organization_id,storage_key)
  do update set payload=excluded.payload,updated_by=auth.uid(),updated_at=timezone('utc',now());
end;
$$;

-- One PostgreSQL transaction updates the newly created downstream document,
-- the workflow-link register, and optional invoice details together. If any
-- part fails, PostgreSQL rolls back all parts.
create or replace function public.erp_commit_ui_state_batch(p_changes jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare
  v_org uuid := public.erp_current_org_id();
  v_item jsonb; v_key text; v_old jsonb; v_expected jsonb; v_new jsonb;
begin
  if auth.uid() is null or v_org is null then raise exception 'ERP session/organization is missing'; end if;
  if jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) < 2 or jsonb_array_length(p_changes) > 3 then
    raise exception 'Expected two or three connected ERP state sections';
  end if;
  if (select count(distinct item->>'key') from jsonb_array_elements(p_changes) item) <> jsonb_array_length(p_changes) then
    raise exception 'Each state section may appear only once';
  end if;
  -- Serialize across the organization; prevents racing document/link creation.
  perform pg_advisory_xact_lock(hashtextextended(v_org::text || ':flow',0));
  for v_item in select * from jsonb_array_elements(p_changes) loop
    v_key := v_item->>'key';
    if v_key is null or not (v_key like 'dfab-erp-%' or v_key in ('dfab-workflow-links-v1','dfab-invoice-details-v1')) then
      raise exception 'Unsupported connected document key %', v_key;
    end if;
    if not (v_item ? 'expected' and v_item ? 'payload') then raise exception 'Missing expected state or payload'; end if;
    v_expected:=v_item->'expected';v_new:=v_item->'payload';
    if v_new is null or jsonb_typeof(v_new)='null' then raise exception 'Null workflow payload is not allowed'; end if;
    v_old:=null;
    select payload into v_old from public.erp_ui_state where organization_id=v_org and storage_key=v_key for update;
    if v_old is distinct from (case when jsonb_typeof(v_expected)='null' then null else v_expected end) then
      raise exception 'ERP workflow section % changed in another session. Reload before retrying.',v_key using errcode='40001';
    end if;
  end loop;
  for v_item in select * from jsonb_array_elements(p_changes) loop
    v_key:=v_item->>'key';v_new:=v_item->'payload';
    insert into public.erp_ui_state(organization_id,storage_key,payload,updated_by)
      values(v_org,v_key,v_new,auth.uid())
    on conflict (organization_id,storage_key) do update
      set payload=excluded.payload,updated_by=auth.uid(),updated_at=timezone('utc',now());
  end loop;
end;
$$;

revoke all on function public.erp_put_ui_state_if_unchanged(text,jsonb,jsonb) from public;
revoke all on function public.erp_commit_ui_state_batch(jsonb) from public;
grant execute on function public.erp_put_ui_state_if_unchanged(text,jsonb,jsonb) to authenticated;
grant execute on function public.erp_commit_ui_state_batch(jsonb) to authenticated;

commit;
