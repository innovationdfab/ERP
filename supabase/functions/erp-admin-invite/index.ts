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
  if (!corsAllowed) return respond(403, { error: 'Origin not authorized for ERP administration.' });
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
      const name = String(body.name || '').trim();
      const roleIds = Array.isArray(body.role_ids) ? body.role_ids : [];
      const departmentId = body.department_id || null;
      if (!emailPattern.test(email) || email.length > 254 || name.length < 2 || name.length > 100 || roleIds.length === 0 || roleIds.length > 20 || !roleIds.every((id: unknown) => typeof id === 'string' && uuid.test(id)) || (departmentId && (typeof departmentId !== 'string' || !uuid.test(departmentId)))) {
        return respond(400, { error: 'Valid employee email, name, department and role are required.' });
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
      // An admin account cannot have a company-wide known initial password.
      const requestedAdmin = roleIds.some((id: string) => roles.some((role: {id: string; code: string; system_role?: boolean}) => role.id === id && (role.code === 'ADMIN' || role.system_role === true)));
      if (body.password != null && typeof body.password !== 'string') return respond(400, { error: 'Password must be plain text.' });
      const suppliedPassword = typeof body.password === 'string' ? body.password : '';
      if (requestedAdmin && suppliedPassword) return respond(400, { error: 'Administrator access requires an individual invitation; do not set a shared password.' });
      if (suppliedPassword && (!validPersonalPassword(suppliedPassword) || suppliedPassword === temporaryPassword)) {
        return respond(400, { error: 'Use a different 12–128 character temporary password with letters and numbers.' });
      }
      if (!requestedAdmin && !suppliedPassword && (temporaryPassword.length < 8 || temporaryPassword.length > 128)) {
        return respond(503, { error: 'ERP_INITIAL_PASSWORD secret is not configured. Enter an individual strong password or configure the server default.' });
      }
      const accountPassword = suppliedPassword || temporaryPassword;
      const { data: created, error: createError } = requestedAdmin
        ? await elevated.auth.admin.inviteUserByEmail(email, { data: { full_name: name } })
        : await elevated.auth.admin.createUser({ email, password: accountPassword, email_confirm: true, user_metadata: { full_name: name }, app_metadata: { [initialFlag]: true } });
      if (createError || !created?.user?.id) return respond(400, { error: createError?.message || 'Employee Auth account could not be created.' });
      // New Auth account trigger creates ERP profile with no access. Assign the
      // selected roles only after successful creation; failure stays locked.
      const { error: assignError } = await caller.rpc('erp_admin_save_user', {
        p_user_id: created.user.id, p_department_id: departmentId,
        p_display_name: name, p_active: true, p_role_ids: roleIds,
      });
      if (assignError) {
        // Only remove the just-created Auth user; never touch a pre-existing identity.
        // This avoids leaving new employees with working credentials but no role.
        const { error: rollbackError } = await elevated.auth.admin.deleteUser(created.user.id);
        return respond(500, { error: rollbackError
          ? 'Auth account created without ERP access, and automatic rollback failed. An administrator must reconcile this employee before retrying.'
          : 'Employee creation was rolled back because ERP role assignment failed. Check Supabase permissions and try again.' });
      }
      return respond(200, { created: true, email, user_id: created.user.id, temporary_password: !requestedAdmin, invited: requestedAdmin });
    }

    if (action === 'reset') {
      const id = typeof body.user_id === 'string' ? body.user_id : '';
      if (!uuid.test(id)) return respond(400, { error: 'Invalid employee ID.' });
      const profile = dashboard.users.find((item: {user_id: string}) => item.user_id === id);
      if (!profile || profile.active !== true) return respond(404, { error: 'Active employee not found in your organization.' });
      if (isProtected(id)) return respond(403, { error: 'Administrator accounts and your own account cannot use the shared initial password. Use an individual password reset.' });
      if (body.password != null && typeof body.password !== 'string') return respond(400, { error: 'Password must be plain text.' });
      const suppliedPassword = typeof body.password === 'string' ? body.password : '';
      if (suppliedPassword && (!validPersonalPassword(suppliedPassword) || suppliedPassword === temporaryPassword)) {
        return respond(400, { error: 'Use a different 12–128 character temporary password with letters and numbers.' });
      }
      if (!suppliedPassword && (temporaryPassword.length < 8 || temporaryPassword.length > 128)) return respond(503, { error: 'ERP_INITIAL_PASSWORD secret is not configured. Enter an individual strong password or configure the server default.' });
      const { data: existing, error: fetchError } = await elevated.auth.admin.getUserById(id);
      if (fetchError || !existing.user) return respond(404, { error: 'Employee Auth account not found. ' + (fetchError?.message || '') });
      const { error: resetError } = await elevated.auth.admin.updateUserById(id, {
        password: suppliedPassword || temporaryPassword,
        app_metadata: { ...(existing.user.app_metadata || {}), [initialFlag]: true },
      });
      if (resetError) return respond(400, { error: resetError.message });
      return respond(200, { reset: true, user_id: id });
    }

    if (action === 'bulk-reset') {
      const ids = Array.isArray(body.user_ids) ? [...new Set(body.user_ids)] : [];
      if (!ids.length || ids.length > 40 || ids.some(id => typeof id !== 'string' || !uuid.test(id))) {
        return respond(400, { error: 'Select 1–40 active employees per batch.' });
      }
      if (temporaryPassword.length < 8 || temporaryPassword.length > 128) return respond(503, { error: 'ERP_INITIAL_PASSWORD secret is not configured.' });
      const errors: Array<{user_id: string; error: string}> = [];
      let updated = 0;
      for (const id of ids) {
        const profile = dashboard.users.find((item: {user_id: string}) => item.user_id === id);
        if (!profile?.active || isProtected(id)) { errors.push({ user_id: id, error: 'Not a permitted active non-admin employee.' }); continue; }
        const { data: existing, error: fetchError } = await elevated.auth.admin.getUserById(id);
        if (fetchError || !existing.user) { errors.push({ user_id: id, error: 'Supabase Auth account not found.' }); continue; }
        const { error: resetError } = await elevated.auth.admin.updateUserById(id, {
          password: temporaryPassword,
          app_metadata: { ...(existing.user.app_metadata || {}), [initialFlag]: true },
        });
        if (resetError) errors.push({ user_id: id, error: resetError.message });
        else updated++;
      }
      return respond(200, { updated, failures: errors, partial: errors.length > 0 });
    }
    return respond(400, { error: 'Unsupported employee login action.' });
  } catch (error) {
    return respond(500, { error: error instanceof Error ? error.message : 'Unexpected identity service error.' });
  }
});
