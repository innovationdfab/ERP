-- DFAB OneERP Admin Control Center. ADDITIVE migration; run after
-- DFAB_ERP_PRODUCTION.sql, ERP_FLOW_INTEGRITY_UPGRADE.sql and
-- ERP_PRODUCTION_GUARDRAILS.sql. Test with a staging backup first.
-- IMPORTANT: Existing ADMIN assignments are NOT silently revoked. Review and
-- demote unwanted admins in the new panel before enabling broad staff access.
begin;

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

commit;

-- Refresh PostgREST function metadata after the migration is committed.
notify pgrst, 'reload schema';
