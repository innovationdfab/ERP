# Fetch and compact transaction forms — 2 November 2026

This update changes Fetch and transaction-form usability only. The existing SOP stage graph, Continue actions, masters, menus, dashboard, login, reports, tax calculations, database migration and cloud API files are retained from the previous ZIP.

## Use Fetch

1. Open a supported transaction and choose Create new or Edit, then **Fetch** in the fixed action bar.
2. Choose a source type. Search by document number, party or product; dates narrow the source list.
3. Choose a released/approved source. Select individual lines or all pending lines, then enter the quantity to fetch for each selected line.
4. Choose **Fetch selected items**. Existing product lines and the source link require an explicit replacement checkbox. Cancel and Escape leave the form unchanged.
5. Review Items, Details and Assignment, then Save. Fetch itself makes no database write. Saving reserves the selected quantities, persists the source link and uses the existing atomic save mechanism.

Fetch copies quantities, descriptions, UOM, rates, discounts, GST splits, HSN, group/type, drawing/revision and line remarks from selected items. Compatible header fields and aliases populate empty destination fields; document reference numbers/dates follow the source lineage. Entered header values, destination assignment, charges, operations, inspection results and attachments are retained. A supplier must still be chosen when a customer document is fetched into purchasing. Conflicting parties or currencies require reconciliation.

Older summary records are excluded until their original line details have been reviewed, saved and released in the expanded workspace. Fetch does not invent missing original prices, line identities or quantities. Existing unlinked historical transactions need reconciliation before their quantities can be represented as already fetched. This feature fetches documents saved in this project's configured ERP; it does not install ongoing synchronization with the reference website.

## Reference Pickup choices inspected

The signed-in reference's Pickup window displayed selection, date/document, party, product, source quantity, picked quantity, pending quantity and editable pickup quantity columns. Its button is named **Fetch** in this project.

| Destination | Reference source choices |
| --- | --- |
| Sales Quotations | Sales Orders; Sales Enquiries |
| Sales Orders | Sales Quotations; Job Work Inward |
| Purchase Orders | Purchase Indents; Outsource Issue DC |
| GRN | Purchase Orders |
| Purchase | GRN |
| Work Order | Sales Orders; Rejection Note |
| Production Output | Work Order |
| Outward QC | Production Output |
| Delivery Challan | Sales Orders |
| Sales Invoice | Sales Orders |
| Proforma Invoice | Sales Orders |
| Sales Return | Sales Invoice |
| Credit Note | Sales Invoice |
| Outsource Receipt | Outsource Issue DC |
| Inward Quality | Job Work Inward |
| Material Issue | Material Request |

The existing SOP sources are additionally available where applicable, including inward QC, route cards, outward QC and delivery challan handoffs. For manufacturing inward QC → Work Order, use the existing **Continue to Work Order** action: it restores finished sales-order items instead of copying inspected raw materials. The SOP graph and that action are unchanged.

Purchase Indents, Sales Enquiries, Outsource Issue DC, Job Work Inward, Job Work Return DC, Material Request, Rejection Note, Inward Quality Rejection and stock-adjustment forms had no generic Pickup button in their inspected creation forms. The reference Inward QC and Route Cards use distinct source/register flows. This update does not fabricate reference Pickup choices for those pages; applicable existing SOP sources remain available.

## Quantity and traceability rules

- Quantities are reserved per source line and destination transaction type. Two different lines with the same product code remain distinct.
- Saved drafts and released records consume pending quantities. Rejected records do not. Editing a document excludes its own reservation.
- Older Continue-created children are recognized through retained line identities.
- Save rechecks remaining quantity, source release status, product/UOM identity and line existence. The existing atomic compare-and-swap also guards the source payloads, destination collection and lineage collection, rejecting stale/concurrent saves.
- Product-code/UOM changes on fetched lines must be reconciled against the source; create separate unlinked lines for unrelated products.
- Source links are written in the same commit as the document. Existing guards against editing a source with downstream records or deleting linked documents remain active.

These are document quantities, not stock-availability or accounting postings. The production limitations in START-HERE-SOP.md still apply.

## Navigation and scrolling

All 30 transaction forms now use **Details / Items / Quality (where applicable) / Assignment / Attachments / Workflow** sections. Header fields are grouped into pages of up to 12 fields. Previous/Next section controls and Save/Submit/Fetch stay outside the content scroller. Validation opens the relevant section and required header-field page. Document registers keep filters and pagination fixed with an internal table scroller.

Desktop pages avoid whole-form scrolling. Long tables and small screens scroll inside the active content panel so every field remains accessible. Wide line-item tables keep their horizontal scroller. Masters, reports and other unrelated pages retain their existing layouts.

## Setup and validation

No new database migration is needed beyond the existing `supabase/DFAB_PROCESS_UPGRADE.sql` from the previous upgrade. Keep the existing Supabase configuration. Run `npm ci`, then `npm run dev` or `npm run build` as before.

Validation results and preservation counts are recorded in FETCH-LOCK-CHECK.json after the final checks. The integration test uses a mocked Supabase transport locally; it does not change live company records.
