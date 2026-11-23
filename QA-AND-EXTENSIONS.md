# QA and ERP Extensions

Base file — `DFAB-OneERP-Employee-Passwords-Login-Only (2).zip`.

## Repairs

- Settings reports success after a confirmed save and observes the assigned create/edit permission.
- Change Password provides the actual Supabase password-change form, current-password submission and verification-code flow.
- Products, accounts, BOMs, route masters and seal uploads save their register and details together in a confirmed database batch.
- Work-centre edits update the existing record.
- Price lists and the vendor price report read the same saved prices.
- Pending Approvals lists submitted transaction records and opens the referenced register. Activity Log and User Wise Transactions read scoped database audit records.
- Backup restore uses a validated transactional database operation.
- Form controls have explicit accessible names where implicit labels included select options or suggestion lists.
- Fetch and typed references leave actual receipt, output and payment entry fields for staff. Source references and available descriptive values still populate supported blanks.
- A procurement schedule retains the original PO reference when creating a receipt draft.

## Added section

| Page | Working behaviour |
| --- | --- |
| Reorder Planning | Save/edit an active product's reorder point, target, preferred vendor and lead time. Calculates the suggested quantity from posted stock, open PO quantities, receipts and unconverted indents. Creates a saved draft Purchase Indent. The new request is included in subsequent calculations to prevent repeat requests. |
| Receivables Ageing | Approved invoice balances as of a selected date, with posted dated receipts and credit notes. Buckets cover current, 1–30, 31–60, 61–90 and 90+ days. Missing due dates are identified. CSV export uses the filtered records. |
| Collection Follow-ups | Save and edit invoice-linked internal notes, owner, contact method, next date and Open/Done status. Settled invoices show their settlement state in the follow-up register. |
| Customer Statements | Select a customer, currency and as-of date. View and export invoice settlement summaries and open the referenced invoice register. |

Quantities use the saved product's base UOM. Matching uses product codes first and unique descriptions second. Duplicate descriptions require a product-code reference. Currency totals stay within the selected currency. Legacy invoices with no saved currency display Unspecified. An invoice's Due Date can be entered under Additional details. Allocations missing a valid date or amount require verification and are flagged in the finance views.

## Permissions and SQL

Run `supabase/ERP_QA_EXTENSIONS_UPDATE.sql` after the existing production, flow-integrity, guardrail, admin-control, admin-operations and initial-password-policy migrations. The combined update includes `ERP_WORKSPACE_INTEGRITY.sql` and `ERP_EXTENSIONS.sql`.

The extension uses the existing organization-scoped `erp_ui_state` storage and compare-and-swap save functions. It adds page and storage mappings plus server validation for reorder policies and collection follow-ups. Existing transaction rows and employee identities are retained.

| Page | Required source view permissions |
| --- | --- |
| Reorder Planning | Products, Vendors, Purchase Indents, Purchase Orders, GRN, Opening Stock, Material Issue, Return to Store, Purchase Return, Excess Stock, Shortage Stock, Production Output, Scrap Entry, Stock Adjustment |
| Receivables Ageing, Collection Follow-ups, Customer Statements | Sales Invoice, Customer Payments, Credit Note |

Each page also requires its own view permission. Policy and follow-up changes use their own create/edit permissions. Creating a replenishment indent requires Purchase Indents create access. CSV download requires the section's export permission. Admin Control supplies these rights through the existing role editor.

## Verified results

On 23 November 2026, lint, the configured JavaScript type check, 101 unit tests and the production build passed. The authenticated page audit opened 185 routes and generated 77 reports. The form sweep opened 94 create forms and their sections on desktop and mobile. Transaction regressions opened 30 reference forms and two further forms, then exercised Fetch, approvals, production release, receipt QC, posted stock, invoice calculations and payment settlement. The upload/import suite, extension suite and temporary PostgreSQL suite passed.

## Verification scope

`npm run verify` covers lint, the configured utility-module type check, unit tests and production compilation. Browser tests cover every menu route, all report Generate actions, reachable create forms and their sections, desktop/mobile overflow, Fetch, saved attachments, master persistence, transaction status gates, posted stock reporting, invoice calculations and settlement. Extension tests cover reload persistence, draft replenishment, duplicate prevention, credit allocations, CSV export, follow-up edits, invoice navigation, mobile widths, failed saves and missing source permissions.

Database tests apply and reapply the migrations in temporary PostgreSQL. They cover staff/admin boundaries, optimistic concurrency, atomic handoff and rollback, restore rollback, extension record validation and restricted records.

The page/form sweep opens reachable controls. Representative transaction suites exercise saved actions and status progression. End-to-end verification of every combination of production data, customized workflow and employee role requires the staging environment. External services and production deployment are outside these local fixture checks. The Vite build retains a bundle-size warning and upstream lucide-react directive warnings.

## Official feature references

The additions adapt these documented patterns to OneERP's existing records and theme.

- Reorder levels and preferred vendors — https://www.zoho.com/inventory/help/items/additional-features.html
- Inventory settings — https://www.zoho.com/en-in/erp/help/settings-and-configuration/general-module-settings/items-settings.html
- Receivable follow-ups and payment dates — https://www.zoho.com/en-in/erp/help/settings-and-configurations/setup-and-configurations/reminders.html
- Customer statements — https://www.zoho.com/en-in/erp/help/customers-and-vendors/operations.html

This release provides features inside OneERP. A Zoho account synchronization service would require organization-specific OAuth credentials and API configuration.

## Extension layout repair

Text actions use content-sized buttons and a dedicated action container. The Actions column stays visible during horizontal scrolling. The results area has its own bounded scroll region, and filters, form controls and pagination use consistent spacing. The shared text-action styling also protects labelled buttons in other row-action groups.

Populated action labels, horizontal access and bounded table scrolling passed at 320, 390, 768, 1024, 1280 and 1440 pixels on all four extension screens. The workspace audit passed 185 routes and 77 reports. Build, lint, the configured type check and 101 unit tests passed. The requested localhost address returned a connection-refused error from the cloud browser. Tests used the project copy with isolated Supabase responses.
