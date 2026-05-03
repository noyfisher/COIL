#!/usr/bin/env node
/**
 * Tier 2 PR B helper — mint a Firebase ID token for load-testing.
 *
 * Uses Application Default Credentials (the gcloud account you're
 * logged in as) to:
 *   1. Mint a custom token for `vuser-loadtest` via firebase-admin
 *   2. Exchange the custom token for an ID token via the Firebase Auth REST API
 *
 * Output: the ID token to stdout (single line, no extra text), so it can
 * be captured into a shell variable directly:
 *
 *   TOKEN=$(node functions/test/mint_test_token.js)
 *   ./functions/test/rate-limit-e2e.sh BURST --token=$TOKEN
 *
 * Usage:
 *   node functions/test/mint_test_token.js                          # default project
 *   FIREBASE_PROJECT=pt-helper-dev node functions/test/mint_test_token.js
 *
 * Requires:
 *   - firebase-admin package (already in functions/package.json)
 *   - GOOGLE_APPLICATION_CREDENTIALS or gcloud login
 *   - The Firebase Web API Key for the project (passed via WEB_API_KEY env
 *     var, or auto-fetched via the Firebase Identity Toolkit if available).
 *
 * The Web API Key is NOT a secret — it's published in your client bundles.
 * Find it at:
 *   https://console.firebase.google.com/project/<project>/settings/general
 *   under "Your apps" → "Web API Key"
 */

const admin = require('firebase-admin');

const PROJECT_ID = process.env.FIREBASE_PROJECT || 'pt-helper-dev';
const WEB_API_KEY = process.env.WEB_API_KEY;
const VIRTUAL_USER_ID = process.env.VIRTUAL_USER_ID || 'vuser-loadtest';

async function main() {
  if (!WEB_API_KEY) {
    console.error('ERROR: set WEB_API_KEY env var to your project Web API Key.');
    console.error('Find it at https://console.firebase.google.com/project/' + PROJECT_ID + '/settings/general');
    process.exit(2);
  }

  // Initialize admin SDK with ADC. `serviceAccountId` tells the SDK to
  // sign custom tokens via IAM (impersonating the service account) rather
  // than trying to sign locally — required when the caller is a user (gcloud
  // ADC) rather than a service-account key. The user must have
  // `roles/iam.serviceAccountTokenCreator` on the target SA.
  admin.initializeApp({
    projectId: PROJECT_ID,
    serviceAccountId: 'firebase-adminsdk-fbsvc@' + PROJECT_ID + '.iam.gserviceaccount.com',
  });

  // Step 1: mint a custom token for the virtual user
  let customToken;
  try {
    customToken = await admin.auth().createCustomToken(VIRTUAL_USER_ID);
  } catch (e) {
    console.error('Failed to mint custom token: ' + e.message);
    console.error('Hint: this requires "Service Account Token Creator" role on the Firebase Admin SDK service account.');
    process.exit(3);
  }

  // Step 2: exchange custom token for an ID token via the Identity Toolkit REST API
  const url = 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=' + WEB_API_KEY;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
  });
  if (!res.ok) {
    const body = await res.text();
    console.error('Custom-token exchange failed (' + res.status + '): ' + body);
    process.exit(4);
  }
  const json = await res.json();
  // Print only the idToken on stdout so callers can capture cleanly.
  console.log(json.idToken);
}

main().catch((e) => {
  console.error('Unexpected error: ' + e.message);
  process.exit(1);
});
