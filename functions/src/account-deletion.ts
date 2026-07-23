import * as admin from "firebase-admin";

/**
 * Deletes ALL of a user's Firestore data: the `users/{uid}` tree (every
 * subcollection via recursiveDelete), their top-level `sessionLogs` index docs,
 * their top-level `concernReports`, and their rate-limit counters. The last two
 * live OUTSIDE the user tree, so recursiveDelete does not reach them — they must
 * be deleted explicitly or they outlive the account (P1-02).
 *
 * Extracted from the `deleteAccount` handler so it can be exercised end-to-end
 * against the Firestore emulator (P2-11). Storage-blob and Auth-user deletion
 * stay in the handler (they need the Storage/Auth services, not just Firestore).
 */
export async function deleteUserFirestoreData(
  db: admin.firestore.Firestore,
  uid: string,
): Promise<void> {
  // 1. Entire user tree (profile, rehabPlans, workoutSessions, notes,
  //    wellnessPlans, assessments, formAnalyses, streakData, analysisOutcomes,
  //    quotas, consents, riskAcknowledgements).
  await db.recursiveDelete(db.collection("users").doc(uid));

  // 2. Top-level sessionLogs index docs authored by this user.
  await deleteWhereUserId(db, "sessionLogs", uid);

  // 3. Top-level concernReports authored by this user.
  await deleteWhereUserId(db, "concernReports", uid);

  // 4. Rate-limit counters (admin-only path).
  await db.recursiveDelete(db.collection("rateLimits").doc(uid));
}

/** Batch-deletes every doc in `collection` whose `userId` field equals `uid`. */
async function deleteWhereUserId(
  db: admin.firestore.Firestore,
  collection: string,
  uid: string,
): Promise<void> {
  for (;;) {
    const snap = await db.collection(collection).where("userId", "==", uid).limit(300).get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    if (snap.size < 300) break;
  }
}
