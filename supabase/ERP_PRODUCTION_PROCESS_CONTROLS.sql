-- Apply after ERP_WORKSPACE_INTEGRITY.sql and DFAB_PROCESS_UPGRADE.sql. Additive; no business records are rewritten.
begin;
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
commit;
