# Pickup is named Fetch — autofill fix

The complete folder includes the active **Fetch** button, its source picker and its data-transfer logic. It remains available on registers, opened records and editors for the 20 existing transaction pages with configured sources. Other pages and existing workflow routes are retained.

## Use it

1. Click **Fetch**.
2. Choose the source type and a reviewed, approved/released document saved in this ERP.
3. Pending items and quantities select automatically. Untick unwanted items or adjust quantities as needed.
4. Click **Fetch selected items**. Matching party information, reference numbers/dates, compatible header fields, product descriptions, quantities, UOM, prices, discounts, taxes, HSN and drawing/specification data fill the form.
5. Review and Save as Draft or submit through the existing release/approval process. Fetch itself never writes a transaction automatically.

When replacing existing lines, the replacement checkbox remains required. Cancel/Escape preserves the existing page and data. A supplier is still chosen explicitly when a customer document is used for purchasing; a customer is not invented as the supplier.

## Corrected behavior

- Choosing a source automatically selects its pending items and quantities. An existing fetched record opens with its current source type selected.
- Re-fetching refreshes values that Fetch originally populated, including the matching party. Manual edits remain intact. Obsolete automatically populated values are cleared when the new source does not provide them; reference identities follow the chosen source.
- Earlier Fetch records are supported conservatively using their saved source when available. Manually changed parties still require reconciliation. The existing currency mismatch guard remains enforced; no currency conversion is installed.
- A new, unassigned destination uses the next department for the fetched manufacturing/labour flow. Existing saved or assigned tasks are retained.
- Fetched data opens as an editable draft. Its total is immediately recalculated from the fetched lines and retained destination charges/adjustment, including when the destination was an older summary record.
- Source choices derived from an SOP must match that source's actual flow and route-output option. Fetch cannot use the alternative labour QC path for a manufacturing QC record or bypass the route-card output choice. The original reference-specific source choices remain supported.
- Saving retains the existing atomic document/source/link checks. Replacing the saved source replaces its inbound link and frees the old source reservation. Over-fetching, missing source lines, unreleased sources, circular references and changed product/UOM identity remain rejected.

Reviewed original source lines are required. Summary-only historical sources are not converted into invented quantities or prices. This is a fetch from documents saved in the configured ERP, not automatic ongoing import from the reference website.

## Setup and verification

Keep the existing `.env` and database. No new SQL migration is needed beyond the existing process-upgrade setup. Extract this updated ZIP into a fresh folder, stop the old development server, run `npm ci` and `npm run dev`; rebuild/redeploy for a hosted site.

`AUTOFILL-VERIFICATION.json` records the current unit/browser checks and the exact archive comparison. Existing menus, fields, styles, SOP graph, database adapters, approvals, payment logic, attachments and other working flows are not replaced by this fix. The original production accounting/inventory/integration limitations still apply.
