# Add Login role-choice update (Admin-only)

- In Admin → Team & Access → Saved logins → Add Login, "Mark as Administrator" is **optional and unchecked by default**.
- When not checked, select one of the existing active **non-admin roles** from the dropdown. The role ID is saved through the **existing** account-provisioning service, and the entered temporary password is required.
- When checked, the built-in active Administrator role is selected and the employee-role dropdown is hidden. As before, an administrator receives an individual invitation (no shared administrator password).
- Toggling between modes clears passwords and selected roles to avoid accidentally provisioning an account with incorrect access.
- Existing employee editing, Supabase SQL and Edge Function are unchanged. No new SQL or redeployment of Edge Function is needed for this UI change.
- All application code outside `src/admin-control.jsx` and `src/admin-control.css` is unchanged from the previous base.

Security note: existing first-login password-change and server-side authorization remain enforced.
