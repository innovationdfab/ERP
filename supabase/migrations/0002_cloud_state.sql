-- Central persistence layer for the existing DFAB ERP UI.
-- JSONB values are stored by PostgreSQL using TOAST compression automatically when beneficial.
-- Run after 0001_core.sql.

create table if not exists public.erp_state (
  storage_key text primary key,
  payload jsonb not null default 'null'::jsonb,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);

create index if not exists erp_state_updated_at_idx on public.erp_state(updated_at desc);

create or replace function public.set_erp_state_audit_fields()
returns trigger
language plpgsql
security invoker
set search_path = public
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

drop trigger if exists trg_erp_state_audit on public.erp_state;
create trigger trg_erp_state_audit
before insert or update on public.erp_state
for each row execute function public.set_erp_state_audit_fields();

alter table public.erp_state enable row level security;

-- Authenticated ERP users share the same company workspace.
drop policy if exists "erp_state_authenticated_select" on public.erp_state;
create policy "erp_state_authenticated_select" on public.erp_state
for select to authenticated using (true);

drop policy if exists "erp_state_authenticated_insert" on public.erp_state;
create policy "erp_state_authenticated_insert" on public.erp_state
for insert to authenticated with check (true);

drop policy if exists "erp_state_authenticated_update" on public.erp_state;
create policy "erp_state_authenticated_update" on public.erp_state
for update to authenticated using (true) with check (true);

drop policy if exists "erp_state_authenticated_delete" on public.erp_state;
create policy "erp_state_authenticated_delete" on public.erp_state
for delete to authenticated using (true);
