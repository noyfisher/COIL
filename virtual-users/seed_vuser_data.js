#!/usr/bin/env node
/**
 * Seed / clean up Firestore data for virtual users.
 *
 * Seed mode (default) populates `vuser-veteran-001` with 14 days of realistic
 * history so in-app charts (Progress tab, RehabMetricsView, AchievementsView)
 * have data to render. Field names mirror the app's manual Firestore decoding:
 *   - WorkoutViewModel.fetchSessions REQUIRES an `id` field (UUID string) on
 *     every workoutSessions doc — docs without it are silently dropped.
 *   - SavedPlansViewModel.parsePlans REQUIRES `id` (UUID string) + `planName`,
 *     and each exercise REQUIRES `id` (UUID string) + `name`.
 *   - StreakService reads streakData/current {currentStreak, longestStreak,
 *     lastWorkoutDate, achievements[{id, dateEarned}]}.
 *   - UserProfileService reads profile/health via UserProfile.from(firestoreData:).
 *
 * Usage:
 *   node virtual-users/seed_vuser_data.js               # seed veteran
 *   node virtual-users/seed_vuser_data.js --cleanup     # delete ALL vuser-* data
 *   node virtual-users/seed_vuser_data.js --verify      # print what exists per vuser
 *
 * The seed is deterministic (fixed UUIDs) so ground-truth assertions are stable.
 * Expected chart values from this seed (see virtual-users/personas/vuser-veteran.json):
 *   sessions=10, avgPain=4.8, totalMinutes=250, currentStreak=3, plan week 4/6.
 */

const path = require("path");
const admin = require(path.join(__dirname, "..", "functions", "node_modules", "firebase-admin"));

const PROJECT_ID = process.env.FIREBASE_PROJECT || "pt-helper-dev";
const VETERAN_UID = "vuser-veteran-001";

admin.initializeApp({
  projectId: PROJECT_ID,
  serviceAccountId: "firebase-adminsdk-fbsvc@" + PROJECT_ID + ".iam.gserviceaccount.com",
});

const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

// Fixed UUIDs so re-runs are idempotent and ground truth is stable.
const PLAN_ID = "AAAAAAAA-0000-4000-8000-000000000001";
const EX_IDS = [
  "BBBBBBBB-0000-4000-8000-000000000001",
  "BBBBBBBB-0000-4000-8000-000000000002",
  "BBBBBBBB-0000-4000-8000-000000000003",
];
const SESSION_ID_PREFIX = "CCCCCCCC-0000-4000-8000-0000000000"; // + 2-digit index

function daysAgo(n, hour = 9) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  d.setHours(hour, 30, 0, 0);
  return d;
}

// 10 sessions over 14 days, pain declining 7.0 -> 3.0, last 3 on consecutive
// days (today, yesterday, day before) so currentStreak=3 is consistent.
const SESSIONS = [
  { daysAgo: 13, pain: 7.0, duration: 1500, exercises: ["Wall Sits", "Straight Leg Raises"], regions: { right_knee: 7.0 } },
  { daysAgo: 12, pain: 6.5, duration: 1200, exercises: ["Clamshells", "Straight Leg Raises"], regions: { right_knee: 6.5, left_hip: 4.0 } },
  { daysAgo: 10, pain: 6.0, duration: 1800, exercises: ["Wall Sits", "Straight Leg Raises", "Clamshells"], regions: { right_knee: 6.0 } },
  { daysAgo: 9, pain: 5.5, duration: 1500, exercises: ["Wall Sits", "Clamshells"], regions: { right_knee: 5.5, left_hip: 3.5 } },
  { daysAgo: 7, pain: 5.0, duration: 1350, exercises: ["Straight Leg Raises", "Clamshells"], regions: { right_knee: 5.0 } },
  { daysAgo: 5, pain: 4.5, duration: 1800, exercises: ["Wall Sits", "Straight Leg Raises", "Clamshells"], regions: { right_knee: 4.5, left_hip: 3.0 } },
  { daysAgo: 4, pain: 4.0, duration: 1500, exercises: ["Wall Sits", "Straight Leg Raises"], regions: { right_knee: 4.0 } },
  { daysAgo: 2, pain: 3.5, duration: 1200, exercises: ["Clamshells", "Wall Sits"], regions: { right_knee: 3.5, left_hip: 2.5 } },
  { daysAgo: 1, pain: 3.0, duration: 1650, exercises: ["Wall Sits", "Straight Leg Raises", "Clamshells"], regions: { right_knee: 3.0 } },
  { daysAgo: 0, pain: 3.0, duration: 1500, exercises: ["Straight Leg Raises", "Clamshells"], regions: { right_knee: 3.0, left_hip: 2.0 } },
];

async function seedVeteran() {
  const userRef = db.doc(`users/${VETERAN_UID}`);

  // Marker on the parent doc — subcollection writes alone leave a phantom
  // parent that collection queries can't see.
  await userRef.set({ virtualUser: true, seededAt: Timestamp.now() });

  await userRef.collection("profile").doc("health").set({
    userId: VETERAN_UID,
    firstName: "Vera",
    lastName: "Veteran",
    dateOfBirth: Timestamp.fromDate(new Date("1985-03-20")),
    sex: "Female",
    heightFeet: 5,
    heightInches: 6,
    weight: 140.0,
    medicalConditions: [],
    surgeries: [],
    injuries: [],
    activityLevel: "Moderate",
  });

  await userRef.collection("rehabPlans").doc(PLAN_ID).set({
    id: PLAN_ID,
    planName: "Knee Recovery Plan",
    conditions: ["Patellofemoral Pain Syndrome"],
    exercises: [
      {
        id: EX_IDS[0], name: "Wall Sits", targetArea: "knee",
        description: "Isometric quad strengthening against a wall.",
        sets: 3, reps: "30 sec", restSeconds: 45, difficulty: "beginner",
        demonstrationIcon: "figure.strengthtraining.functional",
        tips: ["Keep knees behind toes"], contraindications: [],
      },
      {
        id: EX_IDS[1], name: "Straight Leg Raises", targetArea: "knee",
        description: "Quad activation with straight knee, lying down.",
        sets: 3, reps: "12", restSeconds: 30, difficulty: "beginner",
        demonstrationIcon: "figure.flexibility",
        tips: ["Keep core engaged"], contraindications: [],
      },
      {
        id: EX_IDS[2], name: "Clamshells", targetArea: "hip",
        description: "Side-lying hip abduction for glute medius.",
        sets: 3, reps: "15", restSeconds: 30, difficulty: "beginner",
        demonstrationIcon: "figure.flexibility",
        tips: ["Keep hips stacked"], contraindications: [],
      },
    ],
    weeklySchedule: {
      "0": [],
      "1": ["Wall Sits", "Straight Leg Raises"],
      "2": [],
      "3": ["Wall Sits", "Straight Leg Raises", "Clamshells"],
      "4": [],
      "5": ["Straight Leg Raises", "Clamshells"],
      "6": [],
    },
    totalWeeks: 6,
    createdDate: Timestamp.fromDate(daysAgo(21)),
    startDate: Timestamp.fromDate(daysAgo(21)),
    lastModifiedDate: Timestamp.fromDate(daysAgo(1)),
    planType: "rehab",
    schemaVersion: 2,
  });

  for (let i = 0; i < SESSIONS.length; i++) {
    const s = SESSIONS[i];
    const sessionId = SESSION_ID_PREFIX + String(i).padStart(2, "0");
    await userRef.collection("workoutSessions").doc(sessionId).set({
      id: sessionId,
      date: Timestamp.fromDate(daysAgo(s.daysAgo)),
      duration: s.duration,
      painLevel: s.pain,
      isCompleted: true,
      exercisesPerformed: s.exercises,
      regionPainLevels: s.regions,
      planId: PLAN_ID,
    });
  }

  await userRef.collection("streakData").doc("current").set({
    currentStreak: 3,
    longestStreak: 5,
    lastWorkoutDate: Timestamp.fromDate(daysAgo(0)),
    achievements: [
      { id: "first_workout", dateEarned: Timestamp.fromDate(daysAgo(13)) },
      { id: "streak_3", dateEarned: Timestamp.fromDate(daysAgo(0)) },
      { id: "sessions_10", dateEarned: Timestamp.fromDate(daysAgo(0)) },
    ],
  });

  const totalSeconds = SESSIONS.reduce((a, s) => a + s.duration, 0);
  const avgPain = SESSIONS.reduce((a, s) => a + s.pain, 0) / SESSIONS.length;
  console.log(`✅ Seeded ${VETERAN_UID}: 1 profile, 1 plan (week 4/6), ${SESSIONS.length} sessions, streak 3`);
  console.log(`   Ground truth: sessions=${SESSIONS.length}, avgPain=${avgPain.toFixed(2)}, totalMinutes=${Math.round(totalSeconds / 60)}`);
}

// --- Cleanup: delete ALL vuser-* footprints -------------------------------

async function deleteCollectionDocs(query, label) {
  const snap = await query.get();
  let n = 0;
  for (const doc of snap.docs) {
    await db.recursiveDelete(doc.ref);
    n++;
  }
  if (n > 0) console.log(`   deleted ${n} ${label}`);
  return n;
}

// All persona uids ever used — recursiveDelete works on phantom parents too,
// so deleting these is safe even if the user doc itself was never written.
const KNOWN_VUSER_IDS = [
  "vuser-veteran-001",
  "vuser-happy-path-001",
  "vuser-dropoff-001",
  "vuser-smoke-test",
];

async function collectVuserIds() {
  const ids = new Set(KNOWN_VUSER_IDS);
  // Auth records are created when a custom token is exchanged at sign-in.
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    page.users.forEach((u) => { if (u.uid.startsWith("vuser-")) ids.add(u.uid); });
    pageToken = page.pageToken;
  } while (pageToken);
  // Plus any vuser docs visible in the users collection (marker docs).
  const snap = await db.collection("users")
    .where(admin.firestore.FieldPath.documentId(), ">=", "vuser-")
    .where(admin.firestore.FieldPath.documentId(), "<", "vuser-").get();
  snap.docs.forEach((d) => ids.add(d.id));
  return [...ids];
}

async function cleanup() {
  // users/{vuser-*} and all subcollections (incl. phantom parents)
  const vuserIds = await collectVuserIds();
  for (const uid of vuserIds) {
    await db.recursiveDelete(db.doc(`users/${uid}`));
  }
  console.log(`   deleted ${vuserIds.length} users/{vuser-*} trees: ${vuserIds.join(", ")}`);

  // sessionLogs index docs (root collection, keyed by sessionId with userId field)
  const logSnap = await db.collection("sessionLogs")
    .where("userId", ">=", "vuser-").where("userId", "<", "vuser-").get();
  for (const doc of logSnap.docs) await doc.ref.delete();
  console.log(`   deleted ${logSnap.size} sessionLogs index docs`);

  // rate-limit windows created by claudeProxy (also phantom-parent shaped)
  for (const uid of vuserIds) {
    await db.recursiveDelete(db.doc(`rateLimits/${uid}`));
  }
  console.log(`   cleared rateLimits for ${vuserIds.length} vusers`);

  // Storage session log JSON trails
  try {
    const bucket = admin.storage().bucket(`${PROJECT_ID}.firebasestorage.app`);
    const [files] = await bucket.getFiles({ prefix: "sessionLogs/vuser-" });
    for (const f of files) await f.delete();
    console.log(`   deleted ${files.length} Storage session log files`);
  } catch (e) {
    console.warn(`   ⚠️ Storage cleanup skipped: ${e.message}`);
  }

  // Auth user records created by custom-token sign-in
  let deletedAuth = 0;
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    const vusers = page.users.filter((u) => u.uid.startsWith("vuser-")).map((u) => u.uid);
    if (vusers.length > 0) {
      await admin.auth().deleteUsers(vusers);
      deletedAuth += vusers.length;
    }
    pageToken = page.pageToken;
  } while (pageToken);
  console.log(`   deleted ${deletedAuth} Auth user records`);

  console.log("✅ Cleanup complete");
}

async function verify() {
  for (const uid of await collectVuserIds()) {
    const ref = db.doc(`users/${uid}`);
    const sessions = await ref.collection("workoutSessions").get();
    const plans = await ref.collection("rehabPlans").get();
    const profile = await ref.collection("profile").doc("health").get();
    const streak = await ref.collection("streakData").doc("current").get();
    if (sessions.size + plans.size + (profile.exists ? 1 : 0) + (streak.exists ? 1 : 0) === 0) continue;
    console.log(`  ${uid}: profile=${profile.exists} plans=${plans.size} sessions=${sessions.size} streak=${streak.exists}`);
  }
  const logSnap = await db.collection("sessionLogs")
    .where("userId", ">=", "vuser-").where("userId", "<", "vuser-\uf8ff").get();
  console.log(`sessionLogs (vuser-*): ${logSnap.size} index docs`);
}

const mode = process.argv.includes("--cleanup") ? "cleanup"
  : process.argv.includes("--verify") ? "verify" : "seed";

({ seed: seedVeteran, cleanup, verify })[mode]()
  .then(() => process.exit(0))
  .catch((e) => { console.error("FAILED: " + e.message); process.exit(1); });
