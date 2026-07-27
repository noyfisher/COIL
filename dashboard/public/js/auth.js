/**
 * Google sign-in gate for the monitoring dashboard.
 *
 * Firebase JS SDK v10 is loaded as ESM straight from gstatic (no bundler, no
 * npm step) and only when it is actually needed — `?mock=1` and the
 * placeholder-config path never touch the network.
 *
 * Authorisation is NOT decided here: any Google account can sign in, and the
 * `dashboardData` function answers 403 unless the verified email is in
 * ADMIN_EMAILS. This module only proves who the caller is.
 */

import { firebaseConfig, isPlaceholderConfig, FIREBASE_SDK_VERSION } from './firebase-config.js';
import { IS_MOCK, showScreen, setScreenMessage } from './ui.js';

const GSTATIC = `https://www.gstatic.com/firebasejs/${FIREBASE_SDK_VERSION}`;

let authInstance = null;
let currentUser = null;
let signOutFn = null;

/** Bearer token for the API. Throws when there is no signed-in user. */
export async function getIdToken(forceRefresh = false) {
  if (IS_MOCK) return 'mock-id-token';
  if (!currentUser) throw new Error('not_signed_in');
  return currentUser.getIdToken(forceRefresh);
}

export function getUserEmail() {
  return IS_MOCK ? 'mock@example.test' : (currentUser?.email ?? null);
}

/** Drop the session and return to the sign-in screen (used by api.js on 401). */
export async function signOutAndGate() {
  if (authInstance && signOutFn) {
    try {
      await signOutFn(authInstance);
    } catch {
      /* ignore — we are gating either way */
    }
  }
  currentUser = null;
  showScreen('screen-signin');
}

function paintIdentity() {
  const email = getUserEmail();
  for (const el of document.querySelectorAll('[data-user-email]')) {
    el.textContent = email ?? '';
  }
  for (const el of document.querySelectorAll('[data-signout]')) {
    // Nothing to sign out of in mock mode — the button would be a dead control.
    el.hidden = !email || IS_MOCK;
  }
}

function paintMockBadge() {
  for (const el of document.querySelectorAll('[data-mock-badge]')) {
    el.hidden = !IS_MOCK;
  }
}

/**
 * Run a page behind the auth gate.
 *
 * @param {(ctx: {mock: boolean}) => (void|Promise<void>)} onReady
 *        Called once the app screen is visible and a token is obtainable.
 */
export async function bootPage(onReady) {
  paintMockBadge();

  if (IS_MOCK) {
    paintIdentity();
    showScreen('screen-app');
    await onReady({ mock: true });
    return;
  }

  if (isPlaceholderConfig()) {
    showScreen('screen-config');
    return;
  }

  showScreen('screen-loading');

  let initializeApp;
  let auth;
  try {
    const [appMod, authMod] = await Promise.all([
      import(`${GSTATIC}/firebase-app.js`),
      import(`${GSTATIC}/firebase-auth.js`),
    ]);
    initializeApp = appMod.initializeApp;
    auth = authMod;
  } catch (err) {
    showScreen('screen-error');
    setScreenMessage('screen-error', `Could not load the Firebase SDK from gstatic: ${err?.message ?? err}`);
    return;
  }

  const { getAuth, GoogleAuthProvider, signInWithPopup, onAuthStateChanged, signOut } = auth;
  const app = initializeApp(firebaseConfig);
  authInstance = getAuth(app);
  signOutFn = signOut;

  const provider = new GoogleAuthProvider();
  provider.setCustomParameters({ prompt: 'select_account' });

  for (const btn of document.querySelectorAll('[data-signin]')) {
    btn.addEventListener('click', async () => {
      setScreenMessage('screen-signin', '');
      try {
        await signInWithPopup(authInstance, provider);
      } catch (err) {
        const code = err?.code ?? '';
        const message =
          code === 'auth/popup-blocked'
            ? 'The sign-in popup was blocked. Allow popups for this site and try again.'
            : code === 'auth/popup-closed-by-user' || code === 'auth/cancelled-popup-request'
              ? 'Sign-in was cancelled.'
              : `Sign-in failed: ${err?.message ?? err}`;
        setScreenMessage('screen-signin', message);
      }
    });
  }

  for (const btn of document.querySelectorAll('[data-signout]')) {
    btn.addEventListener('click', () => { void signOutAndGate(); });
  }

  let readyRan = false;
  onAuthStateChanged(authInstance, (user) => {
    currentUser = user ?? null;
    paintIdentity();
    if (!user) {
      readyRan = false;
      showScreen('screen-signin');
      return;
    }
    showScreen('screen-app');
    if (readyRan) return;
    readyRan = true;
    Promise.resolve(onReady({ mock: false })).catch((err) => {
      showScreen('screen-error');
      setScreenMessage('screen-error', String(err?.message ?? err));
    });
  });
}
