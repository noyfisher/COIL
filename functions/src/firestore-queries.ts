/**
 * Server-side Firestore data fetching for managed agent insights.
 * Mirrors the data assembly done by RecoveryInsightsViewModel.buildUserMessage() on iOS.
 */

import * as admin from "firebase-admin";

const LOOKBACK_DAYS = 14;
const MINIMUM_SESSION_COUNT = 3;

export interface RecoveryInsightsData {
  userMessage: string;
  sessionCount: number;
}

export async function fetchRecoveryInsightsData(uid: string): Promise<RecoveryInsightsData> {
  const db = admin.firestore();
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - LOOKBACK_DAYS);
  const cutoffTimestamp = admin.firestore.Timestamp.fromDate(cutoff);

  // Fetch sessions, plans, and profile in parallel
  const [sessionsSnap, plansSnap, profileDoc] = await Promise.all([
    db.collection(`users/${uid}/workoutSessions`)
      .where("date", ">=", cutoffTimestamp)
      .orderBy("date", "asc")
      .get(),
    db.collection(`users/${uid}/rehabPlans`)
      .orderBy("createdDate", "desc")
      .get(),
    db.doc(`users/${uid}/profile/health`).get(),
  ]);

  // Format sessions
  const sessionLines: string[] = [];
  for (const doc of sessionsSnap.docs) {
    const s = doc.data();
    const date = (s.date as admin.firestore.Timestamp).toDate();
    const dateStr = formatDate(date);
    const painLevel = s.painLevel ?? 0;
    const exerciseCount = (s.exercisesPerformed as string[] | undefined)?.length ?? 0;
    const duration = Math.round((s.duration ?? 0) / 60);

    let line = `- ${dateStr}: pain ${painLevel.toFixed(1)}/10, ${exerciseCount} exercises, ${duration} min`;

    // Per-region pain
    const regionPain = s.regionPainLevels as Record<string, number> | undefined;
    if (regionPain && Object.keys(regionPain).length > 0) {
      const regionStr = Object.entries(regionPain)
        .map(([region, level]) => `${region}: ${level.toFixed(1)}`)
        .join(", ");
      line += ` [regions: ${regionStr}]`;
    }

    // Linked plan name
    if (s.planId) {
      const linkedPlan = plansSnap.docs.find((p) => p.id === s.planId);
      if (linkedPlan) {
        line += ` (plan: ${linkedPlan.data().planName})`;
      }
    }

    sessionLines.push(line);
  }

  // Format plans
  const planLines: string[] = [];
  let expectedPerWeek = 0;
  for (const doc of plansSnap.docs) {
    const p = doc.data();
    const exercises = (p.exercises as Array<{ name: string }>) || [];
    const exerciseNames = exercises.map((e) => e.name).join(", ");
    // weeklySchedule is stored as a map { "0": [...], "2": [...] } with only non-empty days
    const weeklySchedule = (p.weeklySchedule as Record<string, string[]> | undefined) || {};
    const scheduledDays = Object.values(weeklySchedule).filter((day) => day.length > 0).length;
    expectedPerWeek += scheduledDays;
    const conditions = (p.conditions as string[]) || [];
    planLines.push(
      `- ${p.planName}: ${exercises.length} exercises (${exerciseNames}), ${scheduledDays} days/week scheduled, conditions: ${conditions.join(", ")}`
    );
  }

  // Format profile
  let profileContext = "Not available";
  if (profileDoc.exists) {
    const p = profileDoc.data()!;
    const parts: string[] = [];

    if (p.dateOfBirth) {
      const dob = (p.dateOfBirth as admin.firestore.Timestamp).toDate();
      const age = Math.floor((Date.now() - dob.getTime()) / (365.25 * 24 * 60 * 60 * 1000));
      parts.push(`${age} year old ${p.biologicalSex || "unknown"}`);
    }

    if (p.activityLevel) {
      parts.push(`activity level: ${p.activityLevel}`);
    }

    const conditions = p.medicalConditions as string[] | undefined;
    if (conditions && conditions.length > 0) {
      parts.push(`conditions: ${conditions.join(", ")}`);
    }

    const medications = p.medications as string[] | undefined;
    if (medications && medications.length > 0) {
      parts.push(`medications: ${medications.join(", ")}`);
    }

    if (parts.length > 0) {
      profileContext = parts.join(", ");
    }
  }

  const userMessage = `RECOVERY DATA (past ${LOOKBACK_DAYS} days):

WORKOUT SESSIONS (${sessionsSnap.size} total):
${sessionLines.length > 0 ? sessionLines.join("\n") : "None"}

ACTIVE REHAB PLANS:
${planLines.length > 0 ? planLines.join("\n") : "None"}

EXPECTED SESSIONS PER WEEK: ${expectedPerWeek > 0 ? expectedPerWeek.toString() : "Not scheduled"}

USER PROFILE: ${profileContext}

Please analyze this data and provide a weekly recovery digest.`;

  return {
    userMessage,
    sessionCount: sessionsSnap.size,
  };
}

export { MINIMUM_SESSION_COUNT };

function formatDate(date: Date): string {
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${months[date.getMonth()]} ${date.getDate()}`;
}
