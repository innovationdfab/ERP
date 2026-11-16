/**
 * Temporary, unauthenticated administrator UI preview.
 * Never authorize Supabase reads/writes or impersonate an ERP identity here.
 * Vite replaces import.meta.env.DEV with false in production builds.
 */
export function canUseLocalAdminPreview(isDevelopment, hostname) {
  return isDevelopment === true && ['localhost', '127.0.0.1', '::1', '[::1]'].includes(String(hostname || '').toLowerCase());
}
