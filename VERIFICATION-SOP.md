# Workflow upgrade verification — 2 November 2026

- Lint: passed.
- Existing configured JavaScript utility/backend type check: passed. This check does not type-check every JSX component.
- Unit tests: 14/14 passed; includes original utility tests plus process amount, tax, validation, workflow, QC, routing, financial-year, projection and legacy-payment tests.
- Production build: passed. Vite reports its non-blocking bundle-size and lucide `use client` warnings.
- Browser full regression: 127 existing/new routes rendered; all 30 expanded transaction editors opened, changed tabs, saved drafts and deleted those test drafts. No runtime errors.
- Additional focused browser regression: the added overdue report route, pending-receivable balance calculation, legacy payment projection, approval-inbox review, route-process pricing save, source handoffs, quote attachment/charge persistence, rejected-overpayment recovery, simulated database failure/retry, session refresh and confirmed data reload passed. This brings route coverage to 128 distinct pages.
- Responsive checks: no document-body horizontal overflow at widths 1440, 768 and 390. Wide product tables scroll within their container.
- PostgreSQL-compatible migration regression: function compilation, atomic multi-section commit, stale-payload rollback, invalid-key rejection, permission rejection and legacy-number collision skipping passed locally in PGlite.
- Original archive comparison: 30 original files unchanged byte-for-byte, 4 original files edited, 0 missing. See PRESERVATION-CHECK.json.

Browser tests use an intercepted test Supabase origin and the uploaded seed snapshot. The reference website was inspected read-only; no live transaction was saved. The new SQL has not been installed on the user's live Supabase project, and no production database credentials were supplied. Live deployment, multi-user production operation, bank/email/Tally/e-invoice services, stock-ledger posting and accounting accuracy are not certified by these checks.

## Run checks

```sh
npm ci
npm run verify
npx playwright install chromium
npm run test:process
```

An existing Chromium binary can be used with ERP_CHROMIUM_PATH. ERP_QUICK=1 runs the targeted interaction checks without repeating the full route/editor sweep.

For the optional local PostgreSQL migration regression (test dependency only):

```sh
npm install --no-save @electric-sql/pglite
node tests/database-process.mjs
```

The older browser-smoke/advanced/premium files are preserved from the original archive. Their legacy form/login selectors predate this upgrade; `test:process` is the maintained integration suite for the updated transaction screens.
