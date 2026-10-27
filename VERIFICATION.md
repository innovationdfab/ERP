# Verification

Completed in the build environment:

- `node --check src/backend/cloud-store.js` — PASS
- `node --check src/backend/supabase-rest.js` — PASS
- `node --test tests/erp-utils.test.js` — PASS (6/6)
- Production SQL contains 65 `erp_*` tables and 11 ERP functions/RPCs.
- Only one SQL setup file is present: `supabase/DFAB_ERP_PRODUCTION.sql`.
- No references to the earlier SQL setup files remain in the project documentation/code.

Not completed in this environment:

- `npm ci` timed out twice while downloading/installing dependencies, so lint and the Vite production build could not be executed here.

Run locally after extracting:

```powershell
npm install
npm run verify
```
