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
  apiKey: 'AIzaSyCmvLpY0K6_1HZGyrkHNs-BbDUjItjIeO8',
  authDomain: 'pt-helper-dev.firebaseapp.com',
  projectId: 'pt-helper-dev',
  appId: '1:892493410961:web:131927c9b676e8d70ec530',
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
