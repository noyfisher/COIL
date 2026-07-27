/**
 * Firebase Web SDK config for the monitoring dashboard.
 *
 * FILL THESE IN before deploying. From the repo root:
 *
 *     firebase apps:create web pt-helper-dashboard      # once, if it doesn't exist
 *     firebase apps:sdkconfig web                        # prints the values below
 *
 * A Firebase *web* config is NOT a secret — it ships in every client bundle and
 * is safe to commit. Access control lives in the `dashboardData` function's
 * ADMIN_EMAILS allowlist and in Firestore rules, never in these values.
 *
 * Until they are filled in, every page shows a "config missing" screen instead
 * of trying (and failing) to initialise Firebase.
 */

export const firebaseConfig = {
  apiKey: 'REPLACE_WITH_API_KEY',
  authDomain: 'REPLACE_WITH_PROJECT_ID.firebaseapp.com',
  projectId: 'REPLACE_WITH_PROJECT_ID',
  appId: 'REPLACE_WITH_APP_ID',
};

/** Pinned Firebase JS SDK (loaded as ESM from gstatic — no bundler here). */
export const FIREBASE_SDK_VERSION = '10.14.1';

/**
 * True while any value is still a placeholder (or blank).
 * Keep the `REPLACE_WITH` prefix on placeholders so this check keeps working.
 */
export function isPlaceholderConfig(config = firebaseConfig) {
  return Object.values(config).some(
    (value) => typeof value !== 'string' || value.trim() === '' || value.includes('REPLACE_WITH'),
  );
}
