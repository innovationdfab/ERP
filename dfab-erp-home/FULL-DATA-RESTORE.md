# DFAB OneERP - Full Legacy Data Restore

This build restores the full operational data set found in the pre-clean ERP source and merges it into the current Supabase-backed workspace after a successful authenticated session.

## Restored sections

- Products: 2,118 legacy product rows
- Customers: 220
- Vendors: 422
- Sales invoices: 84
- Product groups: 51
- UOMs, product types, categories, HSN master
- Production BOM and route-card master rows
- Processes, work centres and machines
- Sales enquiries, quotations and sales orders
- Purchase indents, purchase orders, GRN and inward QC
- Work orders, route cards, production output and outward QC
- Delivery challan, approvals, customer/vendor payments
- Users, role permissions and activity history

Total list-style records in the restoration payload: 2,976 across 32 cloud sections.

## Migration behavior

The migration key is `dfab-restored-preclean-data-v2-full`.

On the first successful login with this build:

1. Current Supabase state is loaded.
2. Existing records are retained.
3. Legacy records missing by identity/code are merged in.
4. Changed sections are saved through the authenticated Supabase RPC.
5. The v2 migration marker is written only after queued cloud writes complete.

The marker prevents the old dataset from being recreated after future intentional deletes.

## Login behavior

- Email can be remembered by the app/browser.
- Password uses standard browser password-manager autofill and is not stored by the ERP.
- Supabase refresh-token session is restored on refresh/reopen.
- While a saved session is validated, the ERP boot screen is shown instead of the login screen.
- Login returns only when the session is invalid/revoked or the user clicks Logout.
