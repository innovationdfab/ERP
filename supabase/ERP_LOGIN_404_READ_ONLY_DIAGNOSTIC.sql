-- READ-ONLY diagnostic. Run in Supabase SQL Editor on the exact project used by VITE_SUPABASE_URL.
-- Change the email below to the address listed in Admin > Saved logins.
-- Never copy password hashes, tokens or secrets into support messages.
with target as (select lower(trim('REPLACE_WITH_EMPLOYEE_EMAIL')) as email),
identity as (
  select u.id, lower(u.email) as email, u.email_confirmed_at is not null as email_confirmed,
    (u.app_metadata->>'erp_initial_password_pending') = 'true' as first_login_password_change_pending,
    u.banned_until, u.deleted_at
  from auth.users u join target t on lower(u.email)=t.email
), profile as (
  select p.user_id, p.email, p.active, p.organization_id, p.department_id, p.display_name
  from public.erp_profiles p join target t on lower(p.email)=t.email
)
select t.email as requested_email, i.id is not null as auth_user_exists,
 i.email_confirmed, coalesce(i.first_login_password_change_pending,false) as first_login_password_change_pending,
 (i.banned_until > now()) as auth_banned, i.deleted_at is not null as auth_deleted,
 p.user_id is not null as erp_profile_exists, p.active as erp_profile_active,
 (p.user_id=i.id) as auth_profile_ids_match, p.organization_id is not null as has_organization,
 (select count(*) from public.erp_user_roles ur join public.erp_roles r on r.id=ur.role_id and r.active where ur.user_id=i.id) as active_role_count
from target t left join identity i on true left join profile p on true;

-- Check mandatory login RPCs are present (this does not test authorization).
select to_regprocedure('public.erp_admin_my_access()') is not null as admin_access_rpc_exists,
 to_regprocedure('public.erp_get_ui_state()') is not null as erp_data_rpc_exists;
