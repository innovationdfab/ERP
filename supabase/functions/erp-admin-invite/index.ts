/**
 * ERP identity provisioning. Deploy with JWT verification enabled.
 * Service-role credentials and ERP_INITIAL_PASSWORD are server-side secrets.
 * Supports admin-created non-admin accounts, supervised resets and self-service
 * first-login password replacement. Never resets existing accounts silently.
 */
import { createClient } from 'npm:@supabase/supabase-js@2';

const url = Deno.env.get('SUPABASE_URL') || '';
const anonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
const temporaryPassword = Deno.env.get('ERP_INITIAL_PASSWORD') || '';
const allowedOrigins = (Deno.env.get('ERP_ALLOWED_ORIGINS') || 'http://localhost:5173')
  .split(',').map(value => value.trim()).filter(Boolean);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const emailPattern = /^\S+@\S+\.\S+$/;
const initialFlag = 'erp_initial_password_pending';
// New passwords are transmitted only in this authenticated request and handled by Supabase Auth.
const validPersonalPassword = (password: string) => password.length >= 12 && password.length <= 128 && /[A-Za-z]/.test(password) && /[0-9]/.test(password);

Deno.serve(async request => {
  const origin = request.headers.get('Origin') || '';
  const corsAllowed = !origin || allowedOrigins.includes(origin);
  const headers = {
    'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin',
    ...(corsAllowed && origin ? { 'Access-Control-Allow-Origin': origin } : {}),
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
  const respond = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), { status, headers });
  // Expose only the denial message on a rejected origin, so the browser displays
  // a useful 403 instead of masking the error as `Failed to fetch`. No account
  // information or authenticated action is returned to the rejected origin.
  if (!corsAllowed) return new Response(JSON.stringify({ error: 'This website origin is not allowed for ERP administration. Add your exact Vercel URL to ERP_ALLOWED_ORIGINS and redeploy the erp-admin-invite function.' }), {
    status: 403, headers: { ...headers, 'Access-Control-Allow-Origin': origin },
  });
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return respond(405, { error: 'POST required.' });
  if (!url || !anonKey || !serviceKey) return respond(503, { error: 'ERP identity service is not configured.' });

  const jwt = /^Bearer (.+)$/i.exec(request.headers.get('Authorization') || '')?.[1];
  if (!jwt) return respond(401, { error: 'Sign in with your ERP account first.' });
  try {
    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${jwt}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user: actor }, error: authError } = await caller.auth.getUser(jwt);
    if (authError || !actor?.id) return respond(401, { error: 'Your ERP session is expired or invalid.' });
    const body = await request.json();
    const action = typeof body?.action === 'string' ? body.action : 'create';
    const elevated = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

    // The user can change their own initial password, even while their ERP data
    // permissions are temporarily blocked by the database password-reset gate.
    if (action === 'change-initial-password') {
      if (actor.app_metadata?.[initialFlag] !== true) return respond(403, { error: 'Password setup is not required for this account.' });
      const newPassword = typeof body.password === 'string' ? body.password : '';
      if (newPassword.length < 12 || newPassword.length > 128 || newPassword === temporaryPassword || !/[a-z]/i.test(newPassword) || !/[0-9]/.test(newPassword)) {
        return respond(400, { error: 'Choose a different password with 12–128 characters, including letters and numbers.' });
      }
      const metadata = { ...(actor.app_metadata || {}), [initialFlag]: false };
      const { error: passwordError } = await elevated.auth.admin.updateUserById(actor.id, {
        password: newPassword, app_metadata: metadata,
      });
      if (passwordError) return respond(400, { error: 'Password could not be changed. ' + passwordError.message });
      return respond(200, { password_changed: true, sign_in_again: true });
    }

    // Every privileged operation re-checks the caller's JWT and DB role.
    const { data: admin, error: adminError } = await caller.rpc('erp_admin_is_admin');
    if (adminError || admin !== true) return respond(403, { error: 'Administrator authorization required.' });
    const { data: dashboard, error: dashboardError } = await caller.rpc('erp_admin_dashboard');
    if (dashboardError || !dashboard || !Array.isArray(dashboard.users)) return respond(503, { error: 'Employee directory is unavailable. Install ERP Admin SQL first.' });
    const roles = Array.isArray(dashboard.roles) ? dashboard.roles : [];
    const userRoles = Array.isArray(dashboard.user_roles) ? dashboard.user_roles : [];
    const departments = Array.isArray(dashboard.departments) ? dashboard.departments : [];
    const roleForUser = (id: string) => userRoles.filter((link: {user_id: string; role_id: string}) => link.user_id === id)
      .map((link: {role_id: string}) => roles.find((role: {id: string}) => role.id === link.role_id))
      .filter(Boolean);
    const isProtected = (id: string) => id === actor.id || roleForUser(id).some((role: {code: string; system_role?: boolean}) => role.code === 'ADMIN' || role.system_role === true);

    if (action === 'create') {
      const email = String(body.email || '').trim().toLowerCase();
      // Derive a display label for legacy ERP profiles; the Add Login form requires only email, role and password.
      const suppliedName = typeof body.name === 'string' ? body.name.trim().replace(/\s+/g, ' ').slice(0,100) : '';
      const inferredName = (email.split('@')[0] || 'Employee').replace(/[._-]+/g,' ').trim().slice(0,100);
      const name = suppliedName || (inferredName.length >= 2 ? inferredName : 'Employee');
      const roleIds = Array.isArray(body.role_ids) ? body.role_ids : [];
      const departmentId = null;
      if (!emailPattern.test(email) || email.length > 254 || name.length < 2 || roleIds.length !== 1 || !roleIds.every((id: unknown) => typeof id === 'string' && uuid.test(id))) {
        return respond(400, { error: 'Enter a valid email address and select exactly one role.' });
      }
      if (roleIds.some((id: string) => !roles.some((role: {id: string; active: boolean}) => role.id === id && role.active))) {
        return respond(400, { error: 'Choose an active role belonging to your organization.' });
      }
      if (departmentId && !departments.some((dept: {id: string; active: boolean}) => dept.id === departmentId && dept.active)) {
        return respond(400, { error: 'Choose an active department.' });
      }
      const domains = (Deno.env.get('ERP_INVITE_EMAIL_DOMAINS') || '').split(',').map(v => v.trim().toLowerCase()).filter(Boolean);
      if (domains.length && !domains.includes(email.split('@')[1])) return respond(403, { error: 'Employee email domain is not allowed.' });
      if (dashboard.users.some((profile: {email?: string}) => profile.email?.toLowerCase() === email)) {
        return respond(409, { error: 'This employee already exists. Use Edit or Set temporary password; no duplicate was created.' });
      }
      if (typeof body.password !== 'string' || !validPersonalPassword(body.password)) {
        return respond(400, { error: 'Set an individual password of 12–128 characters containing letters and numbers.' });
      }
      const suppliedPassword = body.password;
      const { data: created, error: createError } = await elevated.auth.admin.createUser({
        email, password: suppliedPassword, email_confirm: true,
        user_metadata: { full_name: name },
        app_metadata: { [initialFlag]: false },
      });
      if (createError || !created?.user?.id) return respond(400, { error: createError?.message || 'Employee Auth account could not be created.' });
      // New Auth account trigger creates ERP profile with no access. Assign the
      // selected roles only after successful creation; failure stays locked.
      // The additive Admin SQL makes profile creation and role assignment atomic;
      // it does not depend on the legacy auth.users trigger being installed.
      const { error: assignError } = await caller.rpc('erp_admin_provision_employee', {
        p_user_id: created.user.id, p_email: email, p_display_name: name,
        p_department_id: departmentId, p_role_ids: roleIds,
      });
      if (assignError) {
        // Only remove the just-created Auth user; never touch a pre-existing identity.
        // This avoids leaving new employees with working credentials but no role.
        const { error: rollbackError } = await elevated.auth.admin.deleteUser(created.user.id);
        const missingMigration = /PGRST202|Could not find the function|schema cache|404/i.test(assignError.message || '');
        const reason = missingMigration
          ? 'Admin employee-provisioning SQL is missing. Run supabase/ERP_ADMIN_EMPLOYEE_PROVISIONING_REPAIR.sql in this Supabase project, refresh schema cache, then redeploy the function.'
          : `ERP profile or role assignment failed: ${assignError.message || 'unknown database error'}`;
        return respond(missingMigration ? 503 : 422, { error: rollbackError
          ? `${reason} Auth account may still exist: check Authentication > Users and Saved logins before retrying.`
          : `${reason} Auth creation was rolled back; other employee accounts were not changed.` });
      }
      // Confirm the identity is retrievable and the newly assigned ERP profile is
      // visible before claiming that this login is usable. Do not replay writes
      // or delete the account if this read-back fails: provisioning may have
      // completed already, so an administrator must reconcile the saved entry.
      const { data: verifiedIdentity, error: identityReadError } = await elevated.auth.admin.getUserById(created.user.id);
      const { data: verifiedDirectory, error: directoryReadError } = await caller.rpc('erp_admin_dashboard');
      const verifiedProfile = !directoryReadError && Array.isArray(verifiedDirectory?.users)
        ? verifiedDirectory.users.find((item: { user_id: string }) => item.user_id === created.user.id)
        : null;
      const assignedRoles = !directoryReadError && Array.isArray(verifiedDirectory?.user_roles)
        ? verifiedDirectory.user_roles.filter((item: { user_id: string; role_id: string }) => item.user_id === created.user.id).map((item: { role_id: string }) => item.role_id)
        : [];
      if (identityReadError || !verifiedIdentity?.user || verifiedIdentity.user.email?.toLowerCase() !== email ||
          !verifiedProfile?.active || !roleIds.every((id: string) => assignedRoles.includes(id))) {
        return respond(503, {
          error: 'The employee account was submitted, but login and ERP role verification did not complete. Refresh Saved logins and check Authentication > Users before retrying. Do not create a duplicate account.',
          email, needs_reconciliation: true,
        });
      }
      return respond(200, { created: true, verified: true, email, user_id: created.user.id });
    }

    if (action === 'reset') {
      const id = typeof body.user_id === 'string' ? body.user_id : '';
      if (!uuid.test(id) || id === actor.id) return respond(400, { error: 'Select another valid employee account.' });
      const profile = dashboard.users.find((item: {user_id: string}) => item.user_id === id);
      if (!profile?.active) return respond(404, { error: 'Enabled ERP account not found.' });
      const suppliedPassword = typeof body.password === 'string' ? body.password : '';
      if (!validPersonalPassword(suppliedPassword)) return respond(400, { error: 'Enter a password with 12–128 characters, including letters and numbers.' });
      const { data: existing, error: fetchError } = await elevated.auth.admin.getUserById(id);
      if (fetchError || !existing.user) return respond(404, { error: 'Supabase Auth account not found.' });
      const { error: resetError } = await elevated.auth.admin.updateUserById(id, {
        password: suppliedPassword,
        app_metadata: { ...(existing.user.app_metadata || {}), [initialFlag]: false },
      });
      if (resetError) return respond(400, { error: resetError.message });
      return respond(200, { reset: true, user_id: id });
    }
    if (action === 'restore') {
      const id = typeof body.user_id === 'string' ? body.user_id : '';
      if (!uuid.test(id) || id === actor.id) return respond(403, { error: 'Select another account.' });
      const profile = dashboard.users.find((item: {user_id: string}) => item.user_id === id);
      if (!profile) return respond(404, { error: 'ERP account not found.' });
      const { error: restoreError } = await elevated.auth.admin.updateUserById(id, { ban_duration: 'none' });
      if (restoreError) return respond(400, { error: 'Could not restore Supabase Auth login: '+restoreError.message });
      return respond(200, { restored:true, user_id:id });
    }
    if (action === 'revoke') {
      const id = typeof body.user_id === 'string' ? body.user_id : '';
      if (!uuid.test(id) || id === actor.id) return respond(403, { error: 'You cannot delete your own login.' });
      const profile = dashboard.users.find((item: {user_id: string}) => item.user_id === id);
      if (!profile?.active) return respond(404, { error: 'Active login not found.' });
      // The existing audited erp_admin_save_user RPC enforces last-admin protection.
      // Disable access first using the existing audited ERP RPC, then revoke Auth sign-in.
      const { error: accessError } = await caller.rpc('erp_admin_save_user', {
        p_user_id:id, p_department_id:profile.department_id || null,
        p_display_name:profile.display_name || profile.email || 'Employee',
        p_active:false, p_role_ids:[],
      });
      if (accessError) return respond(422, { error: `Could not disable ERP access: ${accessError.message}` });
      const { error: banError } = await elevated.auth.admin.updateUserById(id, { ban_duration: '876000h' });
      if (banError) return respond(503, { error: 'ERP access disabled but Supabase Auth ban failed: '+banError.message+'. Review account before retrying.' });
      return respond(200, { revoked:true, user_id:id });
    }
    return respond(400, { error: 'Unsupported employee login action.' });
  } catch (error) {
    return respond(500, { error: error instanceof Error ? error.message : 'Unexpected identity service error.' });
  }
});
