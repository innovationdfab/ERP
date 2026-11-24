# Update this ERP

1. Run **RUN-THIS-UPDATE.sql** in your existing Supabase project. This is the single update file for this release.
2. Deploy this frontend folder through your existing GitHub/Vercel workflow. Keep your existing Supabase URL/publishable key. Node 24 is required.
3. Deploy the updated `erp-invoice-email` Supabase Edge Function; see **ZOHO-SETUP.md**. Frontend deployment alone does not update it.
4. In ERP → Workflow Guide → Existing data reconciliation → **Check database update**. In a saved Sales Invoice → Workflow → **Check email setup**.

Read **LIVE-FIXES-UPDATE.md** for changes and setup, and **LIVE-FIXES-QA.md** for verified results. Existing data and unrelated flows are preserved. Only original documents and your server settings can supply genuinely missing historical values or credentials.

`DFAB-OneERP-All-In-One.sql` is for a fresh installation. For this deployed update, use RUN-THIS-UPDATE.sql instead.
