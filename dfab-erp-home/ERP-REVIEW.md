# DFAB OneERP · Production Architecture Review

## Existing frontend preserved

The navigation, masters, transactions, reports, forms and current screen structure are retained. The production update changes the data foundation and workflow controls without deleting unrelated flows.

## Production interconnections

### Commercial / Order-to-Cash
CRM/Enquiry → Quotation → Sales Order → Work Order → Production → Outward QC → Dispatch → Sales Invoice → Customer Receipt.

### Procurement / Procure-to-Pay
Purchase Indent → Indent-to-Order → Purchase Order → GRN → Inward QC → Purchase Invoice → Vendor Payment.

### Engineering / Manufacturing
Product Revision → Approved BOM + Released Route → Work Order → Material Request → Material Issue → Route Operations → Production Output → QC → Finished Goods.

### Outsourcing
Work Order/Route operation → Outsource Issue DC → Vendor process → Outsource Receipt → Quality → Work Order continuation.

### Inventory
Stock is derived from immutable location-to-location movements, not from manually overwritten balance fields. GRN acceptance, material issue/return, production receipt, scrap, dispatch, sales return and adjustments each create auditable movements.

### Finance
Customer/vendor payments are allocated against invoices. Receivables and payables are derived from invoice total minus allocated/received amount.

## Database controls

The new `supabase/DFAB_ERP_PRODUCTION.sql` defines fresh `erp_*` production objects, organization isolation, Auth-linked profiles, role/permission tables, server-side document numbering, audit triggers, approvals, attachment metadata, stock and outstanding views, plus UI persistence RPCs.

The earlier SQL files are intentionally not part of this build.
