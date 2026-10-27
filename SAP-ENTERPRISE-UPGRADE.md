# DFAB OneERP — SAP-inspired Enterprise Upgrade

This build keeps the existing Supabase schema, restored data, module routes, and workflow logic intact while upgrading the UX toward an enterprise ERP operating model.

## Added
- Executive process-status strip on Home: My Inbox, Sales Orders, Purchase Orders, Work Orders, and QC Queue.
- SAP/Fiori-inspired visual hierarchy for shell, cards, tables, forms, statuses, dialogs, and actions.
- Object-page lifecycle strip on generic transaction/report pages showing record counts, next connected process, and persistence source.
- Denser enterprise table presentation and consistent semantic status colors.
- Responsive behavior for desktop/tablet/mobile.

## Preserved
- Supabase database schema and SQL.
- Existing restored ERP data.
- Authentication and persistent session behavior.
- Existing module routes, navigation, forms, reports, notification logic, and document handoff logic.

## Verification
- `npm test`: 6/6 passing.
- `src/backend/cloud-store.js`: syntax check passed.
- `src/backend/supabase-rest.js`: syntax check passed.
- Full Vite build could not be executed in the packaging environment because dependencies were not installed (`vite: not found`). Run `npm install && npm run verify` locally before production deployment.
