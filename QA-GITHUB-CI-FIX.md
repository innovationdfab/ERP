# GitHub CI fix — verification

Base: innovationdfab/ERP main, ad33f2e2b5b8fb1e47c35e4bc42848d38bd7d88e.
Environment: Node.js v24.22.3; exact lockfile install; Vite 8.3.8.

| Check | Result |
| --- | --- |
| npm ci | PASS: clean installation |
| npm run verify | PASS: lint, configured TypeScript check, 151 tests, production build |
| npm audit --omit=dev --audit-level=high | PASS: zero vulnerabilities |
| npm run test:browser | PASS: complete seven-script suite |
| Browser route and report coverage | PASS: 185 desktop routes, 77 generated reports |
| Shared reference forms | PASS: 30 reference forms and two other inline transaction forms |
| Create forms and accessible sections | PASS: 94 create forms across 185 menu pages, desktop and mobile |
| Dispatch Fetch regression | PASS: source eligibility, product quantity, preserved sales order, saved lineage, duplicate billing prevention |
| Extension UI and data flows | PASS: reorder policy, indent creation, follow-ups, ageing, statements, reload, six viewport widths, failed-save handling and source permissions |
| Session recovery | PASS: one refresh on 401, rotated-token persistence, subsequent save, revoked-session return to login |
| Workspace SQL suite | PASS: eight migrations, permissions, approvals, atomic handoff/rollback, activity scope, transactional restore, extensions and initial-password policy |
| Process SQL suite | PASS: migration compilation, atomic writes, stale-snapshot rollback, unsupported-key and permission rejection, existing-number collision avoidance |
| git diff --check | PASS |

Cloud-store regressions additionally cover successful multi-section confirmation, subsequent saves using committed state, stale local snapshots, queued edits, failed atomic saves, logout during a pending commit, authenticated numbering and invalid number responses.

Browser checks ran against isolated Supabase fixtures in headless Chromium. SQL checks ran in isolated PGlite databases. They did not modify production data. The SQL checks used the existing optional external PGlite test installation; no database dependency was added to the production bundle.

The existing workflow was left enabled and unchanged. No failed check was skipped. The JSX guard was corrected to understand destructured component props; the menu assertion was reconciled with the actual existing navigation, with all existing routes retained. Build warnings about chunk size and third-party module directives remain non-failing.

A hosted GitHub Actions run and a production Supabase deployment were not performed: GitHub was not authenticated in this workspace. Commit and push the provided changes to trigger the existing workflow. See GITHUB-CI-FIX.md for update and database setup instructions.
