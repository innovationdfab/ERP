# GitHub Actions repair

Based on innovationdfab/ERP main commit ad33f2e2b5b8fb1e47c35e4bc42848d38bd7d88e.

## What failed and what changed

- Restored the missing commitProcessChanges and nextProcessNumber exports used by the existing process modules. Saves use the existing atomic Supabase RPC, original edit snapshots, serialized writes, confirmed cache updates and session-change protection. Failed saves do not leave optimistic data displayed as saved.
- Reconciled the Fetch configuration with the existing document-fetch helpers. GRN Fetch leaves actual received quantity and rate for staff confirmation. Invoice Fetch supports delivery and job-work return challans, preserves the sales-order reference, stores source lineage and checks quantities against existing dispatch billing. The shared form uses the tested Fetch implementation.
- Preserved the current navigation. Transaction context now includes the Planning, Warehouse & QC and Additional Operations routes already in the menu. The menu test compares these existing routes; it no longer assumes an absent SOP Workflow screen.
- Corrected the JSX component guard to recognize components passed through destructured props, with a regression test that still rejects missing component declarations.
- Updated Vite from 8.3.0 to 8.3.8 and regenerated the lockfile, including source-map-js 1.2.4. The audit gate remains enabled.
- Added cloud save and dispatch Fetch regression coverage. Existing theme and unrelated screens were retained.

## Apply to GitHub

Extract DFAB-OneERP-GitHub-CI-Fixed and copy its contents into your existing repository, replacing matching files. Include package.json, package-lock.json, src and tests. Preserve your local .env file. Do not upload node_modules or dist. A patch against the above commit is included as github-ci-fix.patch.

From the project directory, using Node.js 24:

```sh
npm ci
npm run verify
npm audit --omit=dev --audit-level=high
```

Commit and push the updated files to main, or open a pull request targeting main. The existing ERP quality gates workflow then runs automatically. GitHub was not authenticated in the repair workspace, so these changes have not been pushed and a hosted Actions result has not been observed.

## Database setup

No SQL was changed for this repair. The restored process helpers require the existing supabase/DFAB_PROCESS_UPGRADE.sql migration after DFAB_ERP_PRODUCTION.sql. If those functions are already installed, no database update is necessary. Missing functions produce a clear setup error rather than a partial save. Keep the existing Supabase URL and publishable-key environment settings on Vercel.

## Verification

See QA-GITHUB-CI-FIX.md for the completed checks. Browser and database checks use isolated fixtures, not production customer data. Build output can retain non-failing warnings about bundle size and lucide-react directives.
