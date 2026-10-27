-- DFAB OneERP · Production Database Schema
-- Fresh production schema for Supabase PostgreSQL.
-- This file intentionally replaces all earlier ERP SQL setup files.
-- Safe to run on an existing Supabase project: all DFAB production objects use the erp_ prefix.

begin;

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Common helpers
-- -----------------------------------------------------------------------------
create or replace function public.erp_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create or replace function public.erp_current_user_id()
returns uuid language sql stable as $$
  select auth.uid();
$$;

-- -----------------------------------------------------------------------------
-- Organization, users, roles and permissions
-- -----------------------------------------------------------------------------
create table if not exists public.erp_organizations (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  gstin text,
  pan text,
  currency_code char(3) not null default 'INR',
  financial_year_start_month smallint not null default 4 check (financial_year_start_month between 1 and 12),
  timezone text not null default 'Asia/Kolkata',
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.erp_departments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  cost_center text,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code),
  unique (organization_id, name)
);

create table if not exists public.erp_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  employee_code text,
  display_name text not null,
  email text,
  department_id uuid references public.erp_departments(id),
  designation text,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.erp_roles (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  system_role boolean not null default false,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create table if not exists public.erp_permissions (
  code text primary key,
  module text not null,
  action text not null,
  description text
);

create table if not exists public.erp_role_permissions (
  role_id uuid not null references public.erp_roles(id) on delete cascade,
  permission_code text not null references public.erp_permissions(code) on delete cascade,
  primary key (role_id, permission_code)
);

create table if not exists public.erp_user_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null references public.erp_roles(id) on delete cascade,
  primary key (user_id, role_id)
);

create or replace function public.erp_current_org_id()
returns uuid language sql stable security definer set search_path = public as $$
  select organization_id from public.erp_profiles where user_id = auth.uid() and active = true limit 1;
$$;

create or replace function public.erp_has_permission(p_permission text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from public.erp_user_roles ur
    join public.erp_roles r on r.id = ur.role_id and r.active
    join public.erp_role_permissions rp on rp.role_id = r.id
    where ur.user_id = auth.uid() and rp.permission_code = p_permission
  );
$$;

-- -----------------------------------------------------------------------------
-- Number sequences / document references
-- -----------------------------------------------------------------------------
create table if not exists public.erp_number_sequences (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_type text not null,
  prefix text not null,
  financial_year text not null,
  next_value bigint not null default 1 check (next_value > 0),
  pad_length smallint not null default 5 check (pad_length between 1 and 12),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, document_type, financial_year)
);

create or replace function public.erp_next_document_no(p_document_type text, p_prefix text, p_financial_year text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_org uuid := public.erp_current_org_id();
  v_value bigint;
  v_pad int;
begin
  if v_org is null then raise exception 'No active ERP organization is mapped to this user'; end if;
  insert into public.erp_number_sequences(organization_id, document_type, prefix, financial_year)
  values(v_org, p_document_type, p_prefix, p_financial_year)
  on conflict (organization_id, document_type, financial_year) do nothing;

  update public.erp_number_sequences
  set next_value = next_value + 1, updated_at = timezone('utc', now())
  where organization_id = v_org and document_type = p_document_type and financial_year = p_financial_year
  returning next_value - 1, pad_length into v_value, v_pad;

  return p_prefix || '/' || p_financial_year || '/' || lpad(v_value::text, v_pad, '0');
end;
$$;

-- -----------------------------------------------------------------------------
-- Masters: UOM, HSN, product hierarchy, products, partners, process/machines
-- -----------------------------------------------------------------------------
create table if not exists public.erp_uom (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  symbol text not null,
  decimal_places smallint not null default 3 check (decimal_places between 0 and 6),
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create table if not exists public.erp_hsn (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  description text,
  cgst numeric(7,4) not null default 0,
  sgst numeric(7,4) not null default 0,
  igst numeric(7,4) not null default 0,
  applicable_from date not null default current_date,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code, applicable_from)
);

create table if not exists public.erp_product_types (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  active boolean not null default true,
  unique (organization_id, code)
);

create table if not exists public.erp_product_categories (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  description text,
  active boolean not null default true,
  unique (organization_id, code)
);

create table if not exists public.erp_product_groups (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  parent_id uuid references public.erp_product_groups(id),
  code text not null,
  name text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create table if not exists public.erp_products (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  product_type_id uuid references public.erp_product_types(id),
  category_id uuid references public.erp_product_categories(id),
  group_id uuid references public.erp_product_groups(id),
  uom_id uuid references public.erp_uom(id),
  hsn_id uuid references public.erp_hsn(id),
  drawing_no text,
  drawing_revision text,
  material_grade text,
  specification text,
  make_buy text not null default 'MAKE' check (make_buy in ('MAKE','BUY','SERVICE')),
  min_stock numeric(18,6) not null default 0,
  max_stock numeric(18,6),
  reorder_level numeric(18,6) not null default 0,
  standard_cost numeric(18,4) not null default 0,
  status text not null default 'ACTIVE' check (status in ('DRAFT','APPROVAL_PENDING','ACTIVE','INACTIVE','REJECTED')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create table if not exists public.erp_product_revisions (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.erp_products(id) on delete cascade,
  revision text not null,
  drawing_no text,
  effective_from date not null default current_date,
  notes text,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  unique (product_id, revision)
);

create table if not exists public.erp_business_partners (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  partner_type text not null check (partner_type in ('CUSTOMER','VENDOR','PROSPECT','CUSTOMER_VENDOR')),
  code text not null,
  name text not null,
  gstin text,
  pan text,
  email text,
  phone text,
  payment_terms_days integer not null default 0 check (payment_terms_days >= 0),
  credit_limit numeric(18,2) not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, code)
);

create table if not exists public.erp_partner_addresses (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.erp_business_partners(id) on delete cascade,
  address_type text not null default 'BILLING' check (address_type in ('BILLING','SHIPPING','REGISTERED','OTHER')),
  line1 text not null,
  line2 text,
  city text,
  district text,
  state text,
  postal_code text,
  country text not null default 'India',
  default_address boolean not null default false
);

create table if not exists public.erp_partner_contacts (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references public.erp_business_partners(id) on delete cascade,
  name text not null,
  designation text,
  email text,
  phone text,
  kind_attention boolean not null default false,
  active boolean not null default true
);

create table if not exists public.erp_processes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  department_id uuid references public.erp_departments(id),
  outsourced_allowed boolean not null default false,
  active boolean not null default true,
  unique (organization_id, code)
);

create table if not exists public.erp_work_centers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  department_id uuid references public.erp_departments(id),
  machine_type text,
  hourly_rate numeric(18,4) not null default 0,
  capacity_per_hour numeric(18,6),
  status text not null default 'AVAILABLE' check (status in ('AVAILABLE','RUNNING','MAINTENANCE','INACTIVE')),
  unique (organization_id, code)
);

create table if not exists public.erp_locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  code text not null,
  name text not null,
  location_type text not null default 'STORE' check (location_type in ('STORE','WIP','QC','SCRAP','DISPATCH','VENDOR','CUSTOMER')),
  active boolean not null default true,
  unique (organization_id, code)
);

-- -----------------------------------------------------------------------------
-- Engineering: BOM and routing
-- -----------------------------------------------------------------------------
create table if not exists public.erp_boms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  bom_no text not null,
  product_id uuid not null references public.erp_products(id),
  revision text not null,
  effective_from date not null default current_date,
  status text not null default 'DRAFT' check (status in ('DRAFT','APPROVAL_PENDING','APPROVED','OBSOLETE')),
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, bom_no),
  unique (product_id, revision)
);

create table if not exists public.erp_bom_items (
  id uuid primary key default gen_random_uuid(),
  bom_id uuid not null references public.erp_boms(id) on delete cascade,
  line_no integer not null,
  component_product_id uuid not null references public.erp_products(id),
  quantity numeric(18,6) not null check (quantity > 0),
  scrap_percent numeric(8,4) not null default 0 check (scrap_percent >= 0),
  issue_location_id uuid references public.erp_locations(id),
  notes text,
  unique (bom_id, line_no)
);

create table if not exists public.erp_routes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  route_no text not null,
  product_id uuid not null references public.erp_products(id),
  revision text not null,
  status text not null default 'DRAFT' check (status in ('DRAFT','RELEASED','CLOSED','OBSOLETE')),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, route_no)
);

create table if not exists public.erp_route_operations (
  id uuid primary key default gen_random_uuid(),
  route_id uuid not null references public.erp_routes(id) on delete cascade,
  sequence_no integer not null,
  process_id uuid not null references public.erp_processes(id),
  work_center_id uuid references public.erp_work_centers(id),
  setup_minutes numeric(12,2) not null default 0,
  run_minutes_per_unit numeric(12,4) not null default 0,
  outsource boolean not null default false,
  qc_required boolean not null default false,
  notes text,
  unique (route_id, sequence_no)
);

-- -----------------------------------------------------------------------------
-- Generic document registry used for traceability across every module
-- -----------------------------------------------------------------------------
create table if not exists public.erp_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_type text not null,
  document_no text not null,
  document_date date not null default current_date,
  status text not null default 'DRAFT',
  partner_id uuid references public.erp_business_partners(id),
  source_document_id uuid references public.erp_documents(id),
  amount numeric(18,2) not null default 0,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  unique (organization_id, document_type, document_no)
);

create table if not exists public.erp_document_links (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  from_document_id uuid not null references public.erp_documents(id) on delete cascade,
  to_document_id uuid not null references public.erp_documents(id) on delete cascade,
  relation_type text not null default 'FLOW',
  created_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now()),
  unique (from_document_id, to_document_id, relation_type)
);

-- -----------------------------------------------------------------------------
-- Sales / CRM
-- -----------------------------------------------------------------------------
create table if not exists public.erp_sales_enquiries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  enquiry_no text not null,
  customer_id uuid not null references public.erp_business_partners(id),
  contact_id uuid references public.erp_partner_contacts(id),
  enquiry_date date not null default current_date,
  expected_delivery date,
  owner_user_id uuid references auth.users(id),
  status text not null default 'NEW',
  remarks text,
  unique (organization_id, enquiry_no)
);

create table if not exists public.erp_sales_enquiry_lines (
  id uuid primary key default gen_random_uuid(),
  enquiry_id uuid not null references public.erp_sales_enquiries(id) on delete cascade,
  line_no integer not null,
  product_id uuid references public.erp_products(id),
  description text,
  drawing_revision text,
  quantity numeric(18,6) not null check (quantity > 0),
  uom_id uuid references public.erp_uom(id),
  target_price numeric(18,4),
  unique (enquiry_id, line_no)
);

create table if not exists public.erp_sales_quotations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  quotation_no text not null,
  enquiry_id uuid references public.erp_sales_enquiries(id),
  customer_id uuid not null references public.erp_business_partners(id),
  quotation_date date not null default current_date,
  valid_until date,
  currency_code char(3) not null default 'INR',
  subtotal numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  total_amount numeric(18,2) not null default 0,
  status text not null default 'DRAFT',
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  unique (organization_id, quotation_no)
);

create table if not exists public.erp_sales_quotation_lines (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.erp_sales_quotations(id) on delete cascade,
  line_no integer not null,
  enquiry_line_id uuid references public.erp_sales_enquiry_lines(id),
  product_id uuid references public.erp_products(id),
  description text,
  quantity numeric(18,6) not null check (quantity > 0),
  uom_id uuid references public.erp_uom(id),
  unit_price numeric(18,4) not null default 0,
  discount_percent numeric(8,4) not null default 0,
  tax_percent numeric(8,4) not null default 0,
  line_total numeric(18,2) generated always as (round((quantity * unit_price * (1 - discount_percent / 100.0))::numeric, 2)) stored,
  unique (quotation_id, line_no)
);

create table if not exists public.erp_sales_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  sales_order_no text not null,
  quotation_id uuid references public.erp_sales_quotations(id),
  customer_id uuid not null references public.erp_business_partners(id),
  customer_po_no text,
  customer_po_date date,
  order_date date not null default current_date,
  delivery_date date,
  billing_address_id uuid references public.erp_partner_addresses(id),
  shipping_address_id uuid references public.erp_partner_addresses(id),
  subtotal numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  total_amount numeric(18,2) not null default 0,
  status text not null default 'DRAFT',
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  unique (organization_id, sales_order_no)
);

create table if not exists public.erp_sales_order_lines (
  id uuid primary key default gen_random_uuid(),
  sales_order_id uuid not null references public.erp_sales_orders(id) on delete cascade,
  line_no integer not null,
  quotation_line_id uuid references public.erp_sales_quotation_lines(id),
  product_id uuid not null references public.erp_products(id),
  description text,
  quantity numeric(18,6) not null check (quantity > 0),
  delivered_qty numeric(18,6) not null default 0 check (delivered_qty >= 0),
  invoiced_qty numeric(18,6) not null default 0 check (invoiced_qty >= 0),
  uom_id uuid references public.erp_uom(id),
  unit_price numeric(18,4) not null default 0,
  tax_percent numeric(8,4) not null default 0,
  delivery_date date,
  status text not null default 'OPEN',
  unique (sales_order_id, line_no),
  check (delivered_qty <= quantity),
  check (invoiced_qty <= quantity)
);

-- -----------------------------------------------------------------------------
-- Procurement / Purchase
-- -----------------------------------------------------------------------------
create table if not exists public.erp_purchase_indents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  indent_no text not null,
  department_id uuid references public.erp_departments(id),
  indent_date date not null default current_date,
  required_date date,
  requested_by uuid references auth.users(id),
  status text not null default 'DRAFT',
  unique (organization_id, indent_no)
);

create table if not exists public.erp_purchase_indent_lines (
  id uuid primary key default gen_random_uuid(),
  indent_id uuid not null references public.erp_purchase_indents(id) on delete cascade,
  line_no integer not null,
  product_id uuid not null references public.erp_products(id),
  quantity numeric(18,6) not null check (quantity > 0),
  ordered_qty numeric(18,6) not null default 0 check (ordered_qty >= 0),
  uom_id uuid references public.erp_uom(id),
  remarks text,
  unique (indent_id, line_no),
  check (ordered_qty <= quantity)
);

create table if not exists public.erp_purchase_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  po_no text not null,
  vendor_id uuid not null references public.erp_business_partners(id),
  po_date date not null default current_date,
  delivery_date date,
  currency_code char(3) not null default 'INR',
  subtotal numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  total_amount numeric(18,2) not null default 0,
  status text not null default 'DRAFT',
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  unique (organization_id, po_no)
);

create table if not exists public.erp_purchase_order_lines (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references public.erp_purchase_orders(id) on delete cascade,
  line_no integer not null,
  indent_line_id uuid references public.erp_purchase_indent_lines(id),
  product_id uuid not null references public.erp_products(id),
  quantity numeric(18,6) not null check (quantity > 0),
  received_qty numeric(18,6) not null default 0 check (received_qty >= 0),
  accepted_qty numeric(18,6) not null default 0 check (accepted_qty >= 0),
  uom_id uuid references public.erp_uom(id),
  unit_price numeric(18,4) not null default 0,
  tax_percent numeric(8,4) not null default 0,
  delivery_date date,
  status text not null default 'OPEN',
  unique (purchase_order_id, line_no),
  check (received_qty <= quantity),
  check (accepted_qty <= received_qty)
);

create table if not exists public.erp_grns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  grn_no text not null,
  purchase_order_id uuid not null references public.erp_purchase_orders(id),
  vendor_id uuid not null references public.erp_business_partners(id),
  grn_date date not null default current_date,
  vendor_dc_no text,
  vendor_invoice_no text,
  vehicle_no text,
  status text not null default 'AWAITING_QC',
  received_by uuid references auth.users(id),
  unique (organization_id, grn_no)
);

create table if not exists public.erp_grn_lines (
  id uuid primary key default gen_random_uuid(),
  grn_id uuid not null references public.erp_grns(id) on delete cascade,
  line_no integer not null,
  po_line_id uuid not null references public.erp_purchase_order_lines(id),
  product_id uuid not null references public.erp_products(id),
  received_qty numeric(18,6) not null check (received_qty > 0),
  accepted_qty numeric(18,6) not null default 0,
  rejected_qty numeric(18,6) not null default 0,
  uom_id uuid references public.erp_uom(id),
  batch_no text,
  heat_no text,
  unique (grn_id, line_no),
  check (accepted_qty + rejected_qty <= received_qty)
);

create table if not exists public.erp_quality_inspections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  inspection_no text not null,
  inspection_type text not null check (inspection_type in ('INWARD','IN_PROCESS','OUTWARD','JOBWORK')),
  source_document_id uuid references public.erp_documents(id),
  inspection_date date not null default current_date,
  inspector_id uuid references auth.users(id),
  status text not null default 'PENDING',
  remarks text,
  unique (organization_id, inspection_no)
);

create table if not exists public.erp_quality_inspection_lines (
  id uuid primary key default gen_random_uuid(),
  inspection_id uuid not null references public.erp_quality_inspections(id) on delete cascade,
  line_no integer not null,
  product_id uuid not null references public.erp_products(id),
  inspected_qty numeric(18,6) not null check (inspected_qty > 0),
  accepted_qty numeric(18,6) not null default 0,
  rejected_qty numeric(18,6) not null default 0,
  rework_qty numeric(18,6) not null default 0,
  disposition text,
  parameters jsonb not null default '{}'::jsonb,
  unique (inspection_id, line_no),
  check (accepted_qty + rejected_qty + rework_qty <= inspected_qty)
);

create table if not exists public.erp_purchase_invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  invoice_no text not null,
  vendor_invoice_no text not null,
  vendor_id uuid not null references public.erp_business_partners(id),
  purchase_order_id uuid references public.erp_purchase_orders(id),
  invoice_date date not null,
  due_date date,
  taxable_amount numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  total_amount numeric(18,2) not null default 0,
  paid_amount numeric(18,2) not null default 0,
  status text not null default 'DRAFT',
  unique (organization_id, invoice_no),
  check (paid_amount >= 0 and paid_amount <= total_amount)
);

create table if not exists public.erp_purchase_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  purchase_invoice_id uuid not null references public.erp_purchase_invoices(id) on delete cascade,
  line_no integer not null,
  grn_line_id uuid references public.erp_grn_lines(id),
  product_id uuid not null references public.erp_products(id),
  quantity numeric(18,6) not null check (quantity > 0),
  uom_id uuid references public.erp_uom(id),
  unit_price numeric(18,4) not null default 0,
  tax_percent numeric(8,4) not null default 0,
  unique (purchase_invoice_id, line_no)
);

-- -----------------------------------------------------------------------------
-- Inventory and stores (immutable movement ledger)
-- -----------------------------------------------------------------------------
create table if not exists public.erp_inventory_movements (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  movement_time timestamptz not null default timezone('utc', now()),
  movement_type text not null check (movement_type in ('OPENING','GRN_ACCEPT','MATERIAL_ISSUE','MATERIAL_RETURN','PRODUCTION_RECEIPT','SCRAP','ADJUSTMENT_IN','ADJUSTMENT_OUT','DISPATCH','SALES_RETURN','JOBWORK_IN','JOBWORK_OUT','TRANSFER')),
  product_id uuid not null references public.erp_products(id),
  from_location_id uuid references public.erp_locations(id),
  to_location_id uuid references public.erp_locations(id),
  quantity numeric(18,6) not null check (quantity > 0),
  uom_id uuid references public.erp_uom(id),
  unit_cost numeric(18,4),
  batch_no text,
  heat_no text,
  source_document_id uuid references public.erp_documents(id),
  source_line_id uuid,
  remarks text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists idx_erp_inventory_product_time on public.erp_inventory_movements(organization_id, product_id, movement_time);
create index if not exists idx_erp_inventory_source on public.erp_inventory_movements(source_document_id);

create or replace view public.erp_stock_balance as
select
  m.organization_id,
  m.product_id,
  l.id as location_id,
  l.code as location_code,
  sum(case when m.to_location_id = l.id then m.quantity else 0 end) -
  sum(case when m.from_location_id = l.id then m.quantity else 0 end) as quantity
from public.erp_inventory_movements m
join public.erp_locations l on l.id in (m.from_location_id, m.to_location_id)
group by m.organization_id, m.product_id, l.id, l.code;

-- -----------------------------------------------------------------------------
-- Production, material issue, routing execution and outsourcing
-- -----------------------------------------------------------------------------
create table if not exists public.erp_work_orders (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  work_order_no text not null,
  sales_order_line_id uuid references public.erp_sales_order_lines(id),
  product_id uuid not null references public.erp_products(id),
  bom_id uuid references public.erp_boms(id),
  route_id uuid references public.erp_routes(id),
  planned_qty numeric(18,6) not null check (planned_qty > 0),
  completed_qty numeric(18,6) not null default 0,
  rejected_qty numeric(18,6) not null default 0,
  planned_start date,
  planned_end date,
  actual_start timestamptz,
  actual_end timestamptz,
  status text not null default 'PLANNED',
  created_by uuid references auth.users(id),
  unique (organization_id, work_order_no),
  check (completed_qty + rejected_qty <= planned_qty)
);

create table if not exists public.erp_material_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  request_no text not null,
  work_order_id uuid not null references public.erp_work_orders(id),
  request_date date not null default current_date,
  status text not null default 'REQUESTED',
  requested_by uuid references auth.users(id),
  unique (organization_id, request_no)
);

create table if not exists public.erp_material_request_lines (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.erp_material_requests(id) on delete cascade,
  line_no integer not null,
  product_id uuid not null references public.erp_products(id),
  required_qty numeric(18,6) not null check (required_qty > 0),
  issued_qty numeric(18,6) not null default 0,
  returned_qty numeric(18,6) not null default 0,
  uom_id uuid references public.erp_uom(id),
  unique (request_id, line_no),
  check (issued_qty <= required_qty),
  check (returned_qty <= issued_qty)
);

create table if not exists public.erp_route_executions (
  id uuid primary key default gen_random_uuid(),
  work_order_id uuid not null references public.erp_work_orders(id) on delete cascade,
  route_operation_id uuid not null references public.erp_route_operations(id),
  sequence_no integer not null,
  work_center_id uuid references public.erp_work_centers(id),
  operator_id uuid references auth.users(id),
  started_at timestamptz,
  completed_at timestamptz,
  input_qty numeric(18,6) not null default 0,
  good_qty numeric(18,6) not null default 0,
  reject_qty numeric(18,6) not null default 0,
  rework_qty numeric(18,6) not null default 0,
  status text not null default 'PENDING',
  notes text,
  unique (work_order_id, route_operation_id)
);

create table if not exists public.erp_production_outputs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  output_no text not null,
  work_order_id uuid not null references public.erp_work_orders(id),
  output_date date not null default current_date,
  good_qty numeric(18,6) not null default 0,
  reject_qty numeric(18,6) not null default 0,
  rework_qty numeric(18,6) not null default 0,
  status text not null default 'DRAFT',
  unique (organization_id, output_no),
  check (good_qty >= 0 and reject_qty >= 0 and rework_qty >= 0)
);

create table if not exists public.erp_outsource_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  outsource_no text not null,
  document_kind text not null check (document_kind in ('ISSUE_DC','RECEIPT','RETURN_DC')),
  work_order_id uuid not null references public.erp_work_orders(id),
  vendor_id uuid not null references public.erp_business_partners(id),
  process_id uuid references public.erp_processes(id),
  source_outsource_id uuid references public.erp_outsource_documents(id),
  document_date date not null default current_date,
  status text not null default 'DRAFT',
  unique (organization_id, outsource_no)
);

create table if not exists public.erp_outsource_lines (
  id uuid primary key default gen_random_uuid(),
  outsource_id uuid not null references public.erp_outsource_documents(id) on delete cascade,
  line_no integer not null,
  product_id uuid not null references public.erp_products(id),
  issued_qty numeric(18,6) not null default 0,
  received_qty numeric(18,6) not null default 0,
  accepted_qty numeric(18,6) not null default 0,
  rejected_qty numeric(18,6) not null default 0,
  uom_id uuid references public.erp_uom(id),
  unique (outsource_id, line_no)
);

-- -----------------------------------------------------------------------------
-- Dispatch, billing, returns and finance
-- -----------------------------------------------------------------------------
create table if not exists public.erp_delivery_challans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  dc_no text not null,
  customer_id uuid not null references public.erp_business_partners(id),
  sales_order_id uuid references public.erp_sales_orders(id),
  dc_date date not null default current_date,
  vehicle_no text,
  transporter text,
  eway_bill_no text,
  status text not null default 'DRAFT',
  unique (organization_id, dc_no)
);

create table if not exists public.erp_delivery_challan_lines (
  id uuid primary key default gen_random_uuid(),
  delivery_challan_id uuid not null references public.erp_delivery_challans(id) on delete cascade,
  line_no integer not null,
  sales_order_line_id uuid references public.erp_sales_order_lines(id),
  product_id uuid not null references public.erp_products(id),
  quantity numeric(18,6) not null check (quantity > 0),
  uom_id uuid references public.erp_uom(id),
  unique (delivery_challan_id, line_no)
);

create table if not exists public.erp_sales_invoices (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  invoice_no text not null,
  customer_id uuid not null references public.erp_business_partners(id),
  sales_order_id uuid references public.erp_sales_orders(id),
  delivery_challan_id uuid references public.erp_delivery_challans(id),
  invoice_date date not null default current_date,
  due_date date,
  taxable_amount numeric(18,2) not null default 0,
  cgst numeric(18,2) not null default 0,
  sgst numeric(18,2) not null default 0,
  igst numeric(18,2) not null default 0,
  total_amount numeric(18,2) not null default 0,
  received_amount numeric(18,2) not null default 0,
  e_invoice_irn text,
  e_invoice_status text not null default 'NOT_CONNECTED',
  status text not null default 'DRAFT',
  unique (organization_id, invoice_no),
  check (received_amount >= 0 and received_amount <= total_amount)
);

create table if not exists public.erp_sales_invoice_lines (
  id uuid primary key default gen_random_uuid(),
  sales_invoice_id uuid not null references public.erp_sales_invoices(id) on delete cascade,
  line_no integer not null,
  delivery_challan_line_id uuid references public.erp_delivery_challan_lines(id),
  product_id uuid not null references public.erp_products(id),
  description text,
  quantity numeric(18,6) not null check (quantity > 0),
  uom_id uuid references public.erp_uom(id),
  unit_price numeric(18,4) not null default 0,
  tax_percent numeric(8,4) not null default 0,
  unique (sales_invoice_id, line_no)
);

create table if not exists public.erp_sales_returns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  return_no text not null,
  customer_id uuid not null references public.erp_business_partners(id),
  invoice_id uuid references public.erp_sales_invoices(id),
  return_date date not null default current_date,
  reason text,
  decision text,
  status text not null default 'INSPECTION',
  unique (organization_id, return_no)
);

create table if not exists public.erp_credit_notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  credit_note_no text not null,
  customer_id uuid not null references public.erp_business_partners(id),
  sales_invoice_id uuid references public.erp_sales_invoices(id),
  sales_return_id uuid references public.erp_sales_returns(id),
  note_date date not null default current_date,
  taxable_amount numeric(18,2) not null default 0,
  tax_amount numeric(18,2) not null default 0,
  total_amount numeric(18,2) not null default 0,
  status text not null default 'DRAFT',
  unique (organization_id, credit_note_no)
);

create table if not exists public.erp_payments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid unique references public.erp_documents(id) on delete cascade,
  payment_no text not null,
  payment_type text not null check (payment_type in ('CUSTOMER_RECEIPT','VENDOR_PAYMENT')),
  partner_id uuid not null references public.erp_business_partners(id),
  payment_date date not null default current_date,
  payment_mode text,
  bank_reference text,
  amount numeric(18,2) not null check (amount > 0),
  status text not null default 'DRAFT',
  unique (organization_id, payment_no)
);

create table if not exists public.erp_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.erp_payments(id) on delete cascade,
  sales_invoice_id uuid references public.erp_sales_invoices(id),
  purchase_invoice_id uuid references public.erp_purchase_invoices(id),
  allocated_amount numeric(18,2) not null check (allocated_amount > 0),
  check ((sales_invoice_id is not null)::int + (purchase_invoice_id is not null)::int = 1)
);

create or replace view public.erp_receivables as
select i.organization_id, i.id invoice_id, i.invoice_no, i.customer_id, i.invoice_date, i.due_date,
       i.total_amount, i.received_amount, (i.total_amount - i.received_amount) balance,
       greatest(0, current_date - coalesce(i.due_date, i.invoice_date)) aging_days, i.status
from public.erp_sales_invoices i
where i.total_amount > i.received_amount;

create or replace view public.erp_payables as
select i.organization_id, i.id invoice_id, i.invoice_no, i.vendor_id, i.invoice_date, i.due_date,
       i.total_amount, i.paid_amount, (i.total_amount - i.paid_amount) balance,
       greatest(0, current_date - coalesce(i.due_date, i.invoice_date)) aging_days, i.status
from public.erp_purchase_invoices i
where i.total_amount > i.paid_amount;

-- -----------------------------------------------------------------------------
-- Approvals, files, notifications, audit
-- -----------------------------------------------------------------------------
create table if not exists public.erp_approval_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid not null references public.erp_documents(id) on delete cascade,
  requested_by uuid not null references auth.users(id),
  requested_at timestamptz not null default timezone('utc', now()),
  approver_role_id uuid references public.erp_roles(id),
  approver_user_id uuid references auth.users(id),
  status text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','CANCELLED')),
  decision_by uuid references auth.users(id),
  decision_at timestamptz,
  remarks text
);

create table if not exists public.erp_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  document_id uuid references public.erp_documents(id) on delete cascade,
  product_id uuid references public.erp_products(id) on delete cascade,
  file_name text not null,
  storage_bucket text not null default 'erp-files',
  storage_path text not null,
  mime_type text,
  file_size bigint,
  checksum_sha256 text,
  uploaded_by uuid references auth.users(id),
  uploaded_at timestamptz not null default timezone('utc', now()),
  check (document_id is not null or product_id is not null)
);

create table if not exists public.erp_notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  title text not null,
  body text,
  severity text not null default 'INFO' check (severity in ('INFO','SUCCESS','WARNING','ERROR')),
  source_document_id uuid references public.erp_documents(id),
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.erp_audit_log (
  id bigint generated always as identity primary key,
  organization_id uuid,
  user_id uuid,
  occurred_at timestamptz not null default timezone('utc', now()),
  table_name text not null,
  action text not null,
  row_id text,
  old_data jsonb,
  new_data jsonb,
  request_id text
);

create or replace function public.erp_audit_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_org uuid;
  v_row_id text;
begin
  v_org := coalesce((case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'organization_id','')::uuid;
  v_row_id := coalesce((case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end)->>'id','');
  insert into public.erp_audit_log(organization_id,user_id,table_name,action,row_id,old_data,new_data)
  values(v_org, auth.uid(), tg_table_name, tg_op, v_row_id,
         case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
         case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end;
$$;

-- -----------------------------------------------------------------------------
-- UI compatibility storage.
-- All existing screens persist here immediately while normalized ERP tables are
-- available for strict module APIs. PostgreSQL JSONB uses TOAST compression.
-- -----------------------------------------------------------------------------
create table if not exists public.erp_ui_state (
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  storage_key text not null,
  payload jsonb not null,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, storage_key)
);

create table if not exists public.erp_ui_records (
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  storage_key text not null,
  record_key text not null,
  sort_order integer not null default 0,
  payload jsonb not null,
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (organization_id, storage_key, record_key)
);

create or replace function public.erp_expand_ui_state()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  item jsonb;
  ord bigint;
  rk text;
begin
  delete from public.erp_ui_records where organization_id = new.organization_id and storage_key = new.storage_key;
  if jsonb_typeof(new.payload) = 'array' then
    for item, ord in select value, ordinality from jsonb_array_elements(new.payload) with ordinality loop
      rk := coalesce(nullif(item->>0,''), '__row_' || ord::text);
      insert into public.erp_ui_records(organization_id,storage_key,record_key,sort_order,payload)
      values(new.organization_id,new.storage_key,rk,ord::int,item)
      on conflict (organization_id,storage_key,record_key)
      do update set sort_order=excluded.sort_order,payload=excluded.payload,updated_at=timezone('utc',now());
    end loop;
  else
    insert into public.erp_ui_records(organization_id,storage_key,record_key,sort_order,payload)
    values(new.organization_id,new.storage_key,'__singleton__',1,new.payload)
    on conflict (organization_id,storage_key,record_key)
    do update set payload=excluded.payload,updated_at=timezone('utc',now());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_erp_expand_ui_state on public.erp_ui_state;
create trigger trg_erp_expand_ui_state after insert or update of payload on public.erp_ui_state
for each row execute function public.erp_expand_ui_state();

-- RPCs used by the current frontend. They enforce organization scope server-side.
create or replace function public.erp_get_ui_state()
returns table(storage_key text, payload jsonb)
language sql stable security definer set search_path=public as $$
  select s.storage_key, s.payload
  from public.erp_ui_state s
  where s.organization_id = public.erp_current_org_id()
  order by s.storage_key;
$$;

create or replace function public.erp_put_ui_state(p_storage_key text, p_payload jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid := public.erp_current_org_id();
begin
  if v_org is null then raise exception 'ERP profile/organization is not configured for this user'; end if;
  if p_storage_key is null or length(trim(p_storage_key)) = 0 then raise exception 'Storage key is required'; end if;
  insert into public.erp_ui_state(organization_id,storage_key,payload,updated_by)
  values(v_org,p_storage_key,coalesce(p_payload,'null'::jsonb),auth.uid())
  on conflict (organization_id,storage_key)
  do update set payload=excluded.payload,updated_by=auth.uid(),updated_at=timezone('utc',now());
end;
$$;

create or replace function public.erp_delete_ui_state(p_storage_key text)
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid := public.erp_current_org_id();
begin
  delete from public.erp_ui_state where organization_id=v_org and storage_key=p_storage_key;
end;
$$;

-- -----------------------------------------------------------------------------
-- Updated-at triggers
-- -----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'erp_organizations','erp_departments','erp_profiles','erp_roles','erp_uom','erp_hsn',
    'erp_product_groups','erp_products','erp_business_partners','erp_boms','erp_routes',
    'erp_documents','erp_ui_state'
  ] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.erp_set_updated_at()', t, t);
  end loop;
end $$;

-- Audit highest-risk operational tables.
do $$
declare t text;
begin
  foreach t in array array[
    'erp_products','erp_business_partners','erp_boms','erp_routes','erp_sales_orders',
    'erp_purchase_orders','erp_grns','erp_quality_inspections','erp_work_orders',
    'erp_inventory_movements','erp_delivery_challans','erp_sales_invoices',
    'erp_purchase_invoices','erp_payments','erp_approval_requests'
  ] loop
    execute format('drop trigger if exists trg_%I_audit on public.%I', t, t);
    execute format('create trigger trg_%I_audit after insert or update or delete on public.%I for each row execute function public.erp_audit_trigger()', t, t);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- Security / RLS
-- -----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'erp_organizations','erp_departments','erp_profiles','erp_roles','erp_user_roles',
    'erp_uom','erp_hsn','erp_product_types','erp_product_categories','erp_product_groups','erp_products',
    'erp_business_partners','erp_processes','erp_work_centers','erp_locations','erp_boms','erp_routes',
    'erp_documents','erp_document_links','erp_sales_enquiries','erp_sales_quotations','erp_sales_orders',
    'erp_purchase_indents','erp_purchase_orders','erp_grns','erp_quality_inspections','erp_purchase_invoices',
    'erp_inventory_movements','erp_work_orders','erp_material_requests','erp_production_outputs','erp_outsource_documents',
    'erp_delivery_challans','erp_sales_invoices','erp_sales_returns','erp_credit_notes','erp_payments',
    'erp_approval_requests','erp_attachments','erp_notifications','erp_audit_log','erp_ui_state','erp_ui_records'
  ] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists erp_org_select on public.%I', t);
    execute format('drop policy if exists erp_org_insert on public.%I', t);
    execute format('drop policy if exists erp_org_update on public.%I', t);
    execute format('drop policy if exists erp_org_delete on public.%I', t);
  end loop;
end $$;

-- Child/detail tables are never exposed directly in this frontend. RLS is enabled with
-- no permissive policy so they remain server/RPC-only until a module-specific API is bound.
do $$
declare t text;
begin
  foreach t in array array[
    'erp_partner_addresses','erp_partner_contacts','erp_product_revisions','erp_bom_items','erp_route_operations',
    'erp_sales_enquiry_lines','erp_sales_quotation_lines','erp_sales_order_lines','erp_purchase_indent_lines',
    'erp_purchase_order_lines','erp_grn_lines','erp_quality_inspection_lines','erp_purchase_invoice_lines',
    'erp_material_request_lines','erp_route_executions','erp_outsource_lines','erp_delivery_challan_lines',
    'erp_sales_invoice_lines','erp_payment_allocations'
  ] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Tables with organization_id use one standard organization isolation policy set.
do $$
declare t text;
begin
  foreach t in array array[
    'erp_departments','erp_roles','erp_uom','erp_hsn','erp_product_types','erp_product_categories',
    'erp_product_groups','erp_products','erp_business_partners','erp_processes','erp_work_centers','erp_locations',
    'erp_boms','erp_routes','erp_documents','erp_document_links','erp_sales_enquiries','erp_sales_quotations',
    'erp_sales_orders','erp_purchase_indents','erp_purchase_orders','erp_grns','erp_quality_inspections',
    'erp_purchase_invoices','erp_inventory_movements','erp_work_orders','erp_material_requests','erp_production_outputs',
    'erp_outsource_documents','erp_delivery_challans','erp_sales_invoices','erp_sales_returns','erp_credit_notes',
    'erp_payments','erp_approval_requests','erp_attachments','erp_notifications','erp_audit_log','erp_ui_state','erp_ui_records'
  ] loop
    execute format('create policy erp_org_select on public.%I for select to authenticated using (organization_id = public.erp_current_org_id())', t);
    execute format('create policy erp_org_insert on public.%I for insert to authenticated with check (organization_id = public.erp_current_org_id())', t);
    execute format('create policy erp_org_update on public.%I for update to authenticated using (organization_id = public.erp_current_org_id()) with check (organization_id = public.erp_current_org_id())', t);
    execute format('create policy erp_org_delete on public.%I for delete to authenticated using (organization_id = public.erp_current_org_id())', t);
  end loop;
end $$;

-- Organization row itself is scoped by its primary key.
drop policy if exists erp_org_select on public.erp_organizations;
create policy erp_org_select on public.erp_organizations for select to authenticated using (id = public.erp_current_org_id());

-- Profile reads are limited to same organization; a user may update their own profile.
drop policy if exists erp_profile_select on public.erp_profiles;
create policy erp_profile_select on public.erp_profiles for select to authenticated
using (organization_id = public.erp_current_org_id());
drop policy if exists erp_profile_self_update on public.erp_profiles;
create policy erp_profile_self_update on public.erp_profiles for update to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Role mapping can be read by authenticated users in their organization through joins.
drop policy if exists erp_user_roles_select on public.erp_user_roles;
create policy erp_user_roles_select on public.erp_user_roles for select to authenticated
using (exists(select 1 from public.erp_roles r where r.id=role_id and r.organization_id=public.erp_current_org_id()));

-- Permissions are global read-only reference data.
alter table public.erp_permissions enable row level security;
alter table public.erp_role_permissions enable row level security;
drop policy if exists erp_permissions_read on public.erp_permissions;
create policy erp_permissions_read on public.erp_permissions for select to authenticated using (true);
drop policy if exists erp_role_permissions_read on public.erp_role_permissions;
create policy erp_role_permissions_read on public.erp_role_permissions for select to authenticated using (
  exists(select 1 from public.erp_roles r where r.id=role_id and r.organization_id=public.erp_current_org_id())
);

-- Child tables are protected through their parent organization.
-- They are intentionally not directly editable through REST until module-specific APIs are bound.

-- Authenticated users can execute the safe RPC compatibility layer.
grant usage on schema public to authenticated;
grant execute on function public.erp_current_org_id() to authenticated;
grant execute on function public.erp_has_permission(text) to authenticated;
grant execute on function public.erp_get_ui_state() to authenticated;
grant execute on function public.erp_put_ui_state(text,jsonb) to authenticated;
grant execute on function public.erp_delete_ui_state(text) to authenticated;
grant execute on function public.erp_next_document_no(text,text,text) to authenticated;

-- Direct table privileges required by PostgREST are deliberately narrow for UI state.
grant select, insert, update, delete on public.erp_ui_state to authenticated;
grant select on public.erp_ui_records to authenticated;
grant select on public.erp_stock_balance, public.erp_receivables, public.erp_payables to authenticated;

-- -----------------------------------------------------------------------------
-- Bootstrap one DFAB organization and map existing Supabase users automatically.
-- Change display names/departments later from ERP administration.
-- -----------------------------------------------------------------------------
insert into public.erp_organizations(code,name,currency_code,financial_year_start_month,timezone)
values('DFAB','DFAB Stainless Systems Pvt Ltd','INR',4,'Asia/Kolkata')
on conflict (code) do update set name=excluded.name, updated_at=timezone('utc',now());

insert into public.erp_roles(organization_id,code,name,description,system_role)
select o.id,'ADMIN','Administrator','Full ERP administration',true from public.erp_organizations o where o.code='DFAB'
on conflict (organization_id,code) do nothing;

insert into public.erp_permissions(code,module,action,description) values
('ERP.VIEW','ERP','VIEW','View ERP modules'),
('ERP.CREATE','ERP','CREATE','Create ERP records'),
('ERP.EDIT','ERP','EDIT','Edit ERP records'),
('ERP.DELETE','ERP','DELETE','Delete ERP records'),
('ERP.APPROVE','ERP','APPROVE','Approve ERP documents'),
('ERP.EXPORT','ERP','EXPORT','Export ERP reports'),
('SYSTEM.ADMIN','SYSTEM','ADMIN','Manage ERP system configuration')
on conflict (code) do nothing;

insert into public.erp_role_permissions(role_id,permission_code)
select r.id,p.code from public.erp_roles r cross join public.erp_permissions p
where r.code='ADMIN' and r.organization_id=(select id from public.erp_organizations where code='DFAB')
on conflict do nothing;

insert into public.erp_profiles(user_id,organization_id,display_name,email)
select u.id,o.id,coalesce(nullif(u.raw_user_meta_data->>'full_name',''),split_part(u.email,'@',1)),u.email
from auth.users u cross join public.erp_organizations o
where o.code='DFAB'
on conflict (user_id) do update set organization_id=excluded.organization_id,email=excluded.email;

insert into public.erp_user_roles(user_id,role_id)
select p.user_id,r.id
from public.erp_profiles p
join public.erp_roles r on r.organization_id=p.organization_id and r.code='ADMIN'
on conflict do nothing;

-- New Auth users are automatically added to DFAB with no role escalation beyond the
-- current single-company rollout. Review this trigger before enabling self-signup.
create or replace function public.erp_on_auth_user_created()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_org uuid; v_role uuid;
begin
  select id into v_org from public.erp_organizations where code='DFAB' limit 1;
  insert into public.erp_profiles(user_id,organization_id,display_name,email)
  values(new.id,v_org,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(new.email,'@',1)),new.email)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_erp_auth_user_created on auth.users;
create trigger trg_erp_auth_user_created after insert on auth.users
for each row execute function public.erp_on_auth_user_created();

commit;

-- END OF DFAB OneERP production schema
