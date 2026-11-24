# DFAB OneERP — production engineering assessment and release checklist

## Baseline and scope

Source: `DFAB-OneERP-iMANTRA-Features-Integrated.zip`. Existing JSX pages, CSS,
login UI, routing, business modules, restored seed data, and core form mappings
were deliberately not modified. This package makes scoped persistence changes and
adds an **opt-in** additive SQL migration. It is not a declaration of full ERP
production readiness.

## Improvements implemented in this package

1. Generic queued writes now use compare-and-swap with the last **confirmed**
   Supabase payload where the integrity RPC is installed, instead of blindly
   overwriting it. Pending optimistic values no longer become database-version
   expectations. Every confirmed success updates a separate committed snapshot.
2. Subsequent writes are stopped after a failed write, rather than using a
   poisoned in-memory snapshot and silently replacing newer data. Logout already
   refuses to continue when the save queue failed. Recovery requires reload and
   reconciliation with Supabase.
3. Deleting a state section uses a compare-and-swap deletion RPC when installed.
4. Connected downstream documents fail closed when the required **atomic batch
   RPC** is unavailable, rather than sequentially writing only part of a handoff.
5. Optional `ERP_PRODUCTION_GUARDRAILS.sql` restricts UI-state writes to users
   with `ERP.EDIT` in their organization, adds CAS deletion, adds audit records,
   keeps the derived record mirror consistent on delete, and preserves duplicate
   source row IDs in the mirror.
6. No existing users, data rows, role assignments, CSS or navigation were removed.

## Required rollout order

1. **Back up the production database** (including roles, memberships, JSONB UI
   collections, invoice details and workflow links). Restore the backup to a
   separate staging Supabase project; test database restoration.
2. Apply `supabase/ERP_FLOW_INTEGRITY_UPGRADE.sql` to staging (unless already
   applied), then `supabase/ERP_PRODUCTION_GUARDRAILS.sql`.
3. Audit `erp_profiles`, `erp_roles`, `erp_user_roles`, and `erp_role_permissions`
   for every real employee. **Existing seed SQL assigns all current users ADMIN.**
   Do not release until unnecessary ADMIN grants are removed intentionally and
   minimal roles created. This cannot be done safely without the actual employee
   roster and approved permission matrix. The migration DOES NOT remove them.
4. In staging, test with separate ADMIN, purchaser, production, QC, sales, and
   read-only accounts. Check both permitted and denied create/edit/delete/approve
   paths. `ERP.EDIT` enforces broad edit access but **not module-level approve
   permissions**; additional module-specific server rules are still necessary.
5. Run representative multi-user conflicts, duplicate handoffs, 2-stage QC,
   partial dispatch, return, tax rounding, currency, payment balances, inventory
   reversal, data imports, refresh/re-login and backup/restore tests.
6. Run `npm ci`, `npm run verify`, and `npm run test:browser` on a configured
   development machine. A staged deployment with rollback and monitoring is
   mandatory before switching production traffic.

## Remaining blockers to enterprise production sign-off

- **Normalized data model:** most UI screens still save large JSONB document
  collections; the normalized tables do not fully back every transaction. Full
  concurrency and posting guarantees require per-document transactional APIs.
- **Permissions:** broad authenticated permissions exist in other normalized
  tables; their RLS and role mapping must be revised per module/action. Current
  compatibility write guard checks ERP.EDIT but cannot safely distinguish
  approval or accounting posting from an ordinary edit inside arbitrary JSONB.
- **Accounting/stock ledger:** inventory, costing, payments, journal entries,
  fiscal-period locks and reconciliations are not fully covered by a certified
  posting engine. Do not treat simulated UI totals as authoritative stock/GL.
- **Authentication:** token renewal after an extended idle session, sign-out in
  other sessions, and recovery from token revocation need deployed browser tests.
- **Audit:** collection-level JSONB audit can be large and needs retention rules,
  restricted access, archiving and PII redaction as appropriate.
- **Deployment:** live Supabase URLs/permissions/operations were not available in
  this artifact run, so no claims are made about deployed transactions or backups.

## Worktree integrity

The existing app UI is not redesigned. Source changes: `src/backend/cloud-store.js`
only. All new SQL is additive and **does not execute on its own**. Run migrations
only after staging validation and role review. No real `.env` or credentials are
included in the distributable archive.

## Automated checks on source changes

`.github/workflows/quality.yml` adds GitHub Actions checks for npm locked
installation, ESLint, JS typecheck, all automated tests, Vite production build,
and production dependency audit. Require these checks on protected `main` before
merging. They must run successfully in GitHub; this artifact run could not
install the required packages because the package registry was inaccessible.
