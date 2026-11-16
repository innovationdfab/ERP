# DFAB OneERP — Automated registered workflow connections

## Scope

This release is based on the DFAB OneERP Premium Admin Header Aligned build. No existing business module, database SQL, reports, login, form, stored data key, or other navigation component was rewritten.

**UI change:** Removed the redundant Admin Control button from the left sidebar. The Admin button remains in the header, immediately before Search.

**Admin automation:** Added a workflow builder in Admin → Document flows and a shortcut on Admin Home. It reads the authenticated Supabase admin catalog, discovers `default_next` for each eligible transaction document, and generates a complete **draft** with:
- All catalog-registered source → destination steps (currently 40 in the bundled reference catalog).
- The configured `default_gate_statuses` from Supabase, when present and valid.
- Compatible existing source-to-destination field mappings (currently 91 in the bundled reference catalog).
- No guessed financial amounts, QC output quantities, status values, employee names, or generated document numbers.
- No made-up links between reports/masters or terminal pages.

## How to use

1. Sign in with an authorized ERP administrator account.
2. Click **Admin** in the top header (before Search).
3. Open **Document flows**.
4. Select **Generate all flows**. This builds an editable draft in memory and reports its coverage.
5. Review every connection, required status and auto-fill mapping; adjust exceptions if your DFAB process differs from the built-in catalog.
6. Click **Save draft**. This uses the existing `erp_admin_save_template` Supabase RPC.
7. From the saved-draft list, click **Publish** and confirm in the in-app dialog. This uses `erp_admin_publish_template` and causes the app to reload `erp_admin_active_workflow`.
8. Open an affected transaction page and inspect the **Connected flow → ...** hint and forward action. When the source document meets its status/field requirements and the user's role permits creation, the linked record is saved using the existing atomic workflow batch.
9. Other signed-in staff will refresh published routing when returning focus to their ERP browser tab (or on their next sign-in). Existing documents are **never silently converted** by this template generator.
10. To revert, select **Use original flow** in Admin → Document flows. This calls the existing `erp_admin_reset_workflow` RPC.

Only an authenticated administrator can Save, Publish, Reset or edit company configuration. The no-login Admin preview remains read-only.

## Why no additional SQL migration?

The existing `supabase/ERP_ADMIN_CONTROL.sql` already defines the organization-scoped page catalog, draft/published workflow templates, per-source edges, status gates, audit log, Supabase RPC save/publish/reset, and server-side verification of source/target documents during atomic creation. This update uses those installed functions. **Do not run fresh-install scripts over a production database.** If the Admin functions are missing, stage and apply the existing admin migration according to `ADMIN-CONTROL-DEPLOYMENT.md` before enabling the builder.

## Technical limits and validation

- Registered catalog links: **40 of 40** in the current bundled reference. There are other master, report and terminal screens that do not have a valid next transaction; they are intentionally not linked.
- Compatible safe field mappings: **91** from current bundled catalog. The published result depends on the actual live Supabase catalog, which can differ.
- Automated tests: **71/71 passing** (including six dedicated workflow-generator tests).
- React JSX syntax: checked using the TypeScript parser; CSS syntax: checked with `tinycss2`.
- Full `npm ci`, Vite build and lint: **not verified** (package installation timed out in this execution environment).
- Real Supabase save/publish, role/RLS, multi-user refresh, inventory posting and end-to-end browser navigation: **not tested against the user's live or staging database**.

Required release acceptance on a staging database: publish one generated template, verify both Admin audit events and the active workflow RPC, test source status gating, map at least one sales and purchase source reference, confirm no duplicate downstream document, verify failed writes do not create orphaned links, test department access rights, then reset to built-in and confirm rollback.

## ERP patterns reviewed online

- SAP Help — invoice verification and PO/GRN/invoice controls: https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/f3419342409c4a7cb0b2d27f801d38b1/ab6fb6531de6b64ce10000000a174cb4.html?locale=en-US
- Odoo 19 — warehouse receive/quality/store steps: https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/warehouses_storage/inventory_management/use_routes.html
- Odoo 19 — manufacturing work-order dependencies: https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/manufacturing/advanced_configuration/work_order_dependencies.html
- Odoo 19 — quality checks tied to manufacturing and inventory: https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/quality/quality_management/quality_checks.html

These references informed the conservative approval/lineage behavior. Exact DFAB paths are generated from **DFAB's existing registered catalog**, not copied wholesale from other products.
