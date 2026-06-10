#!/usr/bin/env node
/**
 * Mint a Firebase CUSTOM token for a virtual user, for app sign-in via the
 * `--virtual-user-token` launch argument (RootView signs in with
 * Auth.auth().signIn(withCustomToken:)).
 *
 * Unlike functions/test/mint_test_token.js this does NOT exchange the custom
 * token for an ID token — the iOS Firebase SDK needs the custom token itself.
 *
 * Output: the custom token on stdout (single line), so it can be captured:
 *
 *   TOKEN=$(VIRTUAL_USER_ID=vuser-happy-path-001 node virtual-users/mint_app_token.js)
 *
 * Requires: gcloud ADC login with `roles/iam.serviceAccountTokenCreator` on the
 * Firebase Admin SDK service account (same setup as mint_test_token.js).
 * Uses firebase-admin from functions/node_modules (run `npm install` there first).
 */

const path = require('path');
const admin = require(path.join(__dirname, '..', 'functions', 'node_modules', 'firebase-admin'));

const PROJECT_ID = process.env.FIREBASE_PROJECT || 'pt-helper-dev';
const VIRTUAL_USER_ID = process.env.VIRTUAL_USER_ID || 'vuser-default';

async function main() {
  if (!VIRTUAL_USER_ID.startsWith('vuser-')) {
    console.error('ERROR: VIRTUAL_USER_ID must start with "vuser-" (got: ' + VIRTUAL_USER_ID + ')');
    process.exit(2);
  }

  admin.initializeApp({
    projectId: PROJECT_ID,
    serviceAccountId: 'firebase-adminsdk-fbsvc@' + PROJECT_ID + '.iam.gserviceaccount.com',
  });

  try {
    const customToken = await admin.auth().createCustomToken(VIRTUAL_USER_ID);
    console.log(customToken);
  } catch (e) {
    console.error('Failed to mint custom token: ' + e.message);
    console.error('Hint: requires "Service Account Token Creator" role on the Firebase Admin SDK service account.');
    process.exit(3);
  }
}

main().catch((e) => {
  console.error('Unexpected error: ' + e.message);
  process.exit(1);
});
