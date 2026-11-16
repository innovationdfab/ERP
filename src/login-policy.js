/** Auth-provider app_metadata is server-controlled; do not infer a forced reset from user_metadata. */
export const INITIAL_PASSWORD_CLAIM = 'erp_initial_password_pending';
export function requiresInitialPasswordChange(user) {
  return user?.app_metadata?.[INITIAL_PASSWORD_CLAIM] === true;
}
export function initialPasswordIssue(password, confirmPassword) {
  if (typeof password !== 'string' || password.length < 12 || password.length > 128 || !/[a-z]/i.test(password) || !/[0-9]/.test(password))
    return 'Use 12–128 characters with letters and numbers.';
  if (password !== confirmPassword) return 'The new passwords do not match.';
  return '';
}
