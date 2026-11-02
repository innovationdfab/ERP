# Visible ERP buttons — 2 November 2026

## What was corrected

Fetch previously appeared only while editing. It is now a visible blue button next to **Create new** on every transaction register with a configured source. It also appears on opened records and editors. Clicking it opens source selection immediately; cancelling keeps the current page and data unchanged. Applying selected items opens the editable destination form. Saving remains explicit.

Approval, rejection, Continue, dispatch and delivery actions are now visible above the document sections when applicable. You no longer have to open Workflow to find them. Their existing status, quantity, QC and permission checks are retained. An action that is not yet permitted stays disabled with its reason.

Masters, reports, payments and configuration pages retain their own existing actions. Fetch is a source-document action, so it is not added to pages that have no configured source. The per-page audit identifies which transaction pages support it.

## Run the updated folder

1. Extract this ZIP into a fresh folder and open the included project folder in VS Code.
2. Keep your existing Supabase `.env` configuration; do not replace company credentials with sample values.
3. Stop the old development server. In the new project folder, run `npm ci`, then `npm run dev` and open the URL printed by Vite.
4. For deployed hosting, run `npm run build` from this updated folder and deploy its resulting `dist` folder. Downloading the ZIP does not update an already deployed site.

No additional SQL migration is needed beyond the existing `DFAB_PROCESS_UPGRADE.sql`. Existing SOPs, validation, source quantities, saved data, accounting limitations and Fetch rules from `START-HERE-SOP.md` and `FETCH-UPDATE.md` remain in force.

## Checks included

`BUTTON-AUDIT.json` records the actual visible commands observed on each ERP page and each expanded transaction's register, editor and saved-record states at desktop and mobile widths. Tests check missing Fetch commands, clipped action bars, modal open/cancel behavior and actual source fetching from the register. Existing workflow, save, payment, attachment, reload and responsive tests also run locally with mocked Supabase transport. No live company transactions are submitted.

`BUTTON-LOCK-CHECK.json` compares this folder with the last delivered Fetch ZIP and records the current verification results. Unrelated files are retained without replacement.
