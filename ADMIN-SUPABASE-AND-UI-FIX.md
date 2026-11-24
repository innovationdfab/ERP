# Admin-only release: fixed navigation and Supabase diagnostics

Base: DFAB-OneERP-Admin-Premium-Navigation-Logins.zip.

Only Admin-specific `src/admin-api.js`, `src/admin-control.jsx`, `src/admin-control.css`, and `supabase/functions/erp-admin-invite/index.ts` changed. No shared backend, login, transaction, workflows, schemas, or other pages were edited.

## What changed
- Fixed-height Admin navigation on desktops; its navigation list and the Admin content scroll separately. On small screens the layout returns to the standard responsive view.
- Removed duplicate Admin dashboard action cards, setup walkthrough, workflow promotions, and extraneous footer information. All original Admin sections stay accessible from the left panel.
- The Admin employee-login Edge Function returns a visible 403 error for disallowed browser origins while continuing to reject unauthorized origins. Redeploy this function to activate the change.
- Admin RPC and employee-login Edge Function network failures now identify the failing endpoint and deployed project configuration, with explicit advice not to retry a possibly committed write blindly. No automatic mutation retries.

## Required deployment checks for `Failed to fetch`
1. On Vercel, confirm `VITE_SUPABASE_URL=https://<project-ref>.supabase.co` and `VITE_SUPABASE_PUBLISHABLE_KEY` (or legacy anon key) match your active Supabase project, including Production environment, then redeploy. Do not place service-role secrets in the frontend.
2. Inspect browser Developer Tools > Network for the failing request. `/rest/v1/rpc/erp_admin_dashboard` implies an RPC/network/project issue; `/functions/v1/erp-admin-invite` implies Edge Function reachability or CORS preflight.
3. In Supabase confirm project is active and the `erp-admin-invite` function is deployed; the function must return correct `Access-Control-Allow-Origin`, `Access-Control-Allow-Headers`, and respond to OPTIONS from the deployed Vercel origin.
4. A HTTP error response (401/403/404/500) is a distinct problem from Failed to fetch. Do not rerun SQL merely for a network error.
5. After failed creation, refresh Saved logins and inspect Supabase Auth users before retrying to avoid duplicates.

Live Supabase was not modified or accessible through this source-only release. The new messages help isolate the fault but cannot resolve wrong deployment secrets, project outages, or missing CORS headers without configuration changes.
