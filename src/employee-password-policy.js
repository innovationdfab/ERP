/** Form-only validation. Supabase Auth and the Edge Function enforce the final password policy. */
export function temporaryPasswordIssue(password, confirmation, { allowEmpty = false } = {}) {
  if (allowEmpty && !password && !confirmation) return '';
  if (typeof password !== 'string' || password.length < 12 || password.length > 128 || !/[A-Za-z]/.test(password) || !/[0-9]/.test(password)) {
    return 'Temporary password must have 12–128 characters, including a letter and a number.';
  }
  if (password !== confirmation) return 'The password and confirmation do not match.';
  return '';
}
