-- DFAB OneERP core PostgreSQL schema
-- Apply in a fresh Supabase project using SQL Editor or the Supabase CLI.
-- This migration is additive and does not touch the frontend's current localStorage data.

create extension if not exists pgcrypto;

create type public.document_status as enum ('draft','submitted','approved','rejected','cancelled','closed');
create type public.stock_direction as enum ('in','out','reserve','release','adjust');
create type public.party_type as enum ('customer','vendor');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  employee_code text unique,
  full_name text not null,
  department text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  created_at timestamptz not null default now()
);

create table public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  description text
);

create table public.user_roles (
  user_id uuid not null references public.profiles(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  primary key (user_id, role_id)
);

create table public.role_permissions (
  role_id uuid not null references public.roles(id) on delete cascade,
  permission_id uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table public.uoms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  decimals smallint not null default 3 check (decimals between 0 and 6),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.product_groups (
  id uuid primary key default gen_random_uuid(),
  code text unique,
  name text not null unique,
  parent_id uuid references public.product_groups(id),
  description text,
  is_active boolean not null default true
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  product_type text not null,
  product_group_id uuid references public.product_groups(id),
  uom_id uuid not null references public.uoms(id),
  revision text,
  hsn_code text,
  drawing_no text,
  material_grade text,
  standard_cost numeric(18,4) not null default 0 check (standard_cost >= 0),
  selling_price numeric(18,4) not null default 0 check (selling_price >= 0),
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.parties (
  id uuid primary key default gen_random_uuid(),
  party_type public.party_type not null,
  code text not null unique,
  name text not null,
  gstin text,
  pan text,
  email text,
  phone text,
  payment_terms_days integer not null default 0 check (payment_terms_days >= 0),
  credit_limit numeric(18,2) not null default 0 check (credit_limit >= 0),
  is_active boolean not null default true,
  billing_address jsonb not null default '{}'::jsonb,
  shipping_address jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.locations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  location_type text not null default 'store',
  is_active boolean not null default true
);

create table public.bom_headers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  revision text not null,
  status public.document_status not null default 'draft',
  effective_from date,
  notes text,
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(product_id, revision)
);

create table public.bom_lines (
  id uuid primary key default gen_random_uuid(),
  bom_id uuid not null references public.bom_headers(id) on delete cascade,
  line_no integer not null check (line_no > 0),
  component_product_id uuid not null references public.products(id),
  qty numeric(18,6) not null check (qty > 0),
  scrap_pct numeric(7,4) not null default 0 check (scrap_pct between 0 and 100),
  notes text,
  unique(bom_id, line_no)
);

create table public.route_headers (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  revision text not null,
  status public.document_status not null default 'draft',
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(product_id, revision)
);

create table public.route_operations (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.route_headers(id) on delete cascade,
  operation_no integer not null check (operation_no > 0),
  process_name text not null,
  machine_code text,
  setup_minutes numeric(12,3) not null default 0 check (setup_minutes >= 0),
  cycle_minutes numeric(12,3) not null default 0 check (cycle_minutes >= 0),
  outsource_allowed boolean not null default false,
  unique(route_id, operation_no)
);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  module text not null,
  document_no text not null,
  financial_year text not null,
  party_id uuid references public.parties(id),
  document_date date not null default current_date,
  status public.document_status not null default 'draft',
  currency char(3) not null default 'INR',
  source_document_id uuid references public.documents(id),
  remarks text,
  totals jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles(id),
  approved_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(module, document_no, financial_year)
);

create table public.document_lines (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.documents(id) on delete cascade,
  line_no integer not null check (line_no > 0),
  product_id uuid references public.products(id),
  description text,
  qty numeric(18,6) not null default 0 check (qty >= 0),
  uom_id uuid references public.uoms(id),
  unit_rate numeric(18,4) not null default 0 check (unit_rate >= 0),
  tax_rate numeric(7,4) not null default 0 check (tax_rate between 0 and 100),
  required_date date,
  metadata jsonb not null default '{}'::jsonb,
  unique(document_id, line_no)
);

create table public.work_orders (
  id uuid primary key default gen_random_uuid(),
  work_order_no text not null unique,
  sales_order_line_id uuid references public.document_lines(id),
  product_id uuid not null references public.products(id),
  bom_id uuid references public.bom_headers(id),
  route_id uuid references public.route_headers(id),
  planned_qty numeric(18,6) not null check (planned_qty > 0),
  completed_qty numeric(18,6) not null default 0 check (completed_qty >= 0),
  rejected_qty numeric(18,6) not null default 0 check (rejected_qty >= 0),
  status public.document_status not null default 'draft',
  start_date date,
  due_date date,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  movement_ts timestamptz not null default now(),
  product_id uuid not null references public.products(id),
  location_id uuid not null references public.locations(id),
  batch_no text,
  direction public.stock_direction not null,
  qty numeric(18,6) not null check (qty > 0),
  source_type text not null,
  source_id uuid,
  source_line_id uuid,
  work_order_id uuid references public.work_orders(id),
  reason text,
  created_by uuid references public.profiles(id),
  idempotency_key text unique,
  created_at timestamptz not null default now()
);

create index inventory_movements_product_location_idx on public.inventory_movements(product_id, location_id, movement_ts);
create index document_lines_document_idx on public.document_lines(document_id);
create index documents_module_date_idx on public.documents(module, document_date desc);

create table public.quality_inspections (
  id uuid primary key default gen_random_uuid(),
  inspection_no text not null unique,
  inspection_type text not null check (inspection_type in ('inward','inprocess','outward')),
  source_type text not null,
  source_id uuid not null,
  product_id uuid not null references public.products(id),
  inspected_qty numeric(18,6) not null check (inspected_qty > 0),
  accepted_qty numeric(18,6) not null default 0 check (accepted_qty >= 0),
  rejected_qty numeric(18,6) not null default 0 check (rejected_qty >= 0),
  result text not null default 'pending',
  inspected_by uuid references public.profiles(id),
  inspected_at timestamptz,
  remarks text,
  created_at timestamptz not null default now(),
  check (accepted_qty + rejected_qty <= inspected_qty)
);

create table public.payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_document_id uuid not null references public.documents(id) on delete cascade,
  invoice_document_id uuid not null references public.documents(id),
  amount numeric(18,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique(payment_document_id, invoice_document_id)
);

create table public.attachments (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  bucket text not null default 'erp-private',
  object_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint check (size_bytes >= 0),
  uploaded_by uuid references public.profiles(id),
  uploaded_at timestamptz not null default now()
);

create table public.approval_events (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  action text not null check (action in ('submitted','approved','rejected','cancelled','returned')),
  actor_id uuid not null references public.profiles(id),
  comments text,
  created_at timestamptz not null default now()
);

create table public.audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger products_set_updated_at before update on public.products
for each row execute function public.set_updated_at();
create trigger parties_set_updated_at before update on public.parties
for each row execute function public.set_updated_at();
create trigger documents_set_updated_at before update on public.documents
for each row execute function public.set_updated_at();
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

-- Balance view: signed stock movements only. Reservations are intentionally separate.
create or replace view public.stock_balance as
select
  product_id,
  location_id,
  batch_no,
  sum(case direction when 'in' then qty when 'out' then -qty when 'adjust' then qty else 0 end) as on_hand_qty,
  sum(case direction when 'reserve' then qty when 'release' then -qty else 0 end) as reserved_qty
from public.inventory_movements
group by product_id, location_id, batch_no;

-- RLS is mandatory for company data.
alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.role_permissions enable row level security;
alter table public.uoms enable row level security;
alter table public.product_groups enable row level security;
alter table public.products enable row level security;
alter table public.parties enable row level security;
alter table public.locations enable row level security;
alter table public.bom_headers enable row level security;
alter table public.bom_lines enable row level security;
alter table public.route_headers enable row level security;
alter table public.route_operations enable row level security;
alter table public.documents enable row level security;
alter table public.document_lines enable row level security;
alter table public.work_orders enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.quality_inspections enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.attachments enable row level security;
alter table public.approval_events enable row level security;
alter table public.audit_log enable row level security;

-- Bootstrap policies: authenticated users can read master/transaction data.
-- Write policies should be narrowed by module/role before production use.
create policy "authenticated read products" on public.products for select to authenticated using (true);
create policy "authenticated read product groups" on public.product_groups for select to authenticated using (true);
create policy "authenticated read uoms" on public.uoms for select to authenticated using (true);
create policy "authenticated read parties" on public.parties for select to authenticated using (true);
create policy "authenticated read locations" on public.locations for select to authenticated using (true);
create policy "authenticated read documents" on public.documents for select to authenticated using (true);
create policy "authenticated read document lines" on public.document_lines for select to authenticated using (true);
create policy "authenticated read stock" on public.inventory_movements for select to authenticated using (true);

-- Never expose service_role keys to this Vite frontend.
