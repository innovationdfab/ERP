# Verification — audit fixes, 24 November 2026

## Scope

Tests run against this folder, isolated authenticated browser fixtures and temporary PostgreSQL. No production transaction, recipient email, Vercel deployment or live database migration was performed. The original source folder is retained separately.

## Completed checks

| Check | Result |
| --- | --- |
| ESLint | Passed |
| Configured utility JavaScript type check | Passed; scope is `src/erp-utils.js`, as configured in the existing project |
| Unit and service regression tests | 178 passed, 0 failed |
| Production build | Passed; existing non-fatal Lucide `use client` bundler notices remain |
| Production dependency audit | 0 vulnerabilities reported |
| SQL migrations and workspace controls | Passed in temporary PostgreSQL |
| Single-file SQL bundle | Passed fresh installation and process regressions in temporary PostgreSQL |

SQL checks include maker/approver separation, numbering permission, row access, concurrency, atomic rollback, source reservation, immutable lineage, financial totals, overpayments, due-date rejection, paid/delivered work-order closure and email-request idempotency. SMTP delivery itself is not part of that check.

## Focused browser checks

- Nested multi-word register search, inclusive date endpoints, invalid ranges and reset.
- New vendor handoff and correcting a rejected save without a reload.
- Database-confirmed Saved, Submitted for approval, Approved and Deleted animations.
- Invoice credit days, due-date derivation and clearing a date without a runtime error.
- Stock report date/product filters, generated-table search and invalid-range handling.
- Draft deletion requires confirmation and removes the fixture record.

## Browser regression results

All nine browser test suites passed their completed checks. The last two suites were rerun successfully after the final feedback refinement; the earlier combined invocation was interrupted by Vite hot reload during that source change.

| Coverage | Result |
| --- | --- |
| Authenticated menu and report sweep | 185 menu pages, including 77 generated reports; passed |
| Reference transaction editors | 58 inline forms, header/line controls, Fetch and saved draft reload; passed |
| Accessible create actions | 92 create forms across the menu, desktop and mobile; passed |
| Master/import/attachment interactions | 10 checks; passed |
| ERP Extensions | Reorder, ageing, statements, follow-ups, permissions, save failure and six viewport widths; passed |
| Sessions | 401 refresh, token rotation, subsequent save and revoked-session sign-out; passed |
| Partial dispatch Fetch | Pending reservations, excess rejection and persisted lineage; passed |
| Manufacturing and labour workflows | Manufacturing through payment/closure; labour inward through QC/SO/work order; passed |
| Focused audit fixes | Search, date filters, rejected-save retry, feedback, invoice terms and confirmed deletion; passed |

No runtime errors were reported in the successful browser runs. The full labour dispatch/payment route was not separately exercised end-to-end; shared manufacturing stages, labour intake and SQL payment/closure guards were covered.

## Repeat locally

```sh
npm ci
npm run verify
npx playwright install chromium
npm run test:browser
npm install --no-save --package-lock=false @electric-sql/pglite
npm run test:sql
ERP_SQL_BUNDLE=DFAB-OneERP-All-In-One.sql node tests/production-sql.mjs
npm audit --omit=dev --audit-level=high
```

If using an independently installed test database or browser, set `ERP_PGLITE_DIR` to PGlite's `dist` directory and `ERP_CHROMIUM_PATH` to the Chromium executable. Optional QA packages are not needed by the deployed application.

## Deployment acceptance still needed

Apply the supplied SQL and deploy the frontend to your environment, then verify sign-in, your actual staff role permissions, production-data reconciliation and Zoho delivery. Historical missing dates require genuine data entry; undated movements are excluded from date-bounded reports rather than being assigned fake dates. This package cannot establish that every production record or external service is correct without those environment checks.
