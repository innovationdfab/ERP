-- DFAB OneERP ALL REQUIRED SQL — 23 November 2026.
-- Run this entire file once in Supabase > SQL Editor, using the project owner.
-- Back up your project before running. All steps commit together or roll back.
-- Includes production schema (only when absent), integrity, Admin Control,
-- password policy, workspace, extensions, transaction flows and Zoho email jobs.
-- Existing production records and user role assignments are retained.
-- Do not additionally run the individual component scripts for this update.
-- Superseded legacy setup scripts, QA/check scripts and optional admin recovery
-- are intentionally excluded. This file does not change Auth passwords or send mail.
-- Zoho SMTP secrets and Edge Function deployment remain separate, as described
-- in PRODUCTION-FLOWS-UPDATE.md. SQL cannot install the mail transport credentials.

BEGIN;
SELECT pg_advisory_xact_lock(hashtextextended('DFAB-OneERP-All-In-One-Migration',0));

-- Never rerun the historical role bootstrap on an installed ERP.
DO $dfab_setup_guard$
BEGIN
 IF to_regclass('public.erp_ui_state') IS NULL AND to_regclass('public.erp_profiles') IS NULL THEN
  IF (SELECT count(*) FROM auth.users) <> 1 THEN
   RAISE EXCEPTION 'Fresh ERP setup requires exactly one intended initial administrator in Supabase Auth. Existing ERP projects do not run this bootstrap.';
  END IF;
  EXECUTE $dfab_initial_schema$
-- DFAB OneERP · Production Database Schema
-- Fresh production schema for Supabase PostgreSQL.
-- This file intentionally replaces all earlier ERP SQL setup files.
-- Safe to run on an existing Supabase project: all DFAB production objects use the erp_ prefix.

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

-- END OF DFAB OneERP production schema

$dfab_initial_schema$;
 ELSIF to_regclass('public.erp_ui_state') IS NULL OR to_regclass('public.erp_profiles') IS NULL THEN
  RAISE EXCEPTION 'The existing ERP baseline is incomplete. Restore the baseline before applying this update.';
 ELSE
  RAISE NOTICE 'Existing ERP detected: production bootstrap skipped; existing roles retained.';
 END IF;
END;
$dfab_setup_guard$;

-- COMPONENT: ERP_FLOW_INTEGRITY_UPGRADE
-- DFAB OneERP optional additive integrity upgrade.
-- Apply in staging first. No existing tables, rows, policies, or functions are removed.
-- The existing legacy UI-state RPCs remain intact for backward compatibility.

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


-- COMPONENT: ERP_PRODUCTION_GUARDRAILS
-- DFAB OneERP: additive production data-integrity guardrails.
-- IMPORTANT: apply ERP_FLOW_INTEGRITY_UPGRADE.sql first, test this on STAGING,
-- then schedule a coordinated frontend/backend deployment.
-- Does not modify application page layout, document values, or role assignments.

-- A user can edit only while their organization and active ERP.EDIT role exist.
-- This applies even to SECURITY DEFINER RPCs which update compatibility state.
CREATE OR REPLACE FUNCTION public.erp_guard_ui_state_mutation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid;
BEGIN
  v_org := CASE WHEN TG_OP='DELETE' THEN OLD.organization_id ELSE NEW.organization_id END;
  IF auth.uid() IS NULL OR v_org IS DISTINCT FROM public.erp_current_org_id()
    OR NOT public.erp_has_permission('ERP.EDIT') THEN
    RAISE EXCEPTION 'ERP write access denied for this user and organization' USING ERRCODE='42501';
  END IF;
  RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END; $$;

DROP TRIGGER IF EXISTS trg_erp_ui_state_permissions ON public.erp_ui_state;
CREATE TRIGGER trg_erp_ui_state_permissions
BEFORE INSERT OR UPDATE OR DELETE ON public.erp_ui_state
FOR EACH ROW EXECUTE FUNCTION public.erp_guard_ui_state_mutation();

-- Compare-and-swap deletion is required to avoid deleting another employee's
-- newer section when the current page was based on an older snapshot.
CREATE OR REPLACE FUNCTION public.erp_delete_ui_state_if_unchanged(
  p_storage_key text, p_expected jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org uuid := public.erp_current_org_id(); v_old jsonb;
BEGIN
  IF auth.uid() IS NULL OR v_org IS NULL OR NOT public.erp_has_permission('ERP.DELETE') THEN
    RAISE EXCEPTION 'ERP delete access denied' USING ERRCODE='42501';
  END IF;
  IF p_storage_key IS NULL OR p_storage_key !~ '^dfab-[a-zA-Z0-9 /_.-]+$' THEN
    RAISE EXCEPTION 'Invalid storage key';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(v_org::text || ':' || p_storage_key, 0));
  SELECT payload INTO v_old FROM public.erp_ui_state
  WHERE organization_id=v_org AND storage_key=p_storage_key FOR UPDATE;
  IF v_old IS DISTINCT FROM p_expected THEN
    RAISE EXCEPTION 'ERP records changed in another session. Reload before deleting.' USING ERRCODE='40001';
  END IF;
  DELETE FROM public.erp_ui_state WHERE organization_id=v_org AND storage_key=p_storage_key;
END; $$;

-- Existing trigger uses the first column of rows as a map key; repeated document
-- codes can otherwise overwrite previous rows in the derived erp_ui_records table.
-- Preserve all original values and their ordering, even with duplicate codes.
CREATE OR REPLACE FUNCTION public.erp_expand_ui_state()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE item jsonb; ord bigint; base_key text; rk text;
BEGIN
  DELETE FROM public.erp_ui_records
  WHERE organization_id=NEW.organization_id AND storage_key=NEW.storage_key;
  IF jsonb_typeof(NEW.payload)='array' THEN
    FOR item, ord IN SELECT value, ordinality
      FROM jsonb_array_elements(NEW.payload) WITH ORDINALITY LOOP
      base_key := COALESCE(NULLIF(item->>0,''),'__row_'||ord::text);
      rk := base_key;
      IF EXISTS(SELECT 1 FROM public.erp_ui_records
        WHERE organization_id=NEW.organization_id AND storage_key=NEW.storage_key AND record_key=rk) THEN
        rk := '__row_' || ord::text || '__' || base_key;
      END IF;
      INSERT INTO public.erp_ui_records(organization_id,storage_key,record_key,sort_order,payload)
      VALUES(NEW.organization_id,NEW.storage_key,rk,ord::int,item);
    END LOOP;
  ELSE
    INSERT INTO public.erp_ui_records(organization_id,storage_key,record_key,sort_order,payload)
    VALUES(NEW.organization_id,NEW.storage_key,'__singleton__',1,NEW.payload);
  END IF;
  RETURN NEW;
END; $$;

-- Keep the derived read model consistent when an entire UI section is deleted.
CREATE OR REPLACE FUNCTION public.erp_cleanup_ui_records()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  DELETE FROM public.erp_ui_records
   WHERE organization_id=OLD.organization_id AND storage_key=OLD.storage_key;
  RETURN OLD;
END; $$;
DROP TRIGGER IF EXISTS trg_erp_cleanup_ui_records ON public.erp_ui_state;
CREATE TRIGGER trg_erp_cleanup_ui_records
AFTER DELETE ON public.erp_ui_state FOR EACH ROW EXECUTE FUNCTION public.erp_cleanup_ui_records();

-- Immutable audit entry per document collection write. The previous and new
-- JSON can be large: for production retention, archive or partition audit rows.
DROP TRIGGER IF EXISTS trg_erp_ui_state_audit ON public.erp_ui_state;
CREATE TRIGGER trg_erp_ui_state_audit
AFTER INSERT OR UPDATE OR DELETE ON public.erp_ui_state
FOR EACH ROW EXECUTE FUNCTION public.erp_audit_trigger();

REVOKE ALL ON FUNCTION public.erp_delete_ui_state_if_unchanged(text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.erp_delete_ui_state_if_unchanged(text,jsonb) TO authenticated;

-- Frontend writes go through guarded RPC functions, not direct PostgREST DML.
REVOKE INSERT,UPDATE,DELETE ON public.erp_ui_state FROM authenticated;
REVOKE INSERT,UPDATE,DELETE ON public.erp_ui_records FROM authenticated;


-- COMPONENT: ERP_ADMIN_CONTROL
-- DFAB OneERP Admin Control Center. ADDITIVE migration; run after
-- DFAB_ERP_PRODUCTION.sql, ERP_FLOW_INTEGRITY_UPGRADE.sql and
-- ERP_PRODUCTION_GUARDRAILS.sql. Test with a staging backup first.
-- IMPORTANT: Existing ADMIN assignments are NOT silently revoked. Review and
-- demote unwanted admins in the new panel before enabling broad staff access.

create table if not exists public.erp_admin_page_catalog (
  page text primary key,
  module_group text not null,
  columns jsonb not null default '[]'::jsonb,
  fields jsonb not null default '[]'::jsonb,
  statuses jsonb not null default '[]'::jsonb,
  default_next text,
  active boolean not null default true,
  check(length(page) between 2 and 100),
  check(jsonb_typeof(columns)='array' and jsonb_typeof(fields)='array' and jsonb_typeof(statuses)='array')
);
create table if not exists public.erp_admin_module_rights (
  role_id uuid not null references public.erp_roles(id) on delete cascade,
  page text not null references public.erp_admin_page_catalog(page),
  can_view boolean not null default false,
  can_create boolean not null default false,
  can_edit boolean not null default false,
  can_delete boolean not null default false,
  can_approve boolean not null default false,
  can_export boolean not null default false,
  primary key(role_id,page)
);
create table if not exists public.erp_admin_storage_map (
  storage_key text primary key,
  page text not null references public.erp_admin_page_catalog(page),
  record_key_index integer not null default 0 check (record_key_index between 0 and 24),
  status_index integer not null default -1 check (status_index between -1 and 24),
  check(storage_key ~ '^dfab-[a-zA-Z0-9 /_.-]+$')
);
create table if not exists public.erp_admin_flow_templates (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  name text not null check(length(trim(name)) between 3 and 100),
  description text not null default '',
  status text not null default 'draft' check(status in ('draft','published')),
  version integer not null default 1 check(version>0),
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,name)
);
create unique index if not exists erp_one_published_flow_per_org on public.erp_admin_flow_templates(organization_id) where status='published';
create table if not exists public.erp_admin_flow_edges (
  id uuid primary key default gen_random_uuid(),
  template_id uuid not null references public.erp_admin_flow_templates(id) on delete cascade,
  source_page text not null references public.erp_admin_page_catalog(page),
  target_page text not null references public.erp_admin_page_catalog(page),
  gate_statuses text[] not null default '{}',
  field_map jsonb not null default '{}'::jsonb,
  unique(template_id,source_page),
  check(source_page <> target_page),
  check(jsonb_typeof(field_map)='object')
);
create table if not exists public.erp_admin_events (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.erp_organizations(id) on delete cascade,
  actor_id uuid references auth.users(id),
  event text not null,
  target text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists erp_admin_events_org_time on public.erp_admin_events(organization_id,created_at desc);
create index if not exists erp_admin_template_org on public.erp_admin_flow_templates(organization_id,status);

-- Catalog entries are generated from the actual application document configs.
-- Existing table rows and document schemas are not rewritten.
insert into public.erp_admin_page_catalog(page,module_group,columns,fields,statuses,default_next) values
('Activity Log','Administration','["Time","User","Action","Reference","Module"]'::jsonb,'["Time","User","Action","Reference","Module"]'::jsonb,'[]'::jsonb,null),
('Asset Allocation','Shared','["Allocation No","Asset","Employee","Allocated Date","Status"]'::jsonb,'["Allocation No","Asset","Employee","Allocated Date"]'::jsonb,'["Allocated","Returned","Maintenance"]'::jsonb,null),
('BOM-Based Work Order','Production','["BOM WO No","BOM No","Product","Qty","Start Date","Target Date","Status"]'::jsonb,'["BOM WO No","BOM No","Product","Qty","Start Date","Target Date"]'::jsonb,'["Draft","Approved","Released","Completed"]'::jsonb,'Work Order'),
('CRM Pipeline','Sales','["Lead","Customer","Value","Owner","Stage"]'::jsonb,'["Lead","Customer","Value","Owner"]'::jsonb,'["New","Qualified","Quotation","Won","Lost"]'::jsonb,'Sales Enquiries'),
('Categories','Shared','["Category Code","Category Name","Description"]'::jsonb,'["Category Code","Category Name","Description"]'::jsonb,'[]'::jsonb,null),
('Credit Note','Sales','["Credit Note No","Invoice","Customer","Date","Amount","Status"]'::jsonb,'["Credit Note No","Invoice","Customer","Date","Amount"]'::jsonb,'["Draft","Approved","Posted"]'::jsonb,'Customer Payments'),
('Customer Payments','Sales','["Receipt No","Customer","Invoice","Date","Amount","Status"]'::jsonb,'["Receipt No","Customer","Invoice","Date","Amount"]'::jsonb,'["Pending","Part Paid","Settled"]'::jsonb,null),
('Customer Price List','Sales','["Price Ref","Customer","Product","UOM","Rate","Valid Until","Status"]'::jsonb,'["Price Ref","Customer","Product","UOM","Rate","Valid Until"]'::jsonb,'["Draft","Active","Expired"]'::jsonb,null),
('Customers','Sales','["Code","Name"]'::jsonb,'["Code","Name"]'::jsonb,'[]'::jsonb,null),
('Daily Task Master','Administration','["Task Code","Task","Department","Frequency","Status"]'::jsonb,'["Task Code","Task","Department","Frequency"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Database Backup','Administration','["Reference","Description"]'::jsonb,'["Reference"]'::jsonb,'[]'::jsonb,null),
('Delivery Challan','Sales','["DC No","Customer","SO No","Product","Qty","Vehicle","Status"]'::jsonb,'["DC No","Customer","SO No","Product","Qty","Vehicle"]'::jsonb,'["Draft","Approved","Dispatched","Delivered"]'::jsonb,'Sales Invoice'),
('Delivery Channel','Sales','["Channel Code","Channel","Transporter","Contact","Region","Status"]'::jsonb,'["Channel Code","Channel","Transporter","Contact","Region"]'::jsonb,'["Draft","Active","Inactive"]'::jsonb,null),
('Department Master','Administration','["Department Code","Department Name","Head","Cost Center","Status"]'::jsonb,'["Department Code","Department Name","Head","Cost Center"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Dispatch Intimation','Sales','["Intimation No","SO No","Customer","Product","Qty","Planned Date","Status"]'::jsonb,'["Intimation No","SO No","Customer","Product","Qty","Planned Date"]'::jsonb,'["Draft","Approved","Sent","Acknowledged"]'::jsonb,'Dispatch Schedule'),
('Dispatch Schedule','Sales','["Schedule No","SO No","Customer","Product","Qty","Scheduled Date","Status"]'::jsonb,'["Schedule No","SO No","Customer","Product","Qty","Scheduled Date"]'::jsonb,'["Draft","Confirmed","Ready","Dispatched"]'::jsonb,'Delivery Challan'),
('Excess Issue','Shared','["Issue No","WO No","Item","Qty","Reason","Store","Status"]'::jsonb,'["Issue No","WO No","Item","Qty","Reason","Store"]'::jsonb,'["Draft","Approval Pending","Approved","Issued"]'::jsonb,'Input to Production'),
('Excess Stock','Stores','["Entry No","Item","Warehouse","Excess Qty","Reason","Status"]'::jsonb,'["Entry No","Item","Warehouse","Excess Qty","Reason"]'::jsonb,'["Identified","Approved","Adjusted"]'::jsonb,null),
('GRN','Purchase','["GRN No","PO No","Vendor","Item","Received Qty","QC Status"]'::jsonb,'["GRN No","PO No","Vendor","Item","Received Qty"]'::jsonb,'["Awaiting QC","Accepted","Rejected"]'::jsonb,'Inward QC'),
('General Task','Shared','["Task No","Task","Owner","Due Date","Status"]'::jsonb,'["Task No","Task","Owner","Due Date"]'::jsonb,'["Open","In Progress","Completed"]'::jsonb,null),
('HSN Master','Administration','["HSN Code","Description","GST %"]'::jsonb,'["HSN Code","Description","GST %"]'::jsonb,'[]'::jsonb,null),
('Import Purchase','Purchase','["Import No","Vendor","PO No","Item","Qty","Currency","Customs Value","Status"]'::jsonb,'["Import No","Vendor","PO No","Item","Qty","Currency","Customs Value"]'::jsonb,'["Draft","Approval Pending","Approved","Received"]'::jsonb,'GRN'),
('In-process QC','Quality','["QC No","WO No","Operation","Qty","Inspector","Disposition","Status"]'::jsonb,'["QC No","WO No","Operation","Qty","Inspector","Disposition"]'::jsonb,'["Pending","In Inspection","Passed","Rejected"]'::jsonb,null),
('Indent To Order','Purchase','["Indent No","Vendor","Item","Qty","Action Status"]'::jsonb,'["Indent No","Vendor","Item","Qty"]'::jsonb,'["Open","PO Created"]'::jsonb,'Purchase Orders'),
('Input to Production','Production','["Input No","WO No","Item","Qty","Issue No","Date","Status"]'::jsonb,'["Input No","WO No","Item","Qty","Issue No","Date"]'::jsonb,'["Draft","Approved","Issued","Consumed"]'::jsonb,'Stage Consumption'),
('Instrument Master','Administration','["Instrument Code","Instrument Name","Range","Calibration Due","Status"]'::jsonb,'["Instrument Code","Instrument Name","Range","Calibration Due"]'::jsonb,'["Active","Calibration Due","Inactive"]'::jsonb,null),
('Inward QC','Quality','["QC No","GRN No","Item","Qty","Inspector","Status"]'::jsonb,'["QC No","GRN No","Item","Qty","Inspector"]'::jsonb,'["Pending","Passed","Rejected"]'::jsonb,'Purchase'),
('Inward Quality','Quality','["Inspection No","GRN No","Item","Accepted Qty","Rejected Qty","Status"]'::jsonb,'["Inspection No","GRN No","Item","Accepted Qty","Rejected Qty"]'::jsonb,'["Pending","Inspected","Posted"]'::jsonb,null),
('Inward Quality Rejection','Quality','["Rejection No","QC No","Vendor","Item","Rejected Qty","Status"]'::jsonb,'["Rejection No","QC No","Vendor","Item","Rejected Qty"]'::jsonb,'["Open","Return Pending","Returned","Closed"]'::jsonb,null),
('Job Order','Production','["Job No","Work Order","Vendor","Process","Qty","Required Date","Status"]'::jsonb,'["Job No","Work Order","Vendor","Process","Qty","Required Date"]'::jsonb,'["Draft","Approved","Issued","Completed"]'::jsonb,'Outsource Issue DC'),
('Job Work Inward','Production','["Inward No","Customer","DC No","Material","Qty","Status"]'::jsonb,'["Inward No","Customer","DC No","Material","Qty"]'::jsonb,'["Received","QC Pending","Accepted","Closed"]'::jsonb,'Job Work Return DC'),
('Job Work QC','Quality','["QC No","Receipt No","Vendor","Item","Qty","Inspector","Status"]'::jsonb,'["QC No","Receipt No","Vendor","Item","Qty","Inspector"]'::jsonb,'["Pending","In Inspection","Passed","Rejected"]'::jsonb,null),
('Job Work Return DC','Production','["Return DC No","Customer","Inward No","Product","Qty","Status"]'::jsonb,'["Return DC No","Customer","Inward No","Product","Qty"]'::jsonb,'["Draft","Dispatched","Delivered"]'::jsonb,null),
('Jobwork Material Issue','Stores','["Issue No","Job No","Vendor","Item","Qty","Issue Date","Status"]'::jsonb,'["Issue No","Job No","Vendor","Item","Qty","Issue Date"]'::jsonb,'["Draft","Approved","Issued","Closed"]'::jsonb,'Jobwork Material Receipt'),
('Jobwork Material Receipt','Stores','["Receipt No","Issue No","Vendor","Item","Received Qty","Receipt Date","Status"]'::jsonb,'["Receipt No","Issue No","Vendor","Item","Received Qty","Receipt Date"]'::jsonb,'["Draft","Received","QC Pending","Accepted"]'::jsonb,'Job Work QC'),
('Kind Attention','Shared','["Code","Contact Person","Company","Designation","Status"]'::jsonb,'["Code","Contact Person","Company","Designation"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Masters','Administration','["Master Code","Master Name","Module","Menu Sequence","Status"]'::jsonb,'["Master Code","Master Name","Module","Menu Sequence"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Material Issue','Stores','["Issue No","Work Order","Item","Qty","Store","Status"]'::jsonb,'["Issue No","Work Order","Item","Qty","Store"]'::jsonb,'["Draft","Issued","Returned"]'::jsonb,'Route Cards'),
('Material Request','Stores','["Request No","Work Order","Item","Qty","Status"]'::jsonb,'["Request No","Work Order","Item","Qty"]'::jsonb,'["Requested","Approved","Issued"]'::jsonb,'Material Issue'),
('Material Reserve','Stores','["Reserve No","WO No","Item","Qty","Warehouse","Required Date","Status"]'::jsonb,'["Reserve No","WO No","Item","Qty","Warehouse","Required Date"]'::jsonb,'["Draft","Approved","Reserved","Released"]'::jsonb,'Material Request'),
('Material Unreserved','Stores','["Unreserve No","Reserve No","Item","Qty","Warehouse","Date","Status"]'::jsonb,'["Unreserve No","Reserve No","Item","Qty","Warehouse","Date"]'::jsonb,'["Draft","Approved","Released"]'::jsonb,null),
('Menu','Administration','["Menu Code","Menu Caption","Parent Menu","Route","Status"]'::jsonb,'["Menu Code","Menu Caption","Parent Menu","Route"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Modules','Administration','["Module Code","Module Name","Sequence","Status"]'::jsonb,'["Module Code","Module Name","Sequence"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Opening Stock','Stores','["Entry No","Item","Warehouse","Qty","Rate","Status"]'::jsonb,'["Entry No","Item","Warehouse","Qty","Rate"]'::jsonb,'["Draft","Posted"]'::jsonb,null),
('Outsource Issue DC','Production','["DC No","Vendor","Work Order","Process","Qty","Status"]'::jsonb,'["DC No","Vendor","Work Order","Process","Qty"]'::jsonb,'["Draft","Dispatched","Part Received","Closed"]'::jsonb,'Outsource Receipt'),
('Outsource Receipt','Production','["Receipt No","Issue DC","Vendor","Process","Received Qty","Status"]'::jsonb,'["Receipt No","Issue DC","Vendor","Process","Received Qty"]'::jsonb,'["Received","QC Pending","Accepted","Closed"]'::jsonb,null),
('Outward QC','Quality','["QC No","Output No","Product","Qty","Inspector","Status"]'::jsonb,'["QC No","Output No","Product","Qty","Inspector"]'::jsonb,'["Pending","Passed","Rejected"]'::jsonb,'Delivery Challan'),
('PO Number Details','Shared','["PO Number","Customer","PO Date","Value","Status"]'::jsonb,'["PO Number","Customer","PO Date","Value"]'::jsonb,'["Open","Consumed","Closed"]'::jsonb,null),
('Pending Approvals','Shared','["Document","Reference No","Requested By","Amount","Status"]'::jsonb,'["Document","Reference No","Requested By","Amount"]'::jsonb,'["Pending","Approved","Rejected"]'::jsonb,null),
('Pick Slip','Stores','["Pick No","SO No","Warehouse","Item","Qty","Picker","Status"]'::jsonb,'["Pick No","SO No","Warehouse","Item","Qty","Picker"]'::jsonb,'["Draft","Allocated","Picked","Confirmed"]'::jsonb,'Dispatch Intimation'),
('Process Master','Production','["Process Code","Process Name","Department","Status"]'::jsonb,'["Process Code","Process Name","Department"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Process Price List','Production','["Price Ref","Process","Vendor","Rate","Effective Date","Status"]'::jsonb,'["Price Ref","Process","Vendor","Rate","Effective Date"]'::jsonb,'["Draft","Active","Expired"]'::jsonb,null),
('Procurement Planning','Purchase','["Plan No","Item","Required Qty","Available Qty","Need Date","Department","Status"]'::jsonb,'["Plan No","Item","Required Qty","Available Qty","Need Date","Department"]'::jsonb,'["Draft","Reviewed","Approved","Released"]'::jsonb,'Purchase Indents'),
('Procurement Schedule','Purchase','["Schedule No","PO No","Vendor","Item","Qty","Planned Date","Status"]'::jsonb,'["Schedule No","PO No","Vendor","Item","Qty","Planned Date"]'::jsonb,'["Draft","Confirmed","Partially Delivered","Completed"]'::jsonb,'GRN'),
('Production BOM','Production','["BOM No","Product","Revision","Status"]'::jsonb,'["BOM No","Product","Revision"]'::jsonb,'["Draft","Approval Pending","Approved"]'::jsonb,null),
('Production Output','Production','["Output No","WO No","Product","Good Qty","Reject Qty","Status"]'::jsonb,'["Output No","WO No","Product","Good Qty","Reject Qty"]'::jsonb,'["Draft","QC Pending","Accepted"]'::jsonb,'Outward QC'),
('Production Schedule','Production','["Schedule No","WO No","Product","Qty","Machine","Planned Date","Status"]'::jsonb,'["Schedule No","WO No","Product","Qty","Machine","Planned Date"]'::jsonb,'["Draft","Released","Running","Completed"]'::jsonb,'Input to Production'),
('Products','Shared','["Product Code","Product Name","Product Type","Group","UOM"]'::jsonb,'["Product Code","Product Name","Product Type","Group","UOM"]'::jsonb,'[]'::jsonb,null),
('Proforma Invoice','Sales','["Proforma No","Customer","SO No","Date","Amount","Status"]'::jsonb,'["Proforma No","Customer","SO No","Date","Amount"]'::jsonb,'["Draft","Approved","Sent","Converted"]'::jsonb,null),
('Project Order','Planning','["Project Order No","Project No","Customer","SO No","Value","Due Date","Status"]'::jsonb,'["Project Order No","Project No","Customer","SO No","Value","Due Date"]'::jsonb,'["Draft","Approved","Running","Completed"]'::jsonb,'Work Order'),
('Project Planning','Planning','["Project No","Customer","SO No","Start Date","Target Date","Owner","Status"]'::jsonb,'["Project No","Customer","SO No","Start Date","Target Date","Owner"]'::jsonb,'["Draft","Approved","Active","Completed"]'::jsonb,'Project Order'),
('Prospects','Shared','["Prospect","Contact","Source","Status"]'::jsonb,'["Prospect","Contact","Source"]'::jsonb,'["New","Qualified","Customer","Lost"]'::jsonb,null),
('Purchase','Purchase','["Invoice No","Vendor","PO No","Invoice Date","Taxable Amount","Status"]'::jsonb,'["Invoice No","Vendor","PO No","Invoice Date","Taxable Amount"]'::jsonb,'["Draft","QC Cleared","Posted","Paid"]'::jsonb,'Vendor Payments'),
('Purchase Indents','Purchase','["Indent No","Department","Item","Qty","Required Date","Status"]'::jsonb,'["Indent No","Department","Item","Qty","Required Date"]'::jsonb,'["Draft","Approval Pending","Approved","Converted"]'::jsonb,'Indent To Order'),
('Purchase Orders','Purchase','["PO No","Vendor","PO Date","Amount","Delivery Date","Status"]'::jsonb,'["PO No","Vendor","PO Date","Amount","Delivery Date"]'::jsonb,'["Draft","Approval Pending","Approved","Sent","Partially Received","Received","Closed"]'::jsonb,'GRN'),
('Purchase Return','Purchase','["Return No","GRN No","Vendor","Item","Qty","Reason","Status"]'::jsonb,'["Return No","GRN No","Vendor","Item","Qty","Reason"]'::jsonb,'["Draft","Approval Pending","Approved","Returned"]'::jsonb,null),
('Put Away','Stores','["Putaway No","GRN No","Item","Qty","Warehouse","Rack","Status"]'::jsonb,'["Putaway No","GRN No","Item","Qty","Warehouse","Rack"]'::jsonb,'["Draft","QC Cleared","Put Away","Completed"]'::jsonb,null),
('Quality Master','Quality','["Plan Code","Quality Plan","Product Group","Revision","Status"]'::jsonb,'["Plan Code","Quality Plan","Product Group","Revision"]'::jsonb,'["Draft","Approved","Inactive"]'::jsonb,null),
('RM Inward and Outward','Shared','["Entry No","Raw Material","Inward Qty","Outward Qty","Balance","Date"]'::jsonb,'["Entry No","Raw Material","Inward Qty","Outward Qty","Balance","Date"]'::jsonb,'[]'::jsonb,null),
('Rejection Note','Quality','["Rejection No","Work Order","Product","Qty","Reason","Status"]'::jsonb,'["Rejection No","Work Order","Product","Qty","Reason"]'::jsonb,'["Open","Disposition Pending","Rework","Scrap","Closed"]'::jsonb,null),
('Remark Master','Administration','["Remark Code","Remark","Module","Status"]'::jsonb,'["Remark Code","Remark","Module"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Reports','Shared','["Report Code","Report Name","Module","Export Type","Status"]'::jsonb,'["Report Code","Report Name","Module","Export Type"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Return to Store','Shared','["Return No","WO No","Item","Qty","Warehouse","Date","Status"]'::jsonb,'["Return No","WO No","Item","Qty","Warehouse","Date"]'::jsonb,'["Draft","Inspected","Accepted","Posted"]'::jsonb,null),
('Role Permissions','Administration','["Role","Module","View","Create","Edit","Approve"]'::jsonb,'["Role","Module","View","Create","Edit","Approve"]'::jsonb,'[]'::jsonb,null),
('Route Card','Production','["Route No","Product","Process","Status"]'::jsonb,'["Route No","Product","Process"]'::jsonb,'["Draft","Released","Closed"]'::jsonb,null),
('Route Cards','Production','["Route No","WO No","Operation","Machine","Completed Qty","Status"]'::jsonb,'["Route No","WO No","Operation","Machine","Completed Qty"]'::jsonb,'["Pending","Running","Completed"]'::jsonb,'Production Output'),
('SO Number Details','Shared','["SO Number","Customer","Product","Qty","Delivery Date","Status"]'::jsonb,'["SO Number","Customer","Product","Qty","Delivery Date"]'::jsonb,'["Open","In Production","Completed"]'::jsonb,null),
('Sales Enquiries','Sales','["Enquiry No","Customer","Product","Qty","Expected Delivery","Status"]'::jsonb,'["Enquiry No","Customer","Product","Qty","Expected Delivery"]'::jsonb,'["New","Under Review","Quoted","Won","Lost"]'::jsonb,'Sales Quotations'),
('Sales Invoice','Sales','["#","Invoice No","Date","Customer","SO No","Reference","Status","Amount","Sync","Remarks"]'::jsonb,'["Invoice No","Customer","SO No","Amount"]'::jsonb,'["DRAFT","APPROVED"]'::jsonb,null),
('Sales Orders','Sales','["SO No","Customer","Customer PO","Product","Qty","Delivery","Status"]'::jsonb,'["SO No","Customer","Customer PO","Product","Qty","Delivery"]'::jsonb,'["Draft","Approved","Production Pending","Production Running","Ready to Dispatch","Completed"]'::jsonb,'Work Order'),
('Sales Quotations','Sales','["Quotation No","Customer","Enquiry","Amount","Status"]'::jsonb,'["Quotation No","Customer","Enquiry","Amount"]'::jsonb,'["Draft","Approval Pending","Approved","Sent","Accepted","Rejected"]'::jsonb,'Sales Orders'),
('Sales Return','Sales','["Return No","Invoice","Customer","Product","Qty","Decision"]'::jsonb,'["Return No","Invoice","Customer","Product","Qty"]'::jsonb,'["Inspection","Repair","Replace","Credit Note","Closed"]'::jsonb,'Credit Note'),
('Scrap Entry','Stores','["Scrap No","Work Order","Material","Qty","Reason","Status"]'::jsonb,'["Scrap No","Work Order","Material","Qty","Reason"]'::jsonb,'["Draft","Approved","Disposed"]'::jsonb,null),
('Seal Uploads','Shared','["Seal No","Product","Drawing / Document","Uploaded By","Status"]'::jsonb,'["Seal No","Product","Drawing / Document","Uploaded By"]'::jsonb,'["Draft","Verified","Approved"]'::jsonb,null),
('Service Invoice','Shared','["Invoice No","Vendor","Job No","Service","Amount","Invoice Date","Status"]'::jsonb,'["Invoice No","Vendor","Job No","Service","Amount","Invoice Date"]'::jsonb,'["Draft","Approval Pending","Approved","Posted"]'::jsonb,'Vendor Payments'),
('Settings','Administration','["Reference","Description"]'::jsonb,'["Reference"]'::jsonb,'[]'::jsonb,null),
('Shortage Stock','Stores','["Entry No","Item","Warehouse","Shortage Qty","Reason","Status"]'::jsonb,'["Entry No","Item","Warehouse","Shortage Qty","Reason"]'::jsonb,'["Identified","Approved","Adjusted"]'::jsonb,null),
('Stage Consumption','Production','["Consumption No","WO No","Operation","Item","Consumed Qty","Input No","Status"]'::jsonb,'["Consumption No","WO No","Operation","Item","Consumed Qty","Input No"]'::jsonb,'["Draft","Recorded","Approved","Posted"]'::jsonb,'Stage Receipt'),
('Stage Receipt','Production','["Receipt No","WO No","Operation","Machine","Good Qty","Reject Qty","Status"]'::jsonb,'["Receipt No","WO No","Operation","Machine","Good Qty","Reject Qty"]'::jsonb,'["Draft","Recorded","Inspected","Completed"]'::jsonb,'In-process QC'),
('Stock Adjustment','Stores','["Adjustment No","Item","Warehouse","Quantity Change","Reason","Date","Status"]'::jsonb,'["Adjustment No","Item","Warehouse","Quantity Change","Reason","Date"]'::jsonb,'["Draft","Approval Pending","Approved","Posted"]'::jsonb,null),
('Tally Link - Purchase','Purchase','["Voucher No","Purchase Invoice","Vendor","Amount","Sync Status"]'::jsonb,'["Voucher No","Purchase Invoice","Vendor","Amount"]'::jsonb,'["Pending","Synced","Failed"]'::jsonb,null),
('Tally Link - Sales','Sales','["Voucher No","Sales Invoice","Customer","Amount","Sync Status"]'::jsonb,'["Voucher No","Sales Invoice","Customer","Amount"]'::jsonb,'["Pending","Synced","Failed"]'::jsonb,null),
('Terminate Order','Shared','["Termination No","SO No","Customer","Reason","Date","Approved By","Status"]'::jsonb,'["Termination No","SO No","Customer","Reason","Date","Approved By"]'::jsonb,'["Draft","Approval Pending","Approved","Closed"]'::jsonb,null),
('Transactions','Shared','["Transaction Code","Transaction Name","Module","Approval Required","Status"]'::jsonb,'["Transaction Code","Transaction Name","Module","Approval Required"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Types','Shared','["Type Code","Type Name","Description"]'::jsonb,'["Type Code","Type Name","Description"]'::jsonb,'[]'::jsonb,null),
('UOM','Stores','["UOM Code","Unit Name","Symbol"]'::jsonb,'["UOM Code","Unit Name","Symbol"]'::jsonb,'[]'::jsonb,null),
('User Roles','Administration','["Role","Users","Description","Status"]'::jsonb,'["Role","Users","Description"]'::jsonb,'["Active","Inactive"]'::jsonb,null),
('Users','Administration','["User","Employee","Role","Department","Status"]'::jsonb,'["User","Employee","Role","Department"]'::jsonb,'["Active","Locked","Inactive"]'::jsonb,null),
('Vendor Payments','Purchase','["Payment No","Vendor","Invoice","Date","Amount","Status"]'::jsonb,'["Payment No","Vendor","Invoice","Date","Amount"]'::jsonb,'["Pending Approval","Approved","Paid"]'::jsonb,null),
('Vendor Price List','Purchase','["Price Ref","Vendor","Item","UOM","Rate","Valid Until","Status"]'::jsonb,'["Price Ref","Vendor","Item","UOM","Rate","Valid Until"]'::jsonb,'["Draft","Active","Expired"]'::jsonb,null),
('Vendors','Purchase','["Code","Name"]'::jsonb,'["Code","Name"]'::jsonb,'[]'::jsonb,null),
('Work Order','Production','["WO No","SO No","Product","Qty","Machine","Status"]'::jsonb,'["WO No","SO No","Product","Qty","Machine"]'::jsonb,'["Planned","Released","Running","QC Pending","Completed"]'::jsonb,'Material Request'),
('WorkCenter/Machine Master','Production','["Machine Code","Machine / Work Center","Department","Hourly Rate","Status"]'::jsonb,'["Machine Code","Machine / Work Center","Department","Hourly Rate"]'::jsonb,'["Available","Running","Maintenance"]'::jsonb,null) on conflict(page) do nothing;
insert into public.erp_admin_storage_map(storage_key,page,record_key_index,status_index) values
('dfab-erp-Activity Log','Activity Log',0,-1),
('dfab-erp-Asset Allocation','Asset Allocation',0,4),
('dfab-erp-BOM-Based Work Order','BOM-Based Work Order',0,6),
('dfab-erp-CRM Pipeline','CRM Pipeline',0,4),
('dfab-erp-Categories','Categories',0,-1),
('dfab-erp-Credit Note','Credit Note',0,5),
('dfab-erp-Customer Payments','Customer Payments',0,5),
('dfab-erp-Customer Price List','Customer Price List',0,6),
('dfab-erp-Daily Task Master','Daily Task Master',0,4),
('dfab-erp-Database Backup','Database Backup',0,-1),
('dfab-erp-Delivery Challan','Delivery Challan',0,6),
('dfab-erp-Delivery Channel','Delivery Channel',0,5),
('dfab-erp-Department Master','Department Master',0,4),
('dfab-erp-Dispatch Intimation','Dispatch Intimation',0,6),
('dfab-erp-Dispatch Schedule','Dispatch Schedule',0,6),
('dfab-erp-Excess Issue','Excess Issue',0,6),
('dfab-erp-Excess Stock','Excess Stock',0,5),
('dfab-erp-GRN','GRN',0,-1),
('dfab-erp-General Task','General Task',0,4),
('dfab-erp-HSN Master','HSN Master',0,-1),
('dfab-erp-Import Purchase','Import Purchase',0,7),
('dfab-erp-In-process QC','In-process QC',0,6),
('dfab-erp-Indent To Order','Indent To Order',0,-1),
('dfab-erp-Input to Production','Input to Production',0,6),
('dfab-erp-Instrument Master','Instrument Master',0,4),
('dfab-erp-Inward QC','Inward QC',0,5),
('dfab-erp-Inward Quality','Inward Quality',0,5),
('dfab-erp-Inward Quality Rejection','Inward Quality Rejection',0,5),
('dfab-erp-Job Order','Job Order',0,6),
('dfab-erp-Job Work Inward','Job Work Inward',0,5),
('dfab-erp-Job Work QC','Job Work QC',0,6),
('dfab-erp-Job Work Return DC','Job Work Return DC',0,5),
('dfab-erp-Jobwork Material Issue','Jobwork Material Issue',0,6),
('dfab-erp-Jobwork Material Receipt','Jobwork Material Receipt',0,6),
('dfab-erp-Kind Attention','Kind Attention',0,4),
('dfab-erp-Masters','Masters',0,4),
('dfab-erp-Material Issue','Material Issue',0,5),
('dfab-erp-Material Request','Material Request',0,4),
('dfab-erp-Material Reserve','Material Reserve',0,6),
('dfab-erp-Material Unreserved','Material Unreserved',0,6),
('dfab-erp-Menu','Menu',0,4),
('dfab-erp-Modules','Modules',0,3),
('dfab-erp-Opening Stock','Opening Stock',0,5),
('dfab-erp-Outsource Issue DC','Outsource Issue DC',0,5),
('dfab-erp-Outsource Receipt','Outsource Receipt',0,5),
('dfab-erp-Outward QC','Outward QC',0,5),
('dfab-erp-PO Number Details','PO Number Details',0,4),
('dfab-erp-Pending Approvals','Pending Approvals',0,4),
('dfab-erp-Pick Slip','Pick Slip',0,6),
('dfab-erp-Process Master','Process Master',0,3),
('dfab-erp-Process Price List','Process Price List',0,5),
('dfab-erp-Procurement Planning','Procurement Planning',0,6),
('dfab-erp-Procurement Schedule','Procurement Schedule',0,6),
('dfab-erp-Production BOM','Production BOM',0,3),
('dfab-erp-Production Output','Production Output',0,5),
('dfab-erp-Production Schedule','Production Schedule',0,6),
('dfab-erp-Proforma Invoice','Proforma Invoice',0,5),
('dfab-erp-Project Order','Project Order',0,6),
('dfab-erp-Project Planning','Project Planning',0,6),
('dfab-erp-Prospects','Prospects',0,3),
('dfab-erp-Purchase','Purchase',0,5),
('dfab-erp-Purchase Indents','Purchase Indents',0,5),
('dfab-erp-Purchase Orders','Purchase Orders',0,5),
('dfab-erp-Purchase Return','Purchase Return',0,6),
('dfab-erp-Put Away','Put Away',0,6),
('dfab-erp-Quality Master','Quality Master',0,4),
('dfab-erp-RM Inward and Outward','RM Inward and Outward',0,-1),
('dfab-erp-Rejection Note','Rejection Note',0,5),
('dfab-erp-Remark Master','Remark Master',0,3),
('dfab-erp-Reports','Reports',0,4),
('dfab-erp-Return to Store','Return to Store',0,6),
('dfab-erp-Role Permissions','Role Permissions',0,-1),
('dfab-erp-Route Card','Route Card',0,3),
('dfab-erp-Route Cards','Route Cards',0,5),
('dfab-erp-SO Number Details','SO Number Details',0,5),
('dfab-erp-Sales Enquiries','Sales Enquiries',0,5),
('dfab-erp-Sales Orders','Sales Orders',0,6),
('dfab-erp-Sales Quotations','Sales Quotations',0,4),
('dfab-erp-Sales Return','Sales Return',0,5),
('dfab-erp-Scrap Entry','Scrap Entry',0,5),
('dfab-erp-Seal Uploads','Seal Uploads',0,4),
('dfab-erp-Service Invoice','Service Invoice',0,6),
('dfab-erp-Settings','Settings',0,-1),
('dfab-erp-Shortage Stock','Shortage Stock',0,5),
('dfab-erp-Stage Consumption','Stage Consumption',0,6),
('dfab-erp-Stage Receipt','Stage Receipt',0,6),
('dfab-erp-Stock Adjustment','Stock Adjustment',0,6),
('dfab-erp-Tally Link - Purchase','Tally Link - Purchase',0,4),
('dfab-erp-Tally Link - Sales','Tally Link - Sales',0,4),
('dfab-erp-Terminate Order','Terminate Order',0,6),
('dfab-erp-Transactions','Transactions',0,4),
('dfab-erp-Types','Types',0,-1),
('dfab-erp-UOM','UOM',0,-1),
('dfab-erp-User Roles','User Roles',0,3),
('dfab-erp-Users','Users',0,4),
('dfab-erp-Vendor Payments','Vendor Payments',0,5),
('dfab-erp-Vendor Price List','Vendor Price List',0,6),
('dfab-erp-Work Order','Work Order',0,5),
('dfab-erp-WorkCenter/Machine Master','WorkCenter/Machine Master',0,4),
('dfab-erp-customers-v2','Customers',0,-1),
('dfab-erp-production-bom-v2','Production BOM',0,-1),
('dfab-erp-products-v3','Products',0,-1),
('dfab-erp-route-card-v2','Route Card',0,-1),
('dfab-erp-sales-invoices-v2','Sales Invoice',1,6),
('dfab-erp-vendors-v2','Vendors',0,-1),
('dfab-invoice-details-v1','Sales Invoice',0,-1),
('dfab-live-daily-tasks','Daily Task Master',0,-1),
('dfab-live-departments','Department Master',0,-1),
('dfab-live-machines','WorkCenter/Machine Master',0,-1),
('dfab-live-process','Process Master',0,-1),
('dfab-live-workcenters','WorkCenter/Machine Master',0,-1) on conflict(storage_key) do nothing;

-- Read-only report screens are permissions-controlled without creating duplicate tables.
insert into public.erp_admin_page_catalog(page,module_group,columns,fields,statuses,default_next) values
('Executed Sales Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Terminated Sales Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Project Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Project Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Executed Purchase Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Terminated Purchase Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Procurement Registers','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Planned Vs Work Orders','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Procurement Vs Planned','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Project Execution Vs Planned','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Dispatch Vs Planned','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Production Vs Planned','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Material Issue Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Jobwork Receipt Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('BOM Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Production Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Inward QC Status Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('In-process QC Status Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Outward QC Status Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Job Work QC Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Stock List','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Inventory Ageing','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Stock Valuation','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('WIP Stock','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Work-Order-Wise Order','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Work Order Status','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Daily Production Report','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Excess Consumption Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Short Consumption Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Consumption Against WO','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null) on conflict(page) do nothing;


-- Built-in statuses remain the default unless a published template overrides them.
alter table public.erp_admin_page_catalog add column if not exists default_gate_statuses text[] not null default '{}'::text[];
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Released']::text[] where page='BOM-Based Work Order';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Qualified','Quotation']::text[] where page='CRM Pipeline';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Posted']::text[] where page='Credit Note';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Dispatched','Delivered']::text[] where page='Delivery Challan';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Sent','Acknowledged']::text[] where page='Dispatch Intimation';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Ready','Dispatched']::text[] where page='Dispatch Schedule';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Issued']::text[] where page='Excess Issue';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Awaiting QC','Accepted']::text[] where page='GRN';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Received']::text[] where page='Import Purchase';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Open']::text[] where page='Indent To Order';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Issued','Consumed']::text[] where page='Input to Production';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Passed']::text[] where page='Inward QC';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Issued']::text[] where page='Job Order';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Accepted','Closed']::text[] where page='Job Work Inward';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Issued']::text[] where page='Jobwork Material Issue';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Accepted']::text[] where page='Jobwork Material Receipt';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Issued']::text[] where page='Material Issue';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Issued']::text[] where page='Material Request';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Reserved']::text[] where page='Material Reserve';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Dispatched','Part Received']::text[] where page='Outsource Issue DC';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Passed']::text[] where page='Outward QC';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Confirmed']::text[] where page='Pick Slip';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Released']::text[] where page='Procurement Planning';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Confirmed','Partially Delivered']::text[] where page='Procurement Schedule';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['QC Pending','Accepted']::text[] where page='Production Output';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Released','Running']::text[] where page='Production Schedule';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Running']::text[] where page='Project Order';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Active']::text[] where page='Project Planning';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Posted']::text[] where page='Purchase';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Converted']::text[] where page='Purchase Indents';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Sent','Partially Received']::text[] where page='Purchase Orders';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Running','Completed']::text[] where page='Route Cards';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['New','Under Review','Quoted']::text[] where page='Sales Enquiries';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Production Pending','Production Running']::text[] where page='Sales Orders';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Sent','Accepted']::text[] where page='Sales Quotations';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Credit Note']::text[] where page='Sales Return';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Posted']::text[] where page='Service Invoice';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Approved','Posted']::text[] where page='Stage Consumption';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Completed']::text[] where page='Stage Receipt';
update public.erp_admin_page_catalog set default_gate_statuses=ARRAY['Released','Running']::text[] where page='Work Order';

-- Existing navigation / reports are included in the access matrix.
insert into public.erp_admin_page_catalog(page,module_group,columns,fields,statuses,default_next) values
('Groups','Stores','["Group","Description"]'::jsonb,'["Group","Description"]'::jsonb,'[]'::jsonb,null),
('Regular Stock List','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Jobwork Inward Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Work Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Stock Ledger','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Stock Report','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Groupwise Stock Report','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Vendor Master List','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Vendor Payment History','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Customer Master List','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Product Rack List','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Vendor Price List Report','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('User Daily Task List','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Time Tracker','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Purchase Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Purchase Indent for order','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Purchase Indent For GR','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('GRN Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Inward QC Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('User Wise Transactions List','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Purchase Order to GRN','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Payables','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Purchase Invoice Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Purchase Invoice Itemwise Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Sales Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Enquiry Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Sales Order Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Sales Register Headerwise','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Sales Quotation Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Sales Order Created & Closed','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Sales Quotation Register Headerwise','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Sales Order Created & Closed Headerwise','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Credit Note Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Proforma Invoice Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Sales Order for Work Order','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Sales Order for Invoice','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Enquiry For QUotation','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Receivables','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('DC Register Headerwise','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('DC Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Work Order for Production Output','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Outsource DC to Receipt','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Outsource DC Register Headerwise','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Outsource DC Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Outsource DC Register Created to Closed','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Outsource Receipt Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Rejection Note Register','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null),
('Pending Jobwork Inward for Quality','Reports','["Reference","Status"]'::jsonb,'[]'::jsonb,'[]'::jsonb,null) on conflict(page) do nothing;
insert into public.erp_admin_storage_map(storage_key,page,record_key_index,status_index)
values ('dfab-erp-product-groups-v2','Groups',0,-1) on conflict(storage_key) do nothing;

-- Staff departments are created only when missing. Existing departments survive.
insert into public.erp_departments(organization_id,code,name)
select o.id,x.code,x.name from public.erp_organizations o
cross join (values
 ('RND','R&D / Innovation'),('SALES','Sales'),('MARKETING','Marketing'),
 ('PURCHASE','Purchase'),('STORES','Stores'),('PRODUCTION','Production'),
 ('QUALITY','Quality Control'),('OUTSOURCING','Outsourcing / Job Work'),
 ('ACCOUNTS','Accounts'),('NPD','New Product Development'),('ADMIN','Administration')
) as x(code,name) where o.code='DFAB'
on conflict (organization_id,code) do nothing;

-- No direct client writes to the admin control data. All mutations use audited RPCs.
alter table public.erp_admin_page_catalog enable row level security;
alter table public.erp_admin_module_rights enable row level security;
alter table public.erp_admin_storage_map enable row level security;
alter table public.erp_admin_flow_templates enable row level security;
alter table public.erp_admin_flow_edges enable row level security;
alter table public.erp_admin_events enable row level security;
revoke all on public.erp_admin_page_catalog,public.erp_admin_module_rights,
  public.erp_admin_storage_map,public.erp_admin_flow_templates,
  public.erp_admin_flow_edges,public.erp_admin_events from anon,authenticated;

-- Re-scope the legacy role helper to current active company; a role from another
-- organization must never grant permissions to this tenant.
create or replace function public.erp_has_permission(p_permission text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.erp_user_roles ur
    join public.erp_roles r on r.id=ur.role_id and r.active
    join public.erp_role_permissions rp on rp.role_id=r.id
    join public.erp_profiles p on p.user_id=ur.user_id and p.active and p.organization_id=r.organization_id
    where ur.user_id=auth.uid() and rp.permission_code=p_permission
      and r.organization_id=public.erp_current_org_id()
  );
$$;

create or replace function public.erp_admin_is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select auth.uid() is not null and public.erp_current_org_id() is not null
    and exists (
      select 1 from public.erp_user_roles ur
      join public.erp_roles r on r.id=ur.role_id
      where ur.user_id=auth.uid() and r.organization_id=public.erp_current_org_id()
      and r.code='ADMIN' and r.active
    ) and public.erp_has_permission('SYSTEM.ADMIN');
$$;

create or replace function public.erp_admin_can_page(p_page text,p_action text default 'view')
returns boolean language sql stable security definer set search_path=public as $$
 select case
  when auth.uid() is null or public.erp_current_org_id() is null then false
  when public.erp_admin_is_admin() then true
  when p_action not in ('view','create','edit','delete','approve','export') then false
  else exists (
    select 1 from public.erp_user_roles ur
    join public.erp_roles r on r.id=ur.role_id and r.active and r.organization_id=public.erp_current_org_id()
    join public.erp_admin_module_rights m on m.role_id=r.id and m.page=p_page
    where ur.user_id=auth.uid() and case p_action
      when 'view' then m.can_view
      when 'create' then m.can_create
      when 'edit' then m.can_edit
      when 'delete' then m.can_delete
      when 'approve' then m.can_approve
      when 'export' then m.can_export else false end
  )
 end;
$$;

create or replace function public.erp_admin_can_key(p_storage_key text,p_action text default 'view')
returns boolean language plpgsql stable security definer set search_path=public as $$
declare v_page text;
begin
 if public.erp_admin_is_admin() then return true; end if;
 if p_storage_key='dfab-workflow-links-v1' then
   return public.erp_has_permission(case when p_action='view' then 'ERP.VIEW' else 'ERP.EDIT' end);
 end if;
 select page into v_page from public.erp_admin_storage_map where storage_key=p_storage_key;
 return v_page is not null and public.erp_admin_can_page(v_page,p_action);
end; $$;

create or replace function public.erp_admin_event(p_event text,p_target text,p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path=public as $$
begin
 insert into public.erp_admin_events(organization_id,actor_id,event,target,details)
 values(public.erp_current_org_id(),auth.uid(),p_event,p_target,coalesce(p_details,'{}'::jsonb));
end; $$;

create or replace function public.erp_admin_my_access()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();
begin
 if auth.uid() is null or v_org is null then
   return jsonb_build_object('enabled',false,'is_admin',false,'rights','{}'::jsonb);
 end if;
 return jsonb_build_object(
 'enabled',public.erp_has_permission('ERP.VIEW'), 'is_admin',public.erp_admin_is_admin(),
 'user_id',auth.uid(),
 'profile',(select to_jsonb(p) from public.erp_profiles p where p.user_id=auth.uid()),
 'roles',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'code',r.code,'name',r.name))
                  from public.erp_user_roles ur join public.erp_roles r on r.id=ur.role_id and r.active
                  where ur.user_id=auth.uid() and r.organization_id=v_org),'[]'::jsonb),
 'rights',coalesce((select jsonb_object_agg(z.page,z.rights) from (
   select m.page,jsonb_build_object('view',bool_or(m.can_view),'create',bool_or(m.can_create),
   'edit',bool_or(m.can_edit),'delete',bool_or(m.can_delete),'approve',bool_or(m.can_approve),
   'export',bool_or(m.can_export)) rights
   from public.erp_user_roles ur join public.erp_roles r on r.id=ur.role_id and r.active
   join public.erp_admin_module_rights m on m.role_id=r.id
   where ur.user_id=auth.uid() and r.organization_id=v_org group by m.page
 ) z),'{}'::jsonb)
 );
end; $$;

create or replace function public.erp_admin_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();
begin
 if not public.erp_admin_is_admin() then raise exception 'Administrator access required' using errcode='42501'; end if;
 return jsonb_build_object(
  'catalog',coalesce((select jsonb_agg(to_jsonb(c) order by c.module_group,c.page) from public.erp_admin_page_catalog c where c.active),'[]'::jsonb),
  'storage',coalesce((select jsonb_agg(to_jsonb(m) order by m.storage_key) from public.erp_admin_storage_map m),'[]'::jsonb),
  'departments',coalesce((select jsonb_agg(to_jsonb(d) order by d.name) from public.erp_departments d where d.organization_id=v_org),'[]'::jsonb),
  'roles',coalesce((select jsonb_agg(to_jsonb(r) order by r.code) from public.erp_roles r where r.organization_id=v_org),'[]'::jsonb),
  'rights',coalesce((select jsonb_agg(to_jsonb(m)) from public.erp_admin_module_rights m join public.erp_roles r on r.id=m.role_id where r.organization_id=v_org),'[]'::jsonb),
  'users',coalesce((select jsonb_agg(to_jsonb(p) order by p.display_name) from public.erp_profiles p where p.organization_id=v_org),'[]'::jsonb),
  'user_roles',coalesce((select jsonb_agg(jsonb_build_object('user_id',ur.user_id,'role_id',ur.role_id)) from public.erp_user_roles ur join public.erp_roles r on r.id=ur.role_id where r.organization_id=v_org),'[]'::jsonb),
  'templates',coalesce((select jsonb_agg(to_jsonb(t) order by t.created_at desc) from public.erp_admin_flow_templates t where t.organization_id=v_org),'[]'::jsonb),
  'edges',coalesce((select jsonb_agg(to_jsonb(e)) from public.erp_admin_flow_edges e join public.erp_admin_flow_templates t on t.id=e.template_id where t.organization_id=v_org),'[]'::jsonb),
  'events',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from (select * from public.erp_admin_events where organization_id=v_org order by created_at desc limit 120) a),'[]'::jsonb)
 );
end; $$;

create or replace function public.erp_admin_active_workflow()
returns jsonb language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(jsonb_build_object(
   'source_page',e.source_page,'target_page',e.target_page,
   'gate_statuses',e.gate_statuses,'field_map',e.field_map)),'[]'::jsonb)
 from public.erp_admin_flow_edges e
 join public.erp_admin_flow_templates t on t.id=e.template_id
 where t.organization_id=public.erp_current_org_id() and t.status='published'
   and public.erp_admin_can_page(e.source_page,'view')
   and public.erp_admin_can_page(e.target_page,'view');
$$;

create or replace function public.erp_admin_save_department(
 p_id uuid,p_code text,p_name text,p_cost_center text default null,p_active boolean default true)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_id uuid;
begin
 if not public.erp_admin_is_admin() then raise exception 'Administrator only' using errcode='42501'; end if;
 p_code:=upper(trim(coalesce(p_code,'')));p_name:=trim(coalesce(p_name,''));
 if p_code !~ '^[A-Z0-9_-]{2,24}$' or length(p_name) not between 2 and 100 then
   raise exception 'Department requires a 2–24 character code and valid name';end if;
 if p_id is null then
   insert into public.erp_departments(organization_id,code,name,cost_center,active)
   values(v_org,p_code,p_name,nullif(trim(p_cost_center),''),coalesce(p_active,true)) returning id into v_id;
 else
   if not coalesce(p_active,true) and exists(select 1 from public.erp_profiles where organization_id=v_org and department_id=p_id and active) then
     raise exception 'Move or deactivate department staff before disabling this department';end if;
   update public.erp_departments set code=p_code,name=p_name,cost_center=nullif(trim(p_cost_center),''),active=coalesce(p_active,true)
   where id=p_id and organization_id=v_org returning id into v_id;
   if v_id is null then raise exception 'Department not found' using errcode='42501';end if;
 end if;
 perform public.erp_admin_event('DEPARTMENT_SAVED',v_id::text,jsonb_build_object('code',p_code,'active',p_active));
 return v_id;
end; $$;

create or replace function public.erp_admin_save_role(
 p_id uuid,p_code text,p_name text,p_description text,p_active boolean,p_rights jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_id uuid;v_right jsonb;v_page text;v_perm text;
begin
 if not public.erp_admin_is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
 p_code:=upper(trim(coalesce(p_code,'')));p_name:=trim(coalesce(p_name,''));
 if p_code !~ '^[A-Z0-9_-]{2,32}$' or length(p_name) not between 3 and 100
    or jsonb_typeof(p_rights) <> 'array' or jsonb_array_length(p_rights)>200 then
    raise exception 'Invalid role code, name or access matrix';end if;
 if p_code='ADMIN' then raise exception 'Administrator role is system-managed';end if;
 if p_id is null then
    if p_code='ADMIN' then raise exception 'Administrator role is system-managed';end if;
    insert into public.erp_roles(organization_id,code,name,description,active)
    values(v_org,p_code,p_name,left(coalesce(p_description,''),500),coalesce(p_active,true)) returning id into v_id;
 else
    update public.erp_roles set code=p_code,name=p_name,description=left(coalesce(p_description,''),500),active=coalesce(p_active,true)
    where id=p_id and organization_id=v_org and not system_role returning id into v_id;
    if v_id is null then raise exception 'System roles cannot be changed. Create a departmental role instead.';end if;
 end if;
 delete from public.erp_admin_module_rights where role_id=v_id;
 for v_right in select value from jsonb_array_elements(p_rights) loop
    v_page:=v_right->>'page';
    if v_page is null or not exists(select 1 from public.erp_admin_page_catalog where page=v_page and active) then
      raise exception 'Unknown ERP module: %',v_page;
    end if;
    insert into public.erp_admin_module_rights(role_id,page,can_view,can_create,can_edit,can_delete,can_approve,can_export)
    values(v_id,v_page,coalesce((v_right->>'view')::boolean,false),coalesce((v_right->>'create')::boolean,false),
      coalesce((v_right->>'edit')::boolean,false),coalesce((v_right->>'delete')::boolean,false),
      coalesce((v_right->>'approve')::boolean,false),coalesce((v_right->>'export')::boolean,false))
    on conflict (role_id,page) do update set can_view=excluded.can_view,can_create=excluded.can_create,
      can_edit=excluded.can_edit,can_delete=excluded.can_delete,can_approve=excluded.can_approve,can_export=excluded.can_export;
 end loop;
 -- ERP.VIEW gates sign-in; ERP.EDIT is required by the legacy CAS trigger.
 delete from public.erp_role_permissions where role_id=v_id;
 insert into public.erp_role_permissions(role_id,permission_code) values(v_id,'ERP.VIEW'),(v_id,'ERP.EXPORT'),(v_id,'ERP.EDIT');
 perform public.erp_admin_event('ROLE_SAVED',v_id::text,jsonb_build_object('code',p_code,'permissions',jsonb_array_length(p_rights)));
 return v_id;
end; $$;

create or replace function public.erp_admin_save_user(
 p_user_id uuid,p_department_id uuid,p_display_name text,p_active boolean,p_role_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_role uuid;v_current_admin boolean;v_new_admin boolean;
begin
 if not public.erp_admin_is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
 if not exists(select 1 from public.erp_profiles where user_id=p_user_id and organization_id=v_org) then
   raise exception 'User must belong to this ERP organization' using errcode='42501';end if;
 if length(trim(coalesce(p_display_name,''))) not between 2 and 100 then raise exception 'Enter a valid employee name';end if;
 if p_department_id is not null and not exists(select 1 from public.erp_departments where id=p_department_id and organization_id=v_org and active) then
    raise exception 'Department is not active in this organization';end if;
 if cardinality(coalesce(p_role_ids,'{}'::uuid[]))>20 then raise exception 'Too many roles';end if;
 for v_role in select distinct unnest(coalesce(p_role_ids,'{}'::uuid[])) loop
   if not exists(select 1 from public.erp_roles where id=v_role and organization_id=v_org and active) then
      raise exception 'Role does not belong to this organization';end if;
 end loop;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||':admin-users',0));
 select exists(select 1 from public.erp_user_roles ur join public.erp_roles r on r.id=ur.role_id
   where ur.user_id=p_user_id and r.organization_id=v_org and r.code='ADMIN') into v_current_admin;
 select exists(select 1 from public.erp_roles r where r.id=any(coalesce(p_role_ids,'{}'::uuid[])) and r.organization_id=v_org and r.code='ADMIN') into v_new_admin;
 if v_current_admin and (not coalesce(p_active,true) or not v_new_admin) and not exists(
    select 1 from public.erp_profiles p join public.erp_user_roles ur on ur.user_id=p.user_id
    join public.erp_roles r on r.id=ur.role_id and r.code='ADMIN' and r.active
    where p.organization_id=v_org and p.active and p.user_id <> p_user_id
  ) then raise exception 'The last active administrator cannot be removed or disabled';end if;
 if coalesce(p_active,true) and cardinality(coalesce(p_role_ids,'{}'::uuid[]))=0 then
    raise exception 'Choose at least one role for an active employee';end if;
 update public.erp_profiles set department_id=p_department_id,display_name=trim(p_display_name),active=coalesce(p_active,true)
 where user_id=p_user_id and organization_id=v_org;
 delete from public.erp_user_roles where user_id=p_user_id and role_id in (select id from public.erp_roles where organization_id=v_org);
 insert into public.erp_user_roles(user_id,role_id)
 select p_user_id,unnest(coalesce(p_role_ids,'{}'::uuid[])) on conflict do nothing;
 perform public.erp_admin_event('USER_ACCESS_SAVED',p_user_id::text,jsonb_build_object('department',p_department_id,'active',p_active,'roles',to_jsonb(p_role_ids)));
end; $$;

create or replace function public.erp_admin_save_template(
 p_id uuid,p_name text,p_description text,p_edges jsonb,p_expected_version integer default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_id uuid;v_item jsonb;v_source text;v_target text;v_gates text[];v_field_map jsonb;v_cyc boolean;
begin
 if not public.erp_admin_is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
 if length(trim(coalesce(p_name,''))) not between 3 and 100 or jsonb_typeof(p_edges)<>'array'
   or jsonb_array_length(p_edges) not between 1 and 100 then
   raise exception 'Template name and at least one connection are required (maximum 100)';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||':flow-template',0));
 if p_id is null then
   insert into public.erp_admin_flow_templates(organization_id,name,description,created_by,updated_by)
   values(v_org,trim(p_name),left(coalesce(p_description,''),500),auth.uid(),auth.uid()) returning id into v_id;
 else
   update public.erp_admin_flow_templates set name=trim(p_name),description=left(coalesce(p_description,''),500),
    updated_at=now(),updated_by=auth.uid(),version=version+1
   where id=p_id and organization_id=v_org and status='draft' and version=p_expected_version returning id into v_id;
   if v_id is null then raise exception 'Template was published or changed. Reload and create a new draft.' using errcode='40001';end if;
   delete from public.erp_admin_flow_edges where template_id=v_id;
 end if;
 for v_item in select value from jsonb_array_elements(p_edges) loop
   v_source:=v_item->>'source_page';v_target:=v_item->>'target_page';
   v_field_map:=coalesce(v_item->'field_map','{}'::jsonb);
   if v_source is null or v_target is null or v_source=v_target or not exists(select 1 from public.erp_admin_page_catalog where page=v_source and active and jsonb_array_length(fields)>0)
     or not exists(select 1 from public.erp_admin_page_catalog where page=v_target and active and jsonb_array_length(fields)>0)
     or jsonb_typeof(v_field_map)<>'object' or (select count(*) from jsonb_object_keys(v_field_map))>20 then
       raise exception 'Invalid workflow step or field mapping: % → %',v_source,v_target;
   end if;
   if exists(select 1 from jsonb_each_text(v_field_map) f
      where not exists(select 1 from public.erp_admin_page_catalog c where c.page=v_source and c.columns ? f.value)
         or not exists(select 1 from public.erp_admin_page_catalog c where c.page=v_target and c.fields ? f.key)) then
      raise exception 'A field mapping references a field missing from its source or destination';end if;
   if jsonb_typeof(coalesce(v_item->'gate_statuses','[]'::jsonb)) <> 'array'
      or jsonb_array_length(coalesce(v_item->'gate_statuses','[]'::jsonb))>20 then raise exception 'Invalid gate statuses';end if;
   if exists(select 1 from jsonb_array_elements_text(coalesce(v_item->'gate_statuses','[]'::jsonb)) g
     where not exists(select 1 from public.erp_admin_page_catalog c where c.page=v_source and c.statuses ? g.value)) then
     raise exception 'A gate status does not exist in the source document';end if;
   select coalesce(array_agg(value),'{}'::text[]) into v_gates from jsonb_array_elements_text(coalesce(v_item->'gate_statuses','[]'::jsonb));
   insert into public.erp_admin_flow_edges(template_id,source_page,target_page,gate_statuses,field_map)
   values(v_id,v_source,v_target,v_gates,v_field_map);
 end loop;
 with recursive walk(source_page,target_page,path,cycle) as (
  select source_page,target_page,array[source_page,target_page],false from public.erp_admin_flow_edges where template_id=v_id
  union all
  select w.source_page,e.target_page,w.path||e.target_page,e.target_page=any(w.path)
  from walk w join public.erp_admin_flow_edges e on e.template_id=v_id and e.source_page=w.target_page
  where not w.cycle and array_length(w.path,1)<102
 ) select exists(select 1 from walk where cycle) into v_cyc;
 if v_cyc then raise exception 'Workflow contains a cycle; connect processes in a forward sequence';end if;
 perform public.erp_admin_event('TEMPLATE_SAVED',v_id::text,jsonb_build_object('name',p_name,'edges',jsonb_array_length(p_edges)));
 return v_id;
end; $$;

create or replace function public.erp_admin_publish_template(p_id uuid,p_expected_version integer)
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_id uuid;
begin
 if not public.erp_admin_is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||':flow-template',0));
 select id into v_id from public.erp_admin_flow_templates where id=p_id and organization_id=v_org
   and status='draft' and version=p_expected_version for update;
 if v_id is null then raise exception 'Template changed or was already published; reload' using errcode='40001';end if;
 if not exists(select 1 from public.erp_admin_flow_edges where template_id=v_id) then raise exception 'Cannot publish an empty workflow';end if;
 update public.erp_admin_flow_templates set status='draft',version=version+1,updated_at=now() where organization_id=v_org and status='published';
 update public.erp_admin_flow_templates set status='published',version=version+1,updated_by=auth.uid(),updated_at=now() where id=v_id;
 perform public.erp_admin_event('WORKFLOW_PUBLISHED',v_id::text);
end; $$;

create or replace function public.erp_admin_reset_workflow()
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();
begin
 if not public.erp_admin_is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||':flow-template',0));
 update public.erp_admin_flow_templates set status='draft',version=version+1 where organization_id=v_org and status='published';
 perform public.erp_admin_event('WORKFLOW_RESET','Built-in workflows');
end; $$;

create or replace function public.erp_admin_map_storage(p_key text,p_page text,p_key_index integer,p_status_index integer)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.erp_admin_is_admin() then raise exception 'Administrator only' using errcode='42501';end if;
 if p_key is null or p_key !~ '^dfab-[a-zA-Z0-9 /_.-]+$' or p_key='dfab-workflow-links-v1'
    or p_key_index not between 0 and 24 or p_status_index not between -1 and 24 then raise exception 'Invalid section or column index';end if;
 if not exists(select 1 from public.erp_admin_page_catalog where page=p_page and active) then raise exception 'Unknown ERP module';end if;
 insert into public.erp_admin_storage_map(storage_key,page,record_key_index,status_index)
 values(p_key,p_page,p_key_index,p_status_index)
 on conflict(storage_key) do update set page=excluded.page,record_key_index=excluded.record_key_index,status_index=excluded.status_index;
 perform public.erp_admin_event('STORAGE_MAPPED',p_key,jsonb_build_object('page',p_page,'key_index',p_key_index,'status_index',p_status_index));
end; $$;

-- A profile must never be able to grant itself a different department,
-- organization or ADMIN role through the old self-update policy.
drop policy if exists erp_profile_self_update on public.erp_profiles;
revoke insert,update,delete on public.erp_profiles from authenticated;
revoke insert,update,delete on public.erp_user_roles,public.erp_roles,public.erp_role_permissions,public.erp_departments from authenticated;

-- Runtime configuration and UI-state reads are restricted by assigned modules.
create or replace function public.erp_get_ui_state()
returns table(storage_key text,payload jsonb)
language sql stable security definer set search_path=public as $$
  select s.storage_key,s.payload from public.erp_ui_state s
  where s.organization_id=public.erp_current_org_id()
    and public.erp_has_permission('ERP.VIEW')
    and public.erp_admin_can_key(s.storage_key,'view')
  order by s.storage_key;
$$;
drop policy if exists erp_org_select on public.erp_ui_state;
create policy erp_org_select on public.erp_ui_state for select to authenticated using (
 organization_id=public.erp_current_org_id() and public.erp_admin_can_key(storage_key,'view')
);
drop policy if exists erp_org_select on public.erp_ui_records;
create policy erp_org_select on public.erp_ui_records for select to authenticated using (
 organization_id=public.erp_current_org_id() and public.erp_admin_can_key(storage_key,'view')
);

-- No client may bypass the compare-and-swap write contract through legacy RPCs.
revoke execute on function public.erp_put_ui_state(text,jsonb) from PUBLIC,anon,authenticated;
revoke execute on function public.erp_delete_ui_state(text) from PUBLIC,anon,authenticated;

-- Enforce module permissions, create/edit/delete operations and status changes
-- even for legacy JSON-array UI collections. This does NOT grant missing
-- row-level accounting or inventory transaction semantics; those require
-- their own normalized posting services.
create or replace function public.erp_admin_assert_change(p_key text,p_old jsonb,p_new jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_page text;v_key_index integer;v_status_index integer;v_added boolean:=false;v_removed boolean:=false;
        v_modified boolean:=false;v_approval boolean:=false;v_bad boolean:=false;
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
 if p_old is null then
   if not public.erp_admin_can_page(v_page,'create') then raise exception 'Create permission required on %',v_page using errcode='42501';end if;
   return;
 end if;
 if p_new is null then
   if not public.erp_admin_can_page(v_page,'delete') then raise exception 'Delete permission required on %',v_page using errcode='42501';end if;
   return;
 end if;
 if jsonb_typeof(p_old)='array' and jsonb_typeof(p_new)='array' then
   -- Arrays must have stable unique reference keys for permission-safe diffing.
   select exists(select 1 from jsonb_array_elements(p_old) r(value) where jsonb_typeof(r.value) not in ('array','object') or nullif(case when jsonb_typeof(r.value)='object' then coalesce(r.value->>'code',r.value->>'name',r.value->>'id') else r.value->>v_key_index end,'') is null)
     or exists(select 1 from jsonb_array_elements(p_new) r(value) where jsonb_typeof(r.value) not in ('array','object') or nullif(case when jsonb_typeof(r.value)='object' then coalesce(r.value->>'code',r.value->>'name',r.value->>'id') else r.value->>v_key_index end,'') is null)
     into v_bad;
   if not v_bad then
     select exists(select 1 from (select case when jsonb_typeof(r.value)='object' then coalesce(r.value->>'code',r.value->>'name',r.value->>'id') else r.value->>v_key_index end k from jsonb_array_elements(p_old) r(value) group by 1 having count(*)>1) d)
       or exists(select 1 from (select case when jsonb_typeof(r.value)='object' then coalesce(r.value->>'code',r.value->>'name',r.value->>'id') else r.value->>v_key_index end k from jsonb_array_elements(p_new) r(value) group by 1 having count(*)>1) d)
       into v_bad;
   end if;
   if v_bad then raise exception 'This collection needs unique reference IDs before non-admin editing. Ask an administrator to repair it.' using errcode='23505';end if;
   with old_rows as (select case when jsonb_typeof(r.value)='object' then coalesce(r.value->>'code',r.value->>'name',r.value->>'id') else r.value->>v_key_index end k,r.value val from jsonb_array_elements(p_old) r(value)),
        new_rows as (select case when jsonb_typeof(r.value)='object' then coalesce(r.value->>'code',r.value->>'name',r.value->>'id') else r.value->>v_key_index end k,r.value val from jsonb_array_elements(p_new) r(value)),
        diff as (select o.val oldval,n.val newval from old_rows o full join new_rows n using(k))
   select coalesce(bool_or(oldval is null),false),coalesce(bool_or(newval is null),false),
       coalesce(bool_or(oldval is not null and newval is not null and oldval<>newval),false),
       coalesce(bool_or(v_status_index>=0 and oldval is not null and newval is not null
         and oldval->v_status_index is distinct from newval->v_status_index),false)
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
 if TG_OP='INSERT' then perform public.erp_admin_assert_change(v_key,null,NEW.payload);return NEW;end if;
 if TG_OP='DELETE' then perform public.erp_admin_assert_change(v_key,OLD.payload,null);return OLD;end if;
 if NEW.organization_id<>OLD.organization_id or NEW.storage_key<>OLD.storage_key then raise exception 'ERP section identity cannot be changed';end if;
 perform public.erp_admin_assert_change(v_key,OLD.payload,NEW.payload);
 return NEW;
end; $$;

-- Re-validate related document/link changes on the database server. A caller
-- cannot forge a link using a single-section JSON update or a partial batch.
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
   select payload into v_source_rows from public.erp_ui_state where organization_id=v_org and storage_key=v_source_key;
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
   if jsonb_typeof(v_target_payload)<>'array' or jsonb_array_length(v_target_payload)<>jsonb_array_length(coalesce(v_target_old,'[]'::jsonb))+1
     or v_target_payload->0->>(case when v_to='Sales Invoice' then 1 else 0 end)<>v_created then
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

-- Native admin functions are callable only by authenticated identities; all
-- authorization decisions happen inside the security-definer function.
revoke all on function public.erp_admin_is_admin() from PUBLIC;
revoke all on function public.erp_admin_can_page(text,text) from PUBLIC;
revoke all on function public.erp_admin_can_key(text,text) from PUBLIC;
revoke all on function public.erp_admin_event(text,text,jsonb) from PUBLIC;
revoke all on function public.erp_admin_assert_change(text,jsonb,jsonb) from PUBLIC;
revoke all on function public.erp_admin_my_access() from PUBLIC;
revoke all on function public.erp_admin_dashboard() from PUBLIC;
revoke all on function public.erp_admin_active_workflow() from PUBLIC;
revoke all on function public.erp_admin_save_department(uuid,text,text,text,boolean) from PUBLIC;
revoke all on function public.erp_admin_save_role(uuid,text,text,text,boolean,jsonb) from PUBLIC;
revoke all on function public.erp_admin_save_user(uuid,uuid,text,boolean,uuid[]) from PUBLIC;
revoke all on function public.erp_admin_save_template(uuid,text,text,jsonb,integer) from PUBLIC;
revoke all on function public.erp_admin_publish_template(uuid,integer) from PUBLIC;
revoke all on function public.erp_admin_reset_workflow() from PUBLIC;
revoke all on function public.erp_admin_map_storage(text,text,integer,integer) from PUBLIC;

grant execute on function public.erp_admin_is_admin(), public.erp_admin_can_page(text,text),
 public.erp_admin_can_key(text,text), public.erp_admin_my_access(),
 public.erp_admin_dashboard(), public.erp_admin_active_workflow(),
 public.erp_admin_save_department(uuid,text,text,text,boolean),
 public.erp_admin_save_role(uuid,text,text,text,boolean,jsonb),
 public.erp_admin_save_user(uuid,uuid,text,boolean,uuid[]),
 public.erp_admin_save_template(uuid,text,text,jsonb,integer),
 public.erp_admin_publish_template(uuid,integer), public.erp_admin_reset_workflow(),
 public.erp_admin_map_storage(text,text,integer,integer)
to authenticated;

-- Refresh PostgREST function metadata after the migration is committed.
notify pgrst, 'reload schema';


-- COMPONENT: ERP_ADMIN_OPERATIONS_V2
-- DFAB OneERP Admin Control — safe management operations (additive release v2).
-- REQUIRED FIRST: DFAB_ERP_PRODUCTION.sql, ERP_FLOW_INTEGRITY_UPGRADE.sql,
-- ERP_PRODUCTION_GUARDRAILS.sql, ERP_ADMIN_CONTROL.sql (in their documented order).
-- Requires an authenticated organization Administrator. No anonymous write path.
-- Apply to staging and run ERP_ADMIN_OPERATIONS_V2_CHECKS.sql before production.

create or replace function public.erp_admin_delete_template(p_id uuid,p_expected_version integer)
returns void language plpgsql security definer set search_path=public as $$
declare v_template public.erp_admin_flow_templates%rowtype;
begin
  if not public.erp_admin_is_admin() then
    raise exception 'Administrator required' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(public.erp_current_org_id()::text||':flow-template',0));
  select * into v_template from public.erp_admin_flow_templates
  where id=p_id and organization_id=public.erp_current_org_id() for update;
  if not found then raise exception 'Workflow template not found' using errcode='P0002'; end if;
  if v_template.status<>'draft' then
    raise exception 'Published workflows cannot be deleted. Reset the live flow first' using errcode='42501';
  end if;
  if p_expected_version is distinct from v_template.version then
    raise exception 'Workflow changed in another session. Refresh before deleting' using errcode='40001';
  end if;
  delete from public.erp_admin_flow_templates where id=p_id and organization_id=public.erp_current_org_id();
  perform public.erp_admin_event('TEMPLATE_DELETED',p_id::text,jsonb_build_object('name',v_template.name,'version',v_template.version));
end; $$;

create or replace function public.erp_admin_delete_department(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_department public.erp_departments%rowtype;
begin
  if not public.erp_admin_is_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
  select * into v_department from public.erp_departments
  where id=p_id and organization_id=public.erp_current_org_id() for update;
  if not found then raise exception 'Department not found' using errcode='P0002'; end if;
  if exists(select 1 from public.erp_profiles where department_id=p_id and organization_id=public.erp_current_org_id()) then
    raise exception 'Department has employee records. Reassign employees first, or set the department inactive' using errcode='23503';
  end if;
  begin
    delete from public.erp_departments where id=p_id and organization_id=public.erp_current_org_id();
  exception when foreign_key_violation then
    raise exception 'Department is referenced by ERP records. Deactivate it instead of deleting' using errcode='23503';
  end;
  perform public.erp_admin_event('DEPARTMENT_DELETED',p_id::text,jsonb_build_object('code',v_department.code,'name',v_department.name));
end; $$;

create or replace function public.erp_admin_delete_role(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_role public.erp_roles%rowtype;
begin
  if not public.erp_admin_is_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
  select * into v_role from public.erp_roles
  where id=p_id and organization_id=public.erp_current_org_id() for update;
  if not found then raise exception 'Access role not found' using errcode='P0002'; end if;
  if v_role.system_role or v_role.code='ADMIN' then
    raise exception 'Protected ERP system roles cannot be deleted' using errcode='42501';
  end if;
  if exists(select 1 from public.erp_user_roles where role_id=p_id) then
    raise exception 'Role is assigned to employees. Reassign them before deletion' using errcode='23503';
  end if;
  begin
    delete from public.erp_admin_module_rights where role_id=p_id;
    delete from public.erp_role_permissions where role_id=p_id;
    delete from public.erp_roles where id=p_id and organization_id=public.erp_current_org_id();
  exception when foreign_key_violation then
    raise exception 'Role is referenced by other ERP records; deactivate it instead' using errcode='23503';
  end;
  perform public.erp_admin_event('ROLE_DELETED',p_id::text,jsonb_build_object('code',v_role.code,'name',v_role.name));
end; $$;

create or replace function public.erp_admin_unmap_storage(p_key text)
returns void language plpgsql security definer set search_path=public as $$
declare v_page text;
begin
  if not public.erp_admin_is_admin() then raise exception 'Administrator required' using errcode='42501'; end if;
  if p_key is null or p_key='dfab-workflow-links-v1' then
    raise exception 'Core workflow storage cannot be removed' using errcode='42501';
  end if;
  select page into v_page from public.erp_admin_storage_map where storage_key=p_key for update;
  if v_page is null then raise exception 'Storage mapping not found' using errcode='P0002';end if;
  -- Storage mapping is GLOBAL. Never unmap while *any* organization has data in that section.
  if exists(select 1 from public.erp_ui_state where storage_key=p_key) or
     exists(select 1 from public.erp_ui_records where storage_key=p_key) then
    raise exception 'This section contains ERP data. Re-map it; do not remove its access policy' using errcode='23503';
  end if;
  delete from public.erp_admin_storage_map where storage_key=p_key;
  perform public.erp_admin_event('STORAGE_UNMAPPED',p_key,jsonb_build_object('previous_page',v_page));
end; $$;

-- PostgreSQL grants are explicit: authenticated users can call the functions,
-- but each one re-checks administrator privileges inside the database.
revoke all on function public.erp_admin_delete_template(uuid,integer) from PUBLIC,anon,authenticated;
revoke all on function public.erp_admin_delete_department(uuid) from PUBLIC,anon,authenticated;
revoke all on function public.erp_admin_delete_role(uuid) from PUBLIC,anon,authenticated;
revoke all on function public.erp_admin_unmap_storage(text) from PUBLIC,anon,authenticated;
grant execute on function public.erp_admin_delete_template(uuid,integer),
 public.erp_admin_delete_department(uuid),public.erp_admin_delete_role(uuid),
 public.erp_admin_unmap_storage(text) to authenticated;

notify pgrst, 'reload schema';


-- COMPONENT: ERP_INITIAL_LOGIN_PASSWORD_POLICY
-- DFAB OneERP / temporary-login enforcement — EXISTING DATABASE ADDITIVE UPGRADE
-- Apply only after ERP_ADMIN_CONTROL.sql. Run in staging and test with a pilot employee first.
-- Does NOT create accounts, change user passwords, assign roles, alter records or reset data.
-- IMPORTANT: a password set by the server-managed Auth function carries the trusted
-- app_metadata.erp_initial_password_pending claim. The temporary Auth JWT cannot
-- access ERP organization data until the employee replaces the password and signs in again.

CREATE OR REPLACE FUNCTION public.erp_current_org_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT p.organization_id
  FROM public.erp_profiles p
  WHERE p.user_id=auth.uid()
    AND p.active=true
    AND COALESCE(auth.jwt()->'app_metadata'->>'erp_initial_password_pending','false') <> 'true'
  LIMIT 1;
$$;
-- The existing ERP_ADMIN_CONTROL.sql implementation checks the organization
-- returned above. This additionally protects the base schema's ERP.VIEW helper.
CREATE OR REPLACE FUNCTION public.erp_has_permission(p_permission text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT public.erp_current_org_id() IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.erp_user_roles ur
    JOIN public.erp_roles r ON r.id=ur.role_id AND r.active
    JOIN public.erp_role_permissions rp ON rp.role_id=r.id
    JOIN public.erp_profiles p ON p.user_id=ur.user_id AND p.active
      AND p.organization_id=r.organization_id
    WHERE ur.user_id=auth.uid()
      AND r.organization_id=public.erp_current_org_id()
      AND rp.permission_code=p_permission
  );
$$;

NOTIFY pgrst, 'reload schema';


-- COMPONENT: ERP_WORKSPACE_INTEGRITY
-- Additive workspace audit repair. No transaction rows or employee accounts are rewritten.

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


-- COMPONENT: ERP_EXTENSIONS
-- Run after ERP_WORKSPACE_INTEGRITY.sql. Safe to reapply on an existing workspace.

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


-- COMPONENT: DFAB_PROCESS_UPGRADE
-- Additive migration. Run AFTER DFAB_ERP_PRODUCTION.sql. No data is deleted.
-- Atomic compatibility writes for transaction header, lines, assignment and lineage.

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


-- COMPONENT: ERP_PRODUCTION_PROCESS_CONTROLS
-- Apply after ERP_WORKSPACE_INTEGRITY.sql and DFAB_PROCESS_UPGRADE.sql. Additive; no business records are rewritten.

create table if not exists public.erp_process_modules(page text primary key, columns jsonb not null, approval boolean not null, party_required boolean not null,status_map jsonb not null);
alter table public.erp_process_modules enable row level security;
revoke all on public.erp_process_modules from public,anon,authenticated;
insert into public.erp_process_modules values('Sales Enquiries','["Enquiry No","Customer","Product","Qty","Expected Delivery","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Sales Enquiries','Sales Enquiries',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Sales Enquiries','Sales Enquiries',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Sales Quotations','["Quotation No","Customer","Enquiry","Amount","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Sales Quotations','Sales Quotations',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Sales Quotations','Sales Quotations',0,4) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Sales Orders','["SO No","Customer","Customer PO","Product","Qty","Delivery","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Sales Orders','Sales Orders',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Sales Orders','Sales Orders',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Purchase Orders','["PO No","Vendor","PO Date","Amount","Delivery Date","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Purchase Orders','Purchase Orders',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Purchase Orders','Purchase Orders',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Purchase Indents','["Indent No","Department","Item","Qty","Required Date","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Purchase Indents','Purchase Indents',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Purchase Indents','Purchase Indents',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('GRN','["GRN No","PO No","Vendor","Item","Received Qty","QC Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Awaiting QC","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-GRN','GRN',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-GRN','GRN',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Work Order','["WO No","SO No","Product","Qty","Machine","Status"]'::jsonb,true,true,'{"DRAFT":"Planned","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Work Order','Work Order',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Work Order','Work Order',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Material Request','["Request No","Work Order","Item","Qty","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Material Request','Material Request',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Material Request','Material Request',0,4) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Material Issue','["Issue No","Work Order","Item","Qty","Store","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Issued","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Material Issue','Material Issue',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Material Issue','Material Issue',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Production Output','["Output No","WO No","Product","Good Qty","Reject Qty","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"QC Pending","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Production Output','Production Output',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Production Output','Production Output',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Outward QC','["QC No","Output No","Product","Qty","Inspector","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Outward QC','Outward QC',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Outward QC','Outward QC',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Delivery Challan','["DC No","Customer","SO No","Product","Qty","Vehicle","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Delivery Challan','Delivery Challan',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Delivery Challan','Delivery Challan',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Sales Invoice','["#","Invoice No","Date","Customer","SO No","Reference","Status","Amount","Sync","Remarks"]'::jsonb,false,true,'{"DRAFT":"DRAFT","APPROVAL PENDING":"APPROVAL PENDING","APPROVED":"APPROVED","REJECTED":"REJECTED","RELEASED":"APPROVED","PASSED":"PASSED","ACCEPTED":"ACCEPTED","COMPLETED":"COMPLETED","DISPATCHED":"DISPATCHED","DELIVERED":"DELIVERED"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Sales Invoice','Sales Invoice',1,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-sales-invoices-v2','Sales Invoice',1,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Purchase','["Invoice No","Vendor","PO No","Invoice Date","Taxable Amount","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Purchase','Purchase',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Purchase','Purchase',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Job Work Inward','["Inward No","Customer","DC No","Material","Qty","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Job Work Inward','Job Work Inward',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Job Work Inward','Job Work Inward',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Job Work Return DC','["Return DC No","Customer","Inward No","Product","Qty","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Job Work Return DC','Job Work Return DC',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Job Work Return DC','Job Work Return DC',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Outsource Issue DC','["DC No","Vendor","Work Order","Process","Qty","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Outsource Issue DC','Outsource Issue DC',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Outsource Issue DC','Outsource Issue DC',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Outsource Receipt','["Receipt No","Issue DC","Vendor","Process","Received Qty","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Outsource Receipt','Outsource Receipt',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Outsource Receipt','Outsource Receipt',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Inward Quality','["Inspection No","GRN No","Item","Accepted Qty","Rejected Qty","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Inward Quality','Inward Quality',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Inward Quality','Inward Quality',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Inward Quality Rejection','["Rejection No","QC No","Vendor","Item","Rejected Qty","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Inward Quality Rejection','Inward Quality Rejection',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Inward Quality Rejection','Inward Quality Rejection',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Rejection Note','["Rejection No","Work Order","Product","Qty","Reason","Status"]'::jsonb,true,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Rejection Note','Rejection Note',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Rejection Note','Rejection Note',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Sales Return','["Return No","Invoice","Customer","Product","Qty","Decision"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Sales Return','Sales Return',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Sales Return','Sales Return',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Proforma Invoice','["Proforma No","Customer","SO No","Date","Amount","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Proforma Invoice','Proforma Invoice',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Proforma Invoice','Proforma Invoice',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Credit Note','["Credit Note No","Invoice","Customer","Date","Amount","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Credit Note','Credit Note',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Credit Note','Credit Note',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Scrap Entry','["Scrap No","Work Order","Material","Qty","Reason","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Disposed","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Scrap Entry','Scrap Entry',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Scrap Entry','Scrap Entry',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Opening Stock','["Entry No","Item","Warehouse","Qty","Rate","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Opening Stock','Opening Stock',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Opening Stock','Opening Stock',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Excess Stock','["Entry No","Item","Warehouse","Excess Qty","Reason","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Adjusted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Excess Stock','Excess Stock',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Excess Stock','Excess Stock',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Shortage Stock','["Entry No","Item","Warehouse","Shortage Qty","Reason","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Adjusted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Shortage Stock','Shortage Stock',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Shortage Stock','Shortage Stock',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Inward QC','["QC No","GRN No","Item","Qty","Inspector","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Inward QC','Inward QC',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Inward QC','Inward QC',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Route Cards','["Route No","WO No","Operation","Machine","Completed Qty","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Route Cards','Route Cards',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Route Cards','Route Cards',0,5) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Import Purchase','["Import No","Vendor","PO No","Item","Qty","Currency","Customs Value","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Import Purchase','Import Purchase',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Import Purchase','Import Purchase',0,7) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Procurement Planning','["Plan No","Item","Required Qty","Available Qty","Need Date","Department","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Procurement Planning','Procurement Planning',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Procurement Planning','Procurement Planning',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Procurement Schedule','["Schedule No","PO No","Vendor","Item","Qty","Planned Date","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Procurement Schedule','Procurement Schedule',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Procurement Schedule','Procurement Schedule',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Dispatch Schedule','["Schedule No","SO No","Customer","Product","Qty","Scheduled Date","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Dispatch Schedule','Dispatch Schedule',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Dispatch Schedule','Dispatch Schedule',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Production Schedule','["Schedule No","WO No","Product","Qty","Machine","Planned Date","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Production Schedule','Production Schedule',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Production Schedule','Production Schedule',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Project Planning','["Project No","Customer","SO No","Start Date","Target Date","Owner","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Project Planning','Project Planning',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Project Planning','Project Planning',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Job Order','["Job No","Work Order","Vendor","Process","Qty","Required Date","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Job Order','Job Order',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Job Order','Job Order',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Jobwork Material Issue','["Issue No","Job No","Vendor","Item","Qty","Issue Date","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Jobwork Material Issue','Jobwork Material Issue',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Jobwork Material Issue','Jobwork Material Issue',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Jobwork Material Receipt','["Receipt No","Issue No","Vendor","Item","Received Qty","Receipt Date","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Jobwork Material Receipt','Jobwork Material Receipt',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Jobwork Material Receipt','Jobwork Material Receipt',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Service Invoice','["Invoice No","Vendor","Job No","Service","Amount","Invoice Date","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Service Invoice','Service Invoice',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Service Invoice','Service Invoice',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Input to Production','["Input No","WO No","Item","Qty","Issue No","Date","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Input to Production','Input to Production',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Input to Production','Input to Production',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Stage Receipt','["Receipt No","WO No","Operation","Machine","Good Qty","Reject Qty","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Stage Receipt','Stage Receipt',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Stage Receipt','Stage Receipt',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Stage Consumption','["Consumption No","WO No","Operation","Item","Consumed Qty","Input No","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Stage Consumption','Stage Consumption',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Stage Consumption','Stage Consumption',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Excess Issue','["Issue No","WO No","Item","Qty","Reason","Store","Status"]'::jsonb,true,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Excess Issue','Excess Issue',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Excess Issue','Excess Issue',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Return to Store','["Return No","WO No","Item","Qty","Warehouse","Date","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Return to Store','Return to Store',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Return to Store','Return to Store',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Dispatch Intimation','["Intimation No","SO No","Customer","Product","Qty","Planned Date","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Dispatch Intimation','Dispatch Intimation',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Dispatch Intimation','Dispatch Intimation',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('BOM-Based Work Order','["BOM WO No","BOM No","Product","Qty","Start Date","Target Date","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-BOM-Based Work Order','BOM-Based Work Order',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-BOM-Based Work Order','BOM-Based Work Order',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Stock Adjustment','["Adjustment No","Item","Warehouse","Quantity Change","Reason","Date","Status"]'::jsonb,true,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Stock Adjustment','Stock Adjustment',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Stock Adjustment','Stock Adjustment',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Material Reserve','["Reserve No","WO No","Item","Qty","Warehouse","Required Date","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Material Reserve','Material Reserve',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Material Reserve','Material Reserve',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Material Unreserved','["Unreserve No","Reserve No","Item","Qty","Warehouse","Date","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Material Unreserved','Material Unreserved',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Material Unreserved','Material Unreserved',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Terminate Order','["Termination No","SO No","Customer","Reason","Date","Approved By","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Terminate Order','Terminate Order',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Terminate Order','Terminate Order',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Project Order','["Project Order No","Project No","Customer","SO No","Value","Due Date","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Project Order','Project Order',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Project Order','Project Order',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Purchase Return','["Return No","GRN No","Vendor","Item","Qty","Reason","Status"]'::jsonb,true,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Returned","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Purchase Return','Purchase Return',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Purchase Return','Purchase Return',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Pick Slip','["Pick No","SO No","Warehouse","Item","Qty","Picker","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Pick Slip','Pick Slip',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Pick Slip','Pick Slip',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Put Away','["Putaway No","GRN No","Item","Qty","Warehouse","Rack","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Put Away','Put Away',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Put Away','Put Away',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('In-process QC','["QC No","WO No","Operation","Qty","Inspector","Disposition","Status"]'::jsonb,false,false,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-In-process QC','In-process QC',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-In-process QC','In-process QC',0,6) on conflict(storage_key) do nothing;
insert into public.erp_process_modules values('Job Work QC','["QC No","Receipt No","Vendor","Item","Qty","Inspector","Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do update set columns=excluded.columns,approval=excluded.approval,party_required=excluded.party_required,status_map=excluded.status_map;
insert into public.erp_admin_storage_map values('dfab-process-Job Work QC','Job Work QC',0,-1) on conflict(storage_key) do nothing;
insert into public.erp_admin_storage_map values('dfab-erp-Job Work QC','Job Work QC',0,6) on conflict(storage_key) do nothing;
create table if not exists public.erp_process_edges(source text,target text,primary key(source,target));
alter table public.erp_process_edges enable row level security;revoke all on public.erp_process_edges from public,anon,authenticated;
insert into public.erp_process_edges values('Sales Orders','Sales Quotations') on conflict do nothing;
insert into public.erp_process_edges values('Sales Enquiries','Sales Quotations') on conflict do nothing;
insert into public.erp_process_edges values('Sales Quotations','Sales Orders') on conflict do nothing;
insert into public.erp_process_edges values('Job Work Inward','Sales Orders') on conflict do nothing;
insert into public.erp_process_edges values('Inward QC','Sales Orders') on conflict do nothing;
insert into public.erp_process_edges values('Purchase Indents','Purchase Orders') on conflict do nothing;
insert into public.erp_process_edges values('Outsource Issue DC','Purchase Orders') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Purchase Orders') on conflict do nothing;
insert into public.erp_process_edges values('Procurement Planning','Purchase Indents') on conflict do nothing;
insert into public.erp_process_edges values('Purchase Orders','GRN') on conflict do nothing;
insert into public.erp_process_edges values('Import Purchase','GRN') on conflict do nothing;
insert into public.erp_process_edges values('Procurement Schedule','GRN') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Work Order') on conflict do nothing;
insert into public.erp_process_edges values('Rejection Note','Work Order') on conflict do nothing;
insert into public.erp_process_edges values('BOM-Based Work Order','Work Order') on conflict do nothing;
insert into public.erp_process_edges values('Project Order','Work Order') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Material Request') on conflict do nothing;
insert into public.erp_process_edges values('Material Reserve','Material Request') on conflict do nothing;
insert into public.erp_process_edges values('Material Request','Material Issue') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Production Output') on conflict do nothing;
insert into public.erp_process_edges values('Route Cards','Production Output') on conflict do nothing;
insert into public.erp_process_edges values('Production Output','Outward QC') on conflict do nothing;
insert into public.erp_process_edges values('Route Cards','Outward QC') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Delivery Challan') on conflict do nothing;
insert into public.erp_process_edges values('Outward QC','Delivery Challan') on conflict do nothing;
insert into public.erp_process_edges values('Dispatch Schedule','Delivery Challan') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Sales Invoice') on conflict do nothing;
insert into public.erp_process_edges values('Delivery Challan','Sales Invoice') on conflict do nothing;
insert into public.erp_process_edges values('Job Work Return DC','Sales Invoice') on conflict do nothing;
insert into public.erp_process_edges values('GRN','Purchase') on conflict do nothing;
insert into public.erp_process_edges values('Inward QC','Purchase') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Outsource Issue DC') on conflict do nothing;
insert into public.erp_process_edges values('Route Cards','Outsource Issue DC') on conflict do nothing;
insert into public.erp_process_edges values('Job Order','Outsource Issue DC') on conflict do nothing;
insert into public.erp_process_edges values('Outsource Issue DC','Outsource Receipt') on conflict do nothing;
insert into public.erp_process_edges values('Job Work Inward','Inward Quality') on conflict do nothing;
insert into public.erp_process_edges values('Sales Invoice','Sales Return') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Proforma Invoice') on conflict do nothing;
insert into public.erp_process_edges values('Sales Invoice','Credit Note') on conflict do nothing;
insert into public.erp_process_edges values('Sales Return','Credit Note') on conflict do nothing;
insert into public.erp_process_edges values('GRN','Inward QC') on conflict do nothing;
insert into public.erp_process_edges values('Job Work Inward','Inward QC') on conflict do nothing;
insert into public.erp_process_edges values('Outsource Receipt','Inward QC') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Route Cards') on conflict do nothing;
insert into public.erp_process_edges values('Material Issue','Route Cards') on conflict do nothing;
insert into public.erp_process_edges values('Dispatch Intimation','Dispatch Schedule') on conflict do nothing;
insert into public.erp_process_edges values('Jobwork Material Issue','Jobwork Material Receipt') on conflict do nothing;
insert into public.erp_process_edges values('Production Schedule','Input to Production') on conflict do nothing;
insert into public.erp_process_edges values('Excess Issue','Input to Production') on conflict do nothing;
insert into public.erp_process_edges values('Stage Consumption','Stage Receipt') on conflict do nothing;
insert into public.erp_process_edges values('Input to Production','Stage Consumption') on conflict do nothing;
insert into public.erp_process_edges values('Pick Slip','Dispatch Intimation') on conflict do nothing;
insert into public.erp_process_edges values('Project Planning','Project Order') on conflict do nothing;
insert into public.erp_process_edges values('Stage Receipt','In-process QC') on conflict do nothing;
insert into public.erp_process_edges values('Jobwork Material Receipt','Job Work QC') on conflict do nothing;
insert into public.erp_admin_storage_map values ('dfab-process-payments-Sales Invoice','Customer Payments',0,-1),('dfab-process-payments-Purchase','Vendor Payments',0,-1),('dfab-process-payments-Service Invoice','Vendor Payments',0,-1) on conflict do nothing;

insert into public.erp_process_edges values('Inward QC','Work Order') on conflict do nothing;

create or replace function public.erp_next_process_no(p_document_type text,p_prefix text,p_financial_year text)
returns text language plpgsql security definer set search_path=public as $$
declare v_number text;v_key text;v_index integer;
begin
 if not exists(select 1 from public.erp_process_modules where page=p_document_type) or not public.erp_admin_can_page(p_document_type,'create') then raise exception 'Document create permission required' using errcode='42501';end if;
 if p_prefix !~ '^[A-Za-z0-9 /_.-]{1,32}$' or p_financial_year !~ '^[0-9]{2}-[0-9]{2}$' then raise exception 'Invalid number prefix or year';end if;
 v_key:=case when p_document_type='Sales Invoice' then 'dfab-erp-sales-invoices-v2' else 'dfab-erp-'||p_document_type end;
 v_index:=case when p_document_type='Sales Invoice' then 1 else 0 end;
 for i in 1..10000 loop
  v_number:=public.erp_next_document_no(p_document_type,p_prefix,p_financial_year);
  if not exists(select 1 from public.erp_ui_state s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.payload)='array' then s.payload else '[]'::jsonb end) r where s.organization_id=public.erp_current_org_id() and s.storage_key=v_key and r->>v_index=v_number) then return v_number;end if;
 end loop;
 raise exception 'Number sequence needs reconciliation';
end; $$;
revoke all on function public.erp_next_process_no(text,text,text) from public,anon;
grant execute on function public.erp_next_process_no(text,text,text) to authenticated;

-- A transaction-bound authorization can only be issued by the validated RPC.
-- This preserves the existing guard on every other write path.
create table if not exists public.erp_process_write_authorizations(
 transaction_id bigint not null, organization_id uuid not null, actor_id uuid not null,
 storage_key text not null, expected jsonb, payload jsonb,
 primary key(transaction_id,organization_id,actor_id,storage_key));
alter table public.erp_process_write_authorizations enable row level security;
revoke all on public.erp_process_write_authorizations from public,anon,authenticated;

create or replace function public.erp_guard_ui_state_mutation()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_org uuid;v_key text;
begin
 v_org:=case when TG_OP='DELETE' then OLD.organization_id else NEW.organization_id end;
 v_key:=case when TG_OP='DELETE' then OLD.storage_key else NEW.storage_key end;
 if auth.uid() is null or v_org is distinct from public.erp_current_org_id() or not public.erp_has_permission('ERP.EDIT') then
  raise exception 'ERP write access denied' using errcode='42501';end if;
 if TG_OP='UPDATE' and (NEW.organization_id<>OLD.organization_id or NEW.storage_key<>OLD.storage_key) then raise exception 'ERP section identity cannot change';end if;
 if TG_OP<>'DELETE' and exists(select 1 from public.erp_process_write_authorizations a
   where a.transaction_id=txid_current() and a.organization_id=v_org and a.actor_id=auth.uid() and a.storage_key=v_key
   and a.payload=NEW.payload and (TG_OP='INSERT' and a.expected=coalesce((select s.payload from public.erp_ui_state s where s.organization_id=v_org and s.storage_key=v_key),'null'::jsonb) or TG_OP='UPDATE' and a.expected=OLD.payload)) then return NEW;end if;
 if v_key like 'dfab-process-%' and not public.erp_admin_is_admin() then raise exception 'Use the atomic process save API' using errcode='42501';end if;
 if TG_OP='INSERT' then
  if not exists(select 1 from public.erp_ui_state where organization_id=v_org and storage_key=v_key) then perform public.erp_admin_assert_change(v_key,null,NEW.payload);end if;
  return NEW;end if;
 if TG_OP='DELETE' then perform public.erp_admin_assert_change(v_key,OLD.payload,null);return OLD;end if;
 perform public.erp_admin_assert_change(v_key,OLD.payload,NEW.payload);return NEW;
end; $$;

create or replace function public.erp_process_payload(p_key text,p_changes jsonb)
returns jsonb language sql stable security definer set search_path=public as $$
 select case when p_changes ? p_key then p_changes->p_key else
  (select payload from public.erp_ui_state where organization_id=public.erp_current_org_id() and storage_key=p_key) end
$$;
revoke all on function public.erp_process_payload(text,jsonb) from public,anon,authenticated;

create or replace function public.erp_process_total(p_doc jsonb)
returns numeric language plpgsql immutable set search_path=public as $$
declare l jsonb;b numeric;t numeric;v_total numeric:=0;d numeric;cg numeric;sg numeric;ig numeric;
begin
 if jsonb_typeof(p_doc->'lines')<>'array' or jsonb_array_length(p_doc->'lines') not between 1 and 500 then raise exception 'Add 1 to 500 product lines';end if;
 for l in select * from jsonb_array_elements(p_doc->'lines') loop
  if coalesce(l->>'code','')='' and coalesce(l->>'description','')='' then raise exception 'A product code or description is required';end if;
  if coalesce(l->>'quantity','') !~ '^[0-9]+([.][0-9]+)?$' or coalesce(l->>'rate','') !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'Valid quantity and rate required';end if;
  if (l->>'quantity')::numeric<=0 or (l->>'rate')::numeric<0 then raise exception 'Invalid product quantity or rate';end if;
  d:=coalesce(nullif(l->>'discount',''),'0')::numeric;cg:=coalesce(nullif(l->>'cgst',''),'0')::numeric;sg:=coalesce(nullif(l->>'sgst',''),'0')::numeric;ig:=coalesce(nullif(l->>'igst',''),'0')::numeric;
  if d not between 0 and 100 or cg not between 0 and 100 or sg not between 0 and 100 or ig not between 0 and 100 or cg+sg>100 or ig>0 and cg+sg>0 then raise exception 'Invalid discount or GST split';end if;
  b:=round((l->>'quantity')::numeric*(l->>'rate')::numeric,2);t:=b-round(b*d/100,2);
  v_total:=v_total+t+round(t*cg/100,2)+round(t*sg/100,2)+round(t*ig/100,2);
 end loop;
 for l in select * from jsonb_array_elements(coalesce(p_doc->'charges','[]'::jsonb)) loop
  if coalesce(l->>'description','')='' or (l->>'amount')::numeric<0 then raise exception 'Invalid charge';end if;
  t:=(l->>'amount')::numeric;cg:=coalesce(nullif(l->>'cgst',''),'0')::numeric;sg:=coalesce(nullif(l->>'sgst',''),'0')::numeric;ig:=coalesce(nullif(l->>'igst',''),'0')::numeric;
  if cg not between 0 and 100 or sg not between 0 and 100 or ig not between 0 and 100 or cg+sg>100 or ig>0 and cg+sg>0 then raise exception 'Invalid charge tax';end if;
  v_total:=v_total+t+round(t*cg/100,2)+round(t*sg/100,2)+round(t*ig/100,2);
 end loop;
 v_total:=round(v_total+coalesce(nullif(p_doc->>'adjustment',''),'0')::numeric,2);
 if v_total<0 or v_total::text in ('NaN','Infinity','-Infinity') then raise exception 'Invalid net amount';end if;
 return v_total;
end; $$;
revoke all on function public.erp_process_total(jsonb) from public,anon,authenticated;

-- Read-only stock calculation over proposed projections, under the commit lock.
create or replace function public.erp_process_stock(p_changes jsonb)
returns table(item text,balance numeric) language plpgsql stable security definer set search_path=public as $$
declare spec record;r jsonb;t jsonb;l jsonb;moves jsonb:='[]'::jsonb;direction numeric;quantity numeric;
begin
 for spec in select * from (values
 ('Opening Stock',1,3,5,array['Posted'],1,false),('GRN',3,4,5,array['Accepted'],1,false),
 ('Material Issue',2,3,5,array['Issued'],-1,false),('Return to Store',2,3,6,array['Posted'],1,false),
 ('Purchase Return',3,4,6,array['Returned'],-1,false),('Excess Stock',1,3,5,array['Adjusted'],1,false),
 ('Shortage Stock',1,3,5,array['Adjusted'],-1,false),('Production Output',2,3,5,array['Accepted'],1,false),
 ('Scrap Entry',2,3,5,array['Disposed'],-1,false),('Stock Adjustment',1,3,6,array['Posted'],1,false),
 ('Delivery Challan',3,4,6,array['Dispatched','Delivered'],-1,true),('Route Cards',2,4,5,array['Accepted'],1,true)
 ) v(module,product_index,quantity_index,status_index,statuses,movement,process_only) loop
  for r in select * from jsonb_array_elements(coalesce(nullif(public.erp_process_payload('dfab-erp-'||spec.module,p_changes),'null'::jsonb),'[]'::jsonb)) loop
   if not ((r->>spec.status_index)=any(spec.statuses)) then continue;end if;
   t:=r->(jsonb_array_length(r)-1);if spec.process_only and t->>'processVersion' is distinct from '1' then continue;end if;
   direction:=spec.movement;if spec.module='Stock Adjustment' and t->'header'->>'Adjustment direction'='Decrease' then direction:=-1;end if;
   if t->>'processVersion'='1' then
    for l in select * from jsonb_array_elements(t->'lines') loop
     moves:=moves||jsonb_build_array(jsonb_build_object('item',lower(coalesce(nullif(l->>'code',''),l->>'description')),'qty',direction*(l->>'quantity')::numeric));
    end loop;
   elsif coalesce(r->>spec.quantity_index,'') ~ '^-?[0-9]+([.][0-9]+)?$' then
    quantity:=(r->>spec.quantity_index)::numeric;
    moves:=moves||jsonb_build_array(jsonb_build_object('item',lower(r->>spec.product_index),'qty',direction*quantity));
   end if;
  end loop;
 end loop;
 return query select value->>'item',sum((value->>'qty')::numeric) from jsonb_array_elements(moves) group by value->>'item';
end; $$;
revoke all on function public.erp_process_stock(jsonb) from public,anon,authenticated;

create or replace function public.erp_commit_process(p_changes jsonb,p_expected jsonb,p_action text default 'save')
returns void language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();k text;old_payload jsonb;new_payload jsonb;module text;
 n text;d jsonb;o jsonb;src jsonb;l jsonb;sl jsonb;other jsonb;rows jsonb;rowval jsonb;metadata jsonb;
 total numeric;qty numeric;reserved numeric;rowkey text;idx integer;col text;ci integer;statusmap jsonb;
 derived boolean;qc jsonb;qc_module text;accepted numeric;changes_doc boolean;payment jsonb;invoice jsonb;allocated numeric;
begin
 if auth.uid() is null or v_org is null or not public.erp_has_permission('ERP.EDIT') then raise exception 'Active ERP edit session required' using errcode='42501';end if;
 if jsonb_typeof(p_changes)<>'object' or jsonb_typeof(p_expected)<>'object' or octet_length(p_changes::text)>12000000 then raise exception 'Invalid process payload';end if;
 if p_action not in ('save','approve','reject','handoff','payment','close','delete') then raise exception 'Invalid process action';end if;
 if (select count(*) from jsonb_object_keys(p_changes)) not between 1 and 500 then raise exception 'Invalid section count';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text,0));
 for k,new_payload in select * from jsonb_each(p_changes) loop
  if not (p_expected ? k) or k !~ '^dfab-[a-zA-Z0-9 /_.-]+$' or k ~* '(password|credential|session)' then raise exception 'Unsupported process key';end if;
  select payload into old_payload from public.erp_ui_state where organization_id=v_org and storage_key=k for update;
  if coalesce(old_payload,'null'::jsonb) is distinct from p_expected->k then raise exception 'This record changed in another session. Reload before saving' using errcode='40001';end if;
 end loop;
 -- The complete document collection is validated, not just the visible register row.
 for k,new_payload in select * from jsonb_each(p_changes) where key like 'dfab-process-%' and key not like 'dfab-process-payments%' loop
  if new_payload is not distinct from p_expected->k then continue;end if;
  module:=substring(k from 14);
  if not exists(select 1 from public.erp_process_modules where page=module) then raise exception 'Unsupported process module %',module;end if;
  old_payload:=coalesce(nullif(p_expected->k,'null'::jsonb),'{}'::jsonb);
  if jsonb_typeof(new_payload)<>'object' then raise exception 'Document collection must be an object';end if;
  for n,d in select * from jsonb_each(new_payload) loop
   o:=old_payload->n;if d=o then continue;end if;
   if n !~ '^[A-Za-z0-9 /_.-]{1,100}$' or d->>'number' is distinct from n or d->>'module' is distinct from module then raise exception 'Document identity mismatch';end if;
   derived:=false;
   if d->>'status'='ACCEPTED' and o is not null and (d-'status')=(o-'status') then
    qc_module:=case when module in ('Production Output','Route Cards') then 'Outward QC' else 'Inward QC' end;
    accepted:=0;
    for qc in select value from jsonb_each(coalesce(public.erp_process_payload('dfab-process-'||qc_module,p_changes),'{}'::jsonb)) loop
     if qc->>'status'='PASSED' and qc->'source'->>'module'=module and qc->'source'->>'number'=n then accepted:=accepted+coalesce((qc->'inspection'->>'accepted')::numeric,0);end if;
    end loop;
    select sum((value->>'quantity')::numeric) into qty from jsonb_array_elements(d->'lines');
    derived:=accepted>=qty and public.erp_admin_can_page(qc_module,'approve');
   end if;
   if o is null and not public.erp_admin_can_page(module,'create') then raise exception 'Create permission required on %',module using errcode='42501';end if;
   if o is not null and not public.erp_admin_can_page(module,'edit') and not derived and not
    (public.erp_admin_can_page(module,'approve') and (d-array['status','history','updatedAt'])=(o-array['status','history','updatedAt'])) then raise exception 'Edit permission required on %',module using errcode='42501';end if;
   if d->>'status' not in ('DRAFT','APPROVAL PENDING') and not public.erp_admin_can_page(module,'approve') and not derived then raise exception 'Approval permission required on %',module using errcode='42501';end if;
   if d->>'status' not in ('DRAFT','APPROVAL PENDING','APPROVED','REJECTED','RELEASED','PASSED','ACCEPTED','COMPLETED','DISPATCHED','DELIVERED') then raise exception 'Invalid document status';end if;
   if o is not null and module in ('Sales Invoice','Purchase','Service Invoice') and exists(select 1 from public.erp_ui_state s cross join lateral jsonb_array_elements(case when jsonb_typeof(s.payload)='array' then s.payload else '[]'::jsonb end) r where s.organization_id=v_org and s.storage_key=case when module='Sales Invoice' then 'dfab-erp-Customer Payments' else 'dfab-erp-Vendor Payments' end and r->>2=n and lower(r->>5) in ('paid','part paid','settled')) then raise exception 'An invoice with allocations cannot be edited';end if;
   if o is not null and (d-array['status','history','updatedAt'])<>(o-array['status','history','updatedAt']) and exists(
    select 1 from public.erp_ui_state s cross join lateral jsonb_each(case when jsonb_typeof(s.payload)='object' then s.payload else '{}'::jsonb end) x
    where s.organization_id=v_org and s.storage_key like 'dfab-process-%' and x.value->'source'->>'module'=module and x.value->'source'->>'number'=n) then raise exception 'Linked source details cannot be changed';end if;
   if coalesce(d->>'status','')='' or coalesce(d->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or coalesce(d->>'total','') !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'Status, valid date and total required';end if;
   if coalesce((d->>'legacy')::boolean,false) and d->>'status'<>'DRAFT' then raise exception 'Reconcile legacy lines before release';end if;
   if (d->>'date')::date::text is distinct from d->>'date' then raise exception 'Valid document date required';end if;
   if (select party_required from public.erp_process_modules where page=module) and trim(coalesce(d->>'party',''))='' then raise exception 'Party required';end if;
   if d->>'status'<>'DRAFT' and (trim(coalesce(d->'assignment'->>'user',''))='' or trim(coalesce(d->'assignment'->>'department',''))='' or (d->'assignment'->>'due')::date<(d->>'date')::date or coalesce(d->'assignment'->>'due','')='') then raise exception 'Assign a next task and valid target date';end if;
   total:=public.erp_process_total(d);
   if not coalesce((d->>'legacy')::boolean,false) and abs(total-(d->>'total')::numeric)>0.009 then raise exception 'Document total does not match lines and charges';end if;
   if module in ('Inward QC','Inward Quality','Outward QC','In-process QC','Job Work QC') and d->>'status' in ('PASSED','RELEASED','APPROVED') then
    select sum((value->>'quantity')::numeric) into qty from jsonb_array_elements(d->'lines');
    if d->'inspection'->>'result'<>'Passed' or coalesce(d->'inspection'->>'inspector','')='' or (d->'inspection'->>'rejected')::numeric<>0 or (d->'inspection'->>'accepted')::numeric<>qty then raise exception 'Passed inspection and accepted quantity required';end if;
   end if;
   if d->>'status' not in ('DRAFT','APPROVAL PENDING','REJECTED') then
    if module in ('Inward QC','Inward Quality','Outward QC','In-process QC','Job Work QC','Production Output','Material Issue','Outsource Receipt','Outsource Issue DC','GRN') and (d->'source' is null or d->'source'='null'::jsonb) then raise exception 'Fetch released source before release';end if;
    if module='Work Order' or module='Sales Orders' and d->>'flow'='labour' or module in ('Delivery Challan','Job Work Return DC') then
     qc_module:=case when module in ('Work Order','Sales Orders') then 'Inward QC' else 'Outward QC' end;
     qc:=public.erp_process_payload('dfab-process-'||qc_module,p_changes)->(d->'references'->>qc_module);
     if qc is null or qc->>'status'<>'PASSED' or qc->'inspection'->>'result'<>'Passed' then raise exception 'Passed QC lineage required before release';end if;
    end if;
    if module='Purchase' then
     qc:=public.erp_process_payload('dfab-process-GRN',p_changes)->(d->'references'->>'GRN');if qc is null or qc->>'status'<>'ACCEPTED' then raise exception 'Accepted GRN after QC required for purchase invoice';end if;
    end if;
    if module='Sales Invoice' then
     qc:=coalesce(public.erp_process_payload('dfab-process-Delivery Challan',p_changes)->(d->'references'->>'Delivery Challan'),public.erp_process_payload('dfab-process-Job Work Return DC',p_changes)->(d->'references'->>'Job Work Return DC'));
     if qc is null or qc->>'status' not in ('APPROVED','RELEASED','DISPATCHED','DELIVERED') then raise exception 'Released dispatch lineage required for invoicing';end if;
    end if;
   end if;
   if d->'source' is not null then
    src:=public.erp_process_payload('dfab-process-'||(d->'source'->>'module'),p_changes)->(d->'source'->>'number');
    if src is null or coalesce((src->>'legacy')::boolean,false) or src->>'status' not in ('APPROVED','RELEASED','PASSED','ACCEPTED','COMPLETED','DISPATCHED','DELIVERED') or not (exists(select 1 from public.erp_process_edges where source=src->>'module' and target=module) or exists(select 1 from public.erp_admin_flow_edges e join public.erp_admin_flow_templates t on t.id=e.template_id where t.organization_id=v_org and t.status='published' and e.source_page=src->>'module' and e.target_page=module)) then raise exception 'Released source with verified line details required';end if;
    if src->>'module' in ('Inward QC','Inward Quality','Outward QC','In-process QC','Job Work QC') and src->'inspection'->>'result'<>'Passed' then raise exception 'Source inspection must pass';end if;
    if src->>'module'='Route Cards' and exists(select 1 from jsonb_array_elements(src->'operations') op where op->>'status'<>'Completed' or coalesce((op->>'qcRequired')::boolean,false) and op->>'qcStatus'<>'Passed') then raise exception 'Route operations and QC must be complete';end if;
    for l in select * from jsonb_array_elements(d->'lines') loop
     select value into sl from jsonb_array_elements(src->'lines') where value->>'id'=l->>'sourceLineId';
     if sl is null or l->>'rootLineId' is distinct from coalesce(sl->>'rootLineId',sl->>'id') or l->>'code' is distinct from sl->>'code' or l->>'uom' is distinct from sl->>'uom' then raise exception 'Fetched line identity or product mismatch';end if;
     reserved:=0;
     for other in select value from jsonb_each(new_payload) loop
      if other->>'status'<>'REJECTED' and other->'source'=d->'source' then
       select reserved+coalesce(sum((value->>'quantity')::numeric),0) into reserved from jsonb_array_elements(other->'lines') where value->>'sourceLineId'=sl->>'id';
      end if;
     end loop;
     if reserved>(sl->>'quantity')::numeric+0.000001 then raise exception 'Fetched quantity exceeds pending source quantity';end if;
    end loop;
   end if;
   rowkey:=case when module='Sales Invoice' then 'dfab-erp-sales-invoices-v2' else 'dfab-erp-'||module end;
   if not (p_changes ? rowkey) then raise exception 'Register projection required';end if;
   idx:=case when module='Sales Invoice' then 1 else 0 end;
   select value into rowval from jsonb_array_elements(p_changes->rowkey) where value->>idx=n;
   if rowval is null then raise exception 'Register reference missing';end if;
   select status_map into statusmap from public.erp_process_modules where page=module;
   for col,ci in select value#>>'{}',(ordinality-1)::integer from jsonb_array_elements((select columns from public.erp_process_modules where page=module)) with ordinality loop
    if col ~* '(status|stage|decision)' and rowval->>ci is distinct from statusmap->>(d->>'status') then raise exception 'Register status mismatch';end if;
    if col ~* '^(customer|vendor|supplier)$' and rowval->>ci is distinct from d->>'party' then raise exception 'Register party mismatch';end if;
    if col ~* '^(amount|value)$' and abs((rowval->>ci)::numeric-(d->>'total')::numeric)>0.009 then raise exception 'Register amount mismatch';end if;
   end loop;
   if module<>'Sales Invoice' then
    metadata:=rowval->(jsonb_array_length(rowval)-1);
    if metadata->'lines' is distinct from d->'lines' or metadata->>'processStatus' is distinct from d->>'status' then raise exception 'Register line details mismatch';end if;
   end if;
  end loop;
  for n,o in select * from jsonb_each(old_payload) loop
   if new_payload ? n then continue;end if;
   if not public.erp_admin_can_page(module,'delete') then raise exception 'Delete permission required';end if;
   if exists(select 1 from public.erp_ui_state s cross join lateral jsonb_each(case when jsonb_typeof(s.payload)='object' then s.payload else '{}'::jsonb end) x where s.organization_id=v_org and s.storage_key like 'dfab-process-%' and x.value->'source'->>'module'=module and x.value->'source'->>'number'=n) then raise exception 'Linked documents cannot be deleted';end if;
  end loop;
 end loop;
 -- Every changed projection has a paired sidecar. Unchanged source snapshots are locks only.
 for k,new_payload in select * from jsonb_each(p_changes) loop
  if new_payload is not distinct from p_expected->k then continue;end if;
  select page into module from public.erp_admin_storage_map where storage_key=k;
  if k like 'dfab-erp-%' and exists(select 1 from public.erp_process_modules where page=module) and not(p_changes ? ('dfab-process-'||module)) then raise exception 'Complete process document required';end if;
  if k='dfab-invoice-details-v1' and not(p_changes ? 'dfab-process-Sales Invoice') then raise exception 'Complete invoice required';end if;
  if k='dfab-workflow-links-v1' then
   for l in select * from jsonb_array_elements(new_payload) loop
    if coalesce(p_expected->k,'[]'::jsonb) @> jsonb_build_array(l) then continue;end if;
    d:=public.erp_process_payload('dfab-process-'||(l->>'to'),p_changes)->(l->>'created');
    if d is null or d->'source'->>'module' is distinct from l->>'from' or d->'source'->>'number' is distinct from l->>'reference' then raise exception 'Invalid workflow link';end if;
   end loop;
  elsif k like 'dfab-process-payments-%' then
   module:=substring(k from 23);
   if module not in ('Sales Invoice','Purchase','Service Invoice') then raise exception 'Unknown payment module';end if;
   if not public.erp_admin_can_page(module,'view') or not public.erp_admin_can_page(case when module<>'Sales Invoice' then 'Vendor Payments' else 'Customer Payments' end,'create') then raise exception 'Payment create permission required';end if;
   if not new_payload @> coalesce(nullif(p_expected->k,'null'::jsonb),'[]'::jsonb) then raise exception 'Payment history is append-only';end if;
   for payment in select * from jsonb_array_elements(new_payload) loop
    if coalesce(nullif(p_expected->k,'null'::jsonb),'[]'::jsonb) @> jsonb_build_array(payment) then continue;end if;
    invoice:=public.erp_process_payload('dfab-process-'||module,p_changes)->(payment->>'invoice');
    if invoice is null then
     rowkey:=case when module='Sales Invoice' then 'dfab-erp-sales-invoices-v2' else 'dfab-erp-'||module end;idx:=case when module='Sales Invoice' then 1 else 0 end;
     select value into rowval from jsonb_array_elements(coalesce(public.erp_process_payload(rowkey,p_changes),'[]'::jsonb)) where value->>idx=payment->>'invoice';
     if rowval is not null then
      invoice:='{}'::jsonb;
      for col,ci in select value#>>'{}',(ordinality-1)::integer from jsonb_array_elements((select columns from public.erp_process_modules where page=module)) with ordinality loop
       if col in ('Amount','Taxable Amount') then invoice:=invoice||jsonb_build_object('total',rowval->>ci);end if;
       if col in ('Date','Invoice Date') then invoice:=invoice||jsonb_build_object('date',rowval->>ci);end if;
       if col='Status' then invoice:=invoice||jsonb_build_object('status',upper(rowval->>ci));end if;
      end loop;
     end if;
    end if;
    if invoice is null or invoice->>'status' in ('DRAFT','REJECTED','APPROVAL PENDING') then raise exception 'Released invoice required';end if;
    select coalesce(sum(coalesce((value->>'amount')::numeric,0)+coalesce((value->>'tds')::numeric,0)+coalesce((value->>'ld')::numeric,0)),0) into allocated from jsonb_array_elements(new_payload) where value->>'invoice'=payment->>'invoice';
    rowkey:=case when module<>'Sales Invoice' then 'dfab-erp-Vendor Payments' else 'dfab-erp-Customer Payments' end;
    select coalesce(sum((r->>4)::numeric+coalesce((r->6->'header'->>'TDS Amount')::numeric,0)+coalesce((r->6->'header'->>'LD Amount')::numeric,0)),0) into allocated
    from jsonb_array_elements(coalesce(public.erp_process_payload(rowkey,p_changes),'[]'::jsonb)) r where r->>2=payment->>'invoice' and coalesce(r->6->'header'->>'Invoice Module',case when module='Service Invoice' then '' else module end)=module and lower(r->>5) in ('paid','part paid','settled');
    if allocated>(invoice->>'total')::numeric or (payment->>'amount')::numeric<0 or (payment->>'tds')::numeric<0 or (payment->>'ld')::numeric<0 or (payment->>'date')::date<(invoice->>'date')::date then raise exception 'Invalid or excessive payment allocation';end if;
   end loop;
  elsif k in ('dfab-erp-Customer Payments','dfab-erp-Vendor Payments') then
   rowkey:=case when k='dfab-erp-Customer Payments' then 'dfab-process-payments-Sales Invoice' when p_changes ? 'dfab-process-payments-Service Invoice' then 'dfab-process-payments-Service Invoice' else 'dfab-process-payments-Purchase' end;
   if not (p_changes ? rowkey) or not new_payload @> coalesce(nullif(p_expected->k,'null'::jsonb),'[]'::jsonb) then raise exception 'Verified append-only payment required';end if;
   for rowval in select * from jsonb_array_elements(new_payload) loop
    if coalesce(nullif(p_expected->k,'null'::jsonb),'[]'::jsonb) @> jsonb_build_array(rowval) then continue;end if;
    select value into payment from jsonb_array_elements(p_changes->rowkey) where value->>'id'=rowval->>0;
    if payment is null or rowval->>2 is distinct from payment->>'invoice' or (rowval->>4)::numeric is distinct from (payment->>'amount')::numeric or coalesce((rowval->6->'header'->>'TDS Amount')::numeric,0) is distinct from coalesce((payment->>'tds')::numeric,0) or coalesce((rowval->6->'header'->>'LD Amount')::numeric,0) is distinct from coalesce((payment->>'ld')::numeric,0) then raise exception 'Payment projection mismatch';end if;
   end loop;
  elsif k not like 'dfab-process-%' and k<>'dfab-invoice-details-v1' and not exists(select 1 from public.erp_admin_storage_map m join public.erp_process_modules p on p.page=m.page where m.storage_key=k) then
   if k not in ('dfab-erp-Customer Payments','dfab-erp-Vendor Payments') then raise exception 'Unsupported process section';end if;
  end if;
 end loop;
 if p_action='close' then
  for k,new_payload in select * from jsonb_each(p_changes) where key in ('dfab-process-Sales Enquiries','dfab-process-Work Order') loop
   module:=substring(k from 14);
   for n,d in select * from jsonb_each(new_payload) loop
    if d is not distinct from p_expected->k->n or d->>'status'<>'COMPLETED' then continue;end if;
    rows:=coalesce(public.erp_process_payload('dfab-process-Sales Invoice',p_changes),'{}'::jsonb);
    for l in select * from jsonb_array_elements(d->'lines') loop
     reserved:=0;
     for invoice in select value from jsonb_each(rows) where value->'references'->>module=n and value->>'status'<>'REJECTED' loop
      if invoice->>'status' not in ('APPROVED','RELEASED') then raise exception 'Every linked invoice must be approved';end if;
      select coalesce(sum((r->>4)::numeric+coalesce((r->6->'header'->>'TDS Amount')::numeric,0)+coalesce((r->6->'header'->>'LD Amount')::numeric,0)),0) into allocated from jsonb_array_elements(coalesce(public.erp_process_payload('dfab-erp-Customer Payments',p_changes),'[]'::jsonb)) r where r->>2=invoice->>'number' and lower(r->>5) in ('part paid','settled');
      if allocated<(invoice->>'total')::numeric then raise exception 'Receive full payment before closure';end if;
      select reserved+coalesce(sum((value->>'quantity')::numeric),0) into reserved from jsonb_array_elements(invoice->'lines') where coalesce(value->>'rootLineId',value->>'id')=coalesce(l->>'rootLineId',l->>'id');
     end loop;
     if reserved<(l->>'quantity')::numeric then raise exception 'Invoice the full source item quantity before closure';end if;
     reserved:=0;
     for qc in select value from jsonb_each(coalesce(public.erp_process_payload('dfab-process-Delivery Challan',p_changes),'{}'::jsonb)) where value->'references'->>module=n loop
      if qc->>'status'<>'DELIVERED' then raise exception 'Confirm every delivery before closure';end if;
      select reserved+coalesce(sum((value->>'quantity')::numeric),0) into reserved from jsonb_array_elements(qc->'lines') where coalesce(value->>'rootLineId',value->>'id')=coalesce(l->>'rootLineId',l->>'id');
     end loop;
     if reserved<(l->>'quantity')::numeric then raise exception 'Deliver the full source item quantity before closure';end if;
    end loop;
   end loop;
  end loop;
 end if;
 if exists(select 1 from public.erp_process_stock(p_changes) n left join public.erp_process_stock('{}'::jsonb) o using(item) where n.balance<0 and n.balance<coalesce(o.balance,0)) then raise exception 'This posting would reduce available stock below zero';end if;
 for k,new_payload in select * from jsonb_each(p_changes) loop
  if new_payload is not distinct from p_expected->k then continue;end if;
  insert into public.erp_process_write_authorizations values(txid_current(),v_org,auth.uid(),k,p_expected->k,new_payload);
  perform public.erp_put_ui_state(k,new_payload);
 end loop;
 delete from public.erp_process_write_authorizations where transaction_id=txid_current() and organization_id=v_org and actor_id=auth.uid();
end; $$;
revoke all on function public.erp_commit_process(jsonb,jsonb,text) from public,anon;
grant execute on function public.erp_commit_process(jsonb,jsonb,text) to authenticated;
insert into public.erp_process_edges values('Purchase Orders','Purchase') on conflict do nothing;
insert into public.erp_process_edges values('Outward QC','Job Work Return DC') on conflict do nothing;
insert into public.erp_process_edges values('Job Work Inward','Job Work Return DC') on conflict do nothing;
insert into public.erp_process_edges values('GRN','Inward Quality') on conflict do nothing;
insert into public.erp_process_edges values('Purchase Orders','Import Purchase') on conflict do nothing;
insert into public.erp_process_edges values('Purchase Orders','Procurement Schedule') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Dispatch Schedule') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Production Schedule') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Project Planning') on conflict do nothing;
insert into public.erp_process_edges values('Job Order','Jobwork Material Issue') on conflict do nothing;
insert into public.erp_process_edges values('Job Order','Service Invoice') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Input to Production') on conflict do nothing;
insert into public.erp_process_edges values('Jobwork Material Issue','Input to Production') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Stage Receipt') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Stage Consumption') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Excess Issue') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Return to Store') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Dispatch Intimation') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Material Reserve') on conflict do nothing;
insert into public.erp_process_edges values('Material Reserve','Material Unreserved') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Terminate Order') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Project Order') on conflict do nothing;
insert into public.erp_process_edges values('GRN','Purchase Return') on conflict do nothing;
insert into public.erp_process_edges values('Purchase','Purchase Return') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Pick Slip') on conflict do nothing;
insert into public.erp_process_edges values('Inward QC','Put Away') on conflict do nothing;
insert into public.erp_process_edges values('GRN','Put Away') on conflict do nothing;
insert into public.erp_process_edges values('Production Output','In-process QC') on conflict do nothing;
insert into public.erp_process_edges values('Route Cards','In-process QC') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','In-process QC') on conflict do nothing;
insert into public.erp_process_edges values('Outsource Receipt','Job Work QC') on conflict do nothing;
insert into public.erp_process_edges values('Job Work Inward','Job Work QC') on conflict do nothing;
insert into public.erp_process_modules values('Indent To Order','["Indent No","Vendor","Item","Qty","Action Status"]'::jsonb,false,true,'{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb) on conflict(page) do nothing;
insert into public.erp_admin_storage_map values('dfab-process-Indent To Order','Indent To Order',0,-1) on conflict do nothing;
insert into public.erp_process_edges values('Indent To Order','Purchase Orders') on conflict do nothing;
insert into public.erp_process_edges values('Production Output','Scrap Entry') on conflict do nothing;
insert into public.erp_process_edges values('Rejection Note','Scrap Entry') on conflict do nothing;
insert into public.erp_process_edges values('Sales Orders','Procurement Planning') on conflict do nothing;
insert into public.erp_process_edges values('Work Order','Procurement Planning') on conflict do nothing;
insert into public.erp_process_edges values('Material Request','Procurement Planning') on conflict do nothing;
insert into public.erp_process_edges values('Sales Enquiries','Project Planning') on conflict do nothing;
insert into public.erp_process_edges values('Purchase Indents','Indent To Order') on conflict do nothing;
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Sales Enquiries';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Sales Quotations';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Sales Orders';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Purchase Orders';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Purchase Indents';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Awaiting QC","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='GRN';
update public.erp_process_modules set status_map='{"DRAFT":"Planned","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Work Order';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Material Request';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Issued","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Material Issue';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"QC Pending","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Production Output';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Outward QC';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Delivery Challan';
update public.erp_process_modules set status_map='{"DRAFT":"DRAFT","APPROVAL PENDING":"APPROVAL PENDING","APPROVED":"APPROVED","REJECTED":"REJECTED","RELEASED":"APPROVED","PASSED":"PASSED","ACCEPTED":"ACCEPTED","COMPLETED":"COMPLETED","DISPATCHED":"DISPATCHED","DELIVERED":"DELIVERED"}'::jsonb where page='Sales Invoice';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Purchase';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Job Work Inward';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Job Work Return DC';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Outsource Issue DC';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Outsource Receipt';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Inward Quality';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Inward Quality Rejection';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Rejection Note';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Sales Return';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Proforma Invoice';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Credit Note';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Disposed","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Scrap Entry';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Opening Stock';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Adjusted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Excess Stock';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Adjusted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Shortage Stock';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Inward QC';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Route Cards';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Received","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Import Purchase';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Procurement Planning';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Confirmed","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Procurement Schedule';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Ready","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Dispatch Schedule';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Production Schedule';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Active","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Project Planning';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Issued","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Job Order';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Issued","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Jobwork Material Issue';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Accepted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Jobwork Material Receipt';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Service Invoice';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Issued","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Input to Production';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Completed","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Stage Receipt';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Stage Consumption';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Issued","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Excess Issue';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Return to Store';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Sent","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Dispatch Intimation';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='BOM-Based Work Order';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Posted","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Stock Adjustment';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Reserved","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Material Reserve';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Material Unreserved';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Closed","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Terminate Order';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Running","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Project Order';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Returned","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Purchase Return';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Confirmed","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Pick Slip';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Completed","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Put Away';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='In-process QC';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Released","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Job Work QC';
update public.erp_process_modules set status_map='{"DRAFT":"Draft","APPROVAL PENDING":"Approval Pending","APPROVED":"Approved","REJECTED":"Rejected","RELEASED":"Open","PASSED":"Passed","ACCEPTED":"Accepted","COMPLETED":"Completed","DISPATCHED":"Dispatched","DELIVERED":"Delivered"}'::jsonb where page='Indent To Order';


-- COMPONENT: ERP_ZOHO_INVOICE_EMAIL
-- Additive. Apply after ERP_PRODUCTION_PROCESS_CONTROLS.sql.

create table if not exists public.erp_invoice_email_jobs(
 organization_id uuid not null references public.erp_organizations(id),request_id uuid not null,
 actor_id uuid not null,invoice_no text not null,recipient text not null,
 status text not null check(status in ('processing','sent','failed','unknown')),
 created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 primary key(organization_id,request_id));
alter table public.erp_invoice_email_jobs enable row level security;
revoke all on public.erp_invoice_email_jobs from public,anon,authenticated;
create or replace function public.erp_invoice_email_start(p_invoice text,p_to text,p_request uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_org uuid:=public.erp_current_org_id();v_doc jsonb;v_job public.erp_invoice_email_jobs%rowtype;
begin
 if auth.uid() is null or v_org is null or not public.erp_admin_can_page('Sales Invoice','view') or not public.erp_admin_can_page('Sales Invoice','export') then raise exception 'Invoice export permission required' using errcode='42501';end if;
 if p_to !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' or length(p_to)>254 then raise exception 'Valid recipient required';end if;
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||p_request::text,0));
 select * into v_job from public.erp_invoice_email_jobs where organization_id=v_org and request_id=p_request;
 if found then
  if v_job.invoice_no<>p_invoice or v_job.recipient<>lower(p_to) then raise exception 'Email request identity changed';end if;
  return jsonb_build_object('created',false,'status',v_job.status);
 end if;
 select payload->p_invoice into v_doc from public.erp_ui_state where organization_id=v_org and storage_key='dfab-process-Sales Invoice';
 if v_doc is null or v_doc->>'status' not in ('APPROVED','RELEASED') or coalesce((v_doc->>'legacy')::boolean,false) then raise exception 'A saved and approved invoice with verified lines is required';end if;
 if (select count(*) from public.erp_invoice_email_jobs where organization_id=v_org and actor_id=auth.uid() and created_at>now()-interval '1 hour')>=30 then raise exception 'Email limit reached. Try later';end if;
 insert into public.erp_invoice_email_jobs values(v_org,p_request,auth.uid(),p_invoice,lower(p_to),'processing',now(),now());
 return jsonb_build_object('created',true,'status','processing','invoice',v_doc,'organization_id',v_org);
end; $$;
create or replace function public.erp_invoice_email_finish(p_request uuid,p_org uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
begin
 if p_status not in ('sent','failed','unknown') then raise exception 'Invalid delivery state';end if;
 update public.erp_invoice_email_jobs set status=p_status,updated_at=now() where organization_id=p_org and request_id=p_request and status='processing';
end; $$;
revoke all on function public.erp_invoice_email_start(text,text,uuid),public.erp_invoice_email_finish(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_invoice_email_start(text,text,uuid) to authenticated;
grant execute on function public.erp_invoice_email_finish(uuid,uuid,text) to service_role;


NOTIFY pgrst, 'reload schema';

-- Current release: filters, feedback and audit fixes
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


-- Current live-audit release
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
-- Completed: reload the ERP frontend after deploying the matching updated folder.
