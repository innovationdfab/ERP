# Zoho invoice email setup

The frontend fix restores authenticated setup/send requests. Complete this configuration on the existing Supabase project if email is not already configured. Never add SMTP or service-role credentials to a `VITE_` variable or commit them to GitHub.

1. In Supabase Edge Function secrets, configure the actual company mailbox settings:

| Server setting | Required value |
| --- | --- |
| ERP_ALLOWED_ORIGINS | `https://erp-lyart-beta.vercel.app` plus any actual staging origins, comma separated; no trailing slash |
| ZOHO_SMTP_HOST | Your Zoho account's regional SMTP hostname, for example `smtppro.zoho.in`; use the one shown by your account |
| ZOHO_SMTP_USER | Full sender mailbox address |
| ZOHO_SMTP_PASSWORD | Its SMTP/app password |
| ZOHO_FROM_EMAIL | Authorized sender address; optional when identical to SMTP user |

Supabase normally provides `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` to its Edge Function runtime. Keep these on the server. The function uses TLS SMTP on port 465.

2. From this project root, with the Supabase CLI signed into the intended account, deploy to your existing project:

```sh
supabase functions deploy erp-invoice-email --project-ref YOUR_EXISTING_PROJECT_REF
```

Use your actual project reference from Supabase settings. Keep JWT verification enabled. This command is for the user to run after selecting the correct account/project; no automatic deployment is performed by this package.

3. In ERP, open a saved approved/released Sales Invoice → Workflow → **Check email setup**. Missing setting names, an undeployed service or permission/network errors now show distinct messages. If this already says configured, do not replace working credentials.
4. Enter a known test recipient and send once. Verify Zoho Sent and receipt by the recipient. A configured status cannot prove delivery. The copy is escaped HTML with an HTML attachment; PDF/IRN generation is not part of this mail service.
5. If the result is unknown, check Zoho before deliberately starting another attempt. Reusing the same request ID does not automatically resend the message. Review `PRODUCTION-FLOWS-UPDATE.md` for existing send limits and permission requirements.
