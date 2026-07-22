/**
 * P2-11: end-to-end deletion test for `deleteUserFirestoreData` against the
 * Firestore emulator. Seeds a user's data across every store the deletion must
 * reach — including the top-level `sessionLogs` and `concernReports` that live
 * OUTSIDE the user tree (the P1-02 gap) — plus a second user's data, then
 * asserts the target is fully erased and the bystander survives.
 *
 * Run via `npm run test:integration` (wraps this in `firebase emulators:exec`).
 */

import * as admin from "firebase-admin";
import { deleteUserFirestoreData } from "../../src/account-deletion";

const PROJECT_ID = "demo-coil";
const UID = "delete-me";
const OTHER = "keep-me";

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

async function seed() {
  // Target user's tree (a representative spread of subcollections).
  await db.doc(`users/${UID}/profile/health`).set({ activityLevel: "active" });
  await db.doc(`users/${UID}/rehabPlans/p1`).set({ name: "Knee Plan" });
  await db.doc(`users/${UID}/notes/n1`).set({ text: "felt good" });
  await db.doc(`users/${UID}/consents/legal`).set({ tosVersion: "1" });
  await db.doc(`users/${UID}/streakData/current`).set({ currentStreak: 3 });
  await db.doc(`rateLimits/${UID}/windows/w1`).set({ count: 3 });
  // Top-level docs OUTSIDE the user tree (the P1-02 concern).
  await db.doc("sessionLogs/log1").set({ userId: UID });
  await db.doc("concernReports/c1").set({ userId: UID, message: "safety issue" });
  // A second user's data that must SURVIVE the deletion.
  await db.doc(`users/${OTHER}/profile/health`).set({ activityLevel: "low" });
  await db.doc("sessionLogs/logOther").set({ userId: OTHER });
  await db.doc("concernReports/cOther").set({ userId: OTHER, message: "keep me" });
}

async function exists(path: string): Promise<boolean> {
  return (await db.doc(path).get()).exists;
}

describe("deleteUserFirestoreData (Firestore emulator)", () => {
  beforeEach(async () => {
    await Promise.all([
      db.recursiveDelete(db.collection("users").doc(UID)),
      db.recursiveDelete(db.collection("users").doc(OTHER)),
      db.recursiveDelete(db.collection("rateLimits").doc(UID)),
    ]);
    await db.recursiveDelete(db.collection("sessionLogs"));
    await db.recursiveDelete(db.collection("concernReports"));
    await seed();
  });

  it("erases the target user's tree, sessionLogs, concernReports, and rate limits", async () => {
    await deleteUserFirestoreData(db, UID);

    expect(await exists(`users/${UID}/profile/health`)).toBe(false);
    expect(await exists(`users/${UID}/rehabPlans/p1`)).toBe(false);
    expect(await exists(`users/${UID}/notes/n1`)).toBe(false);
    expect(await exists(`users/${UID}/consents/legal`)).toBe(false);
    expect(await exists(`users/${UID}/streakData/current`)).toBe(false);
    expect(await exists(`rateLimits/${UID}/windows/w1`)).toBe(false);
    // The top-level docs outside the user tree — the P1-02 regression guard.
    expect(await exists("sessionLogs/log1")).toBe(false);
    expect(await exists("concernReports/c1")).toBe(false);
  });

  it("does NOT touch another user's data", async () => {
    await deleteUserFirestoreData(db, UID);

    expect(await exists(`users/${OTHER}/profile/health`)).toBe(true);
    expect(await exists("sessionLogs/logOther")).toBe(true);
    expect(await exists("concernReports/cOther")).toBe(true);
  });

  it("is idempotent — a second run on an already-deleted user is a no-op", async () => {
    await deleteUserFirestoreData(db, UID);
    await expect(deleteUserFirestoreData(db, UID)).resolves.toBeUndefined();
  });
});
