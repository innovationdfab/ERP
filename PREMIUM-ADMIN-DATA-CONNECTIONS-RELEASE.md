# DFAB OneERP — Premium Admin and Transaction Form Update

## Scope and preservation
This update builds on `DFAB-OneERP-Simple-Admin-UI.zip`. It does not replace the ERP navigation, Supabase authentication, SQL schema, stored-data keys, module configurations, saved records, reports or original document statuses. Published workflow changes still require the previously installed `ERP_ADMIN_CONTROL.sql` and authorized administrator credentials.

## New Admin > Data connections
- Inspect a source document and see its currently configured next-document link.
- Identify its existing Supabase-backed storage section, with record counts taken from the authenticated session's current snapshot. Master data and invoice sections have explicit legacy-key aliases.
- Display configured source-field → destination-field mappings, plus matching-name fields. These are explanations of the current configuration, **not a guarantee that a document can be posted**.
- Follow incoming and outgoing document links; inspect known report sources, including registered i-MANTRA reports and built-in report mappings.
- Jump to the existing workflow draft/publish editor for changes. The viewer itself is read-only, introduces no new database data and does not bypass server permissions.

## Form improvements
- All existing generic transaction forms show grouped source/reference, party/item, quantity/cost and scheduling fields instead of one large undifferentiated grid.
- The number, name, type and storage key of every saved form field remain unchanged.
- Selected stored references show a read-only source summary. Auto-filled values never replace already-entered values except the selected field itself, following existing behavior.
- Vendor Payment invoice suggestions and auto-fill now use the Purchase Invoice section, not Sales Invoice; Customer Payments keep sales-invoice suggestions.
- Custom published workflow mappings can override the default reference copying, except mandatory production quantity defaults and initial statuses, which remain guarded.

## i-MANTRA reference coverage
The supplied single-page i-MANTRA PDF lists transaction/report categories, but **does not contain exact field layouts, field validations or business form screenshots**. This release preserves the fields from the current ERP and restructures their presentation. Do not interpret it as a faithful reconstruction of hidden reference-site forms.

## Verification / deployment limits
- Unit and source-contract tests must be run with `npm test`.
- Before deployment, install project dependencies and run `npm run verify`. In this execution environment, dependency installation could not finish, so full Vite/lint verification and live browser testing were not completed.
- Existing backend type-check diagnostics still affect `cloud-store.js` and `supabase-rest.js` (see earlier production engineering review); not changed here.
- A live Supabase staging account is required to verify Admin active templates, cross-department roles and end-to-end saves before production rollout.
- No additional SQL migration is required for this UI / inspection release. **Do not rerun fresh-database SQL on the existing company project.**

## Local setup
1. Extract the ZIP.
2. Copy existing private Supabase variables into `.env` locally; do not commit it.
3. `npm ci` then `npm run verify`, and `npm run dev`.
4. Log in with an authorized Admin account; open Admin Control → Data connections.
5. Pick a document, inspect its storage and next-step rules, and verify with a test draft in staging before publishing.
