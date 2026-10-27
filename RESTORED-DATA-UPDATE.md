# Restored database data update

This build restores the pre-clean ERP data from the earlier DFAB ERP folder into the Supabase-backed UI state exactly once.

## Restored sections
- Product groups, products, UOMs, product types, product categories and HSN master
- Production BOM and Route Card masters
- 220 customer master records
- 422 vendor master records
- Production process master, workcenters and machines
- Existing sales/purchase/quality/production/payment transaction examples from the earlier ERP build
- 84 earlier sales invoice records
- Users, role permissions and activity records that existed in the previous frontend dataset

## Restore behavior
The restore is additive. Existing Supabase records are preserved and missing records are merged by their primary display identity. A cloud marker (`dfab-restored-preclean-data-v1`) is written after the restore so deleting records later will not re-seed them on every login.

## Authentication/session
The email is remembered locally. Supabase access/refresh tokens are used to restore the session after refresh/reopen, so the login page is not shown again while the session is valid. Logout clears the persistent Supabase session. Passwords are never stored by this frontend.
