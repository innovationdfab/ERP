# Supabase session and Vercel deployment update

The Activity Log screenshot shows an authorization error. The previous app refreshed the session during page restoration, so an open tab could continue using an expired access token. This update renews the saved session before expiry and on return to the tab. A database or function request rejected with 401 gets one token renewal and retry. Simultaneous requests share the renewal, and supported browsers coordinate renewal across tabs. The rotated refresh token is saved. Revoked sessions return to login. Temporary network failures preserve the saved session, and uncertain network outcomes are surfaced for verification.

The Vercel screenshot shows Ready and a Node.js Version Override warning. The project and lockfile now specify Node.js 24.x, and the CI workflow uses Node 24.

## Vercel update

1. Replace the repository files with this updated folder and push to the connected main branch.
2. In Vercel Project Settings, open Build and Deployment and select Node.js 24.x.
3. Confirm the project root is the folder containing package.json. Use the Vite framework preset, build command `npm run build` and output directory `dist`.
4. In Environment Variables, confirm `VITE_SUPABASE_URL` and `VITE_SUPABASE_PUBLISHABLE_KEY` point to the same existing Supabase project. The frontend uses a publishable key or the legacy anon key in `VITE_SUPABASE_ANON_KEY`.
5. Apply the environment variables to Production and any Preview deployments you use, then redeploy the updated commit. Vite embeds these values when it builds the application.
6. Sign in once on the deployed domain. Check Activity Log, a saved transaction and reopening the tab after it has been idle.

A secret or service_role key belongs in server-side configuration. The browser environment uses the publishable or anon key.

## Database requirements

This session update uses the existing Supabase tables and RPCs. The earlier workspace and extension SQL remains in `supabase/ERP_QA_EXTENSIONS_UPDATE.sql`. If a response specifically names a missing `erp_workspace_activity` function or a schema-cache error, apply that earlier migration after its prerequisites in README.md. The screenshot's 401 response alone does not establish a missing migration.

A 403 response requires reviewing the employee's active role and module permissions. The session renewal code preserves permission errors and does not grant extra rights.

## Verification

The release includes `tests/session-refresh.test.js` and `tests/browser-session.mjs`. These check expiry, coordinated refresh, rotated-token persistence, recovery of Activity Log after 401, subsequent saved changes, forbidden requests, revoked sessions, network failures and late refresh responses after the login changes. The login and workspace regression suites check the existing entry points with isolated Supabase responses.

Live Supabase settings and the Vercel dashboard have not been changed by this update. Deployed verification requires the updated commit and the project settings above.

## Official references

- Supabase session lifecycle — https://supabase.com/docs/guides/auth/sessions
- Supabase refreshSession — https://supabase.com/docs/reference/javascript/auth-refreshsession
- Vite build-time environment variables — https://vite.dev/guide/env-and-mode
- Vercel Node.js versions — https://vercel.com/docs/functions/runtimes/node-js/node-js-versions
