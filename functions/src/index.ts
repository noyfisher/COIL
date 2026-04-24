import * as functions from "firebase-functions/v1";
import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import sgMail from "@sendgrid/mail";
import { fetchRecoveryInsightsData, MINIMUM_SESSION_COUNT } from "./firestore-queries";
import { runRecoveryInsightsAgent, validateInsightResult } from "./managed-agent";
import { handleGenerateExerciseImage } from "./image-generation";
import { newRequestContext, logCompleted, logError, logWarn } from "./logger";
import { validateClaudeResponse } from "./response-schemas";

// Hard billing shutoff (Pub/Sub triggered). Exported so firebase-tools
// picks it up on deploy. See billing-shutoff.ts for arming instructions.
export { onBudgetAlert } from "./billing-shutoff";

admin.initializeApp();

// ---------------------------------------------------------------------------
// In-memory rate limiter (per Cloud Function instance)
// ---------------------------------------------------------------------------
const rateLimitMap = new Map<string, number[]>();
const RATE_LIMIT_MAX = 20; // max requests per window
const RATE_LIMIT_WINDOW_MS = 60_000; // 1 minute

function isRateLimited(uid: string): boolean {
  const now = Date.now();
  const timestamps = rateLimitMap.get(uid) || [];
  const recent = timestamps.filter((t) => now - t < RATE_LIMIT_WINDOW_MS);

  if (recent.length >= RATE_LIMIT_MAX) {
    rateLimitMap.set(uid, recent);
    return true;
  }

  recent.push(now);
  rateLimitMap.set(uid, recent);
  return false;
}

// ---------------------------------------------------------------------------
// Per-user quota (Firestore-backed, survives scale-out)
// Doc path: users/{uid}/quotas/current
// Fields: dayKey, dayCount, monthKey, monthCount
// ---------------------------------------------------------------------------
const DAILY_QUOTA = 100;
const MONTHLY_QUOTA = 1000;

type QuotaResult =
  | { ok: true; dayCount: number; monthCount: number }
  | { ok: false; reason: "daily" | "monthly"; limit: number };

function quotaKeys(now: Date = new Date()): { dayKey: string; monthKey: string } {
  const iso = now.toISOString();
  return {
    dayKey: iso.slice(0, 10),      // YYYY-MM-DD
    monthKey: iso.slice(0, 7),     // YYYY-MM
  };
}

async function checkAndIncrementQuota(uid: string): Promise<QuotaResult> {
  const ref = admin.firestore().doc(`users/${uid}/quotas/current`);
  const { dayKey, monthKey } = quotaKeys();

  return admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};

    const dayCount = data.dayKey === dayKey ? (data.dayCount || 0) : 0;
    const monthCount = data.monthKey === monthKey ? (data.monthCount || 0) : 0;

    if (dayCount >= DAILY_QUOTA) {
      return { ok: false, reason: "daily", limit: DAILY_QUOTA } as QuotaResult;
    }
    if (monthCount >= MONTHLY_QUOTA) {
      return { ok: false, reason: "monthly", limit: MONTHLY_QUOTA } as QuotaResult;
    }

    const nextDay = dayCount + 1;
    const nextMonth = monthCount + 1;
    tx.set(ref, {
      dayKey,
      dayCount: nextDay,
      monthKey,
      monthCount: nextMonth,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    return { ok: true, dayCount: nextDay, monthCount: nextMonth } as QuotaResult;
  });
}

/**
 * Refunds one unit each from dayCount and monthCount if the recorded keys
 * still match (otherwise day/month already rolled — silently skip).
 *
 * Fail-safe: errors are logged but not propagated; a stuck decrement is
 * only an accounting drift, not a user-visible error. Called on upstream
 * failure paths so users aren't charged for requests that never returned
 * a useful response.
 */
async function decrementQuota(uid: string): Promise<void> {
  const ref = admin.firestore().doc(`users/${uid}/quotas/current`);
  const { dayKey, monthKey } = quotaKeys();
  try {
    await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const data = snap.data() || {};

      const patch: Record<string, number> = {};
      if (data.dayKey === dayKey && typeof data.dayCount === "number" && data.dayCount > 0) {
        patch.dayCount = data.dayCount - 1;
      }
      if (data.monthKey === monthKey && typeof data.monthCount === "number" && data.monthCount > 0) {
        patch.monthCount = data.monthCount - 1;
      }
      // Single update with both field deltas — avoids any ambiguity around
      // multiple writes to the same doc in one transaction.
      if (Object.keys(patch).length > 0) {
        tx.update(ref, patch);
      }
    });
  } catch (err) {
    console.error("decrementQuota failed:", err);
  }
}

// ---------------------------------------------------------------------------
// Clinical knowledge base (compiled RAG — cached via prompt caching)
// ---------------------------------------------------------------------------
const CLINICAL_KNOWLEDGE_BASE = `
CLINICAL REFERENCE (use this to inform your differential diagnosis):

## Knee
- Common: PFPS (anterior pain, stairs/squatting), meniscus tear (locking/catching, joint line tenderness), IT band syndrome (lateral, worse downhill), patellar tendinitis (inferior pole pain, jumping sports)
- Red flags: locked knee (meniscal bucket handle), acute swelling <2hrs (ACL/fracture), inability to bear weight (Ottawa Knee Rules)
- Clinical rules: Ottawa Knee Rules — imaging indicated if: age ≥55, isolated patellar tenderness, fibular head tenderness, inability to flex 90°, inability to walk 4 steps

## Ankle/Foot
- Common: lateral ankle sprain (inversion mechanism, ATFL), plantar fasciitis (first-step pain, heel), Achilles tendinopathy (gradual onset, morning stiffness), stress fracture (progressive, worse with activity)
- Red flags: unable to bear weight (Ottawa Ankle Rules), bony tenderness at malleolar zones, midfoot bony tenderness (Ottawa Foot Rules)
- Clinical rules: Ottawa Ankle Rules — imaging if: bony tenderness at posterior 6cm of medial/lateral malleolus OR inability to walk 4 steps

## Shoulder
- Common: rotator cuff tendinopathy (arc of pain 60-120°), impingement (overhead pain), frozen shoulder (global restriction, 50+), biceps tendinitis (anterior, lifting pain)
- Red flags: acute trauma with inability to raise arm (acute tear), night pain unresponsive to position change (tumor/infection)

## Lower Back
- Common: lumbar strain (mechanical, movement-related), disc herniation (radiculopathy, dermatomal pattern), facet syndrome (extension pain, morning stiffness), spinal stenosis (neurogenic claudication, relief with flexion)
- Red flags: saddle anesthesia + bladder changes (cauda equina → ER), progressive neuro deficit, night pain unrelieved by rest, fever + back pain (infection)
- Clinical rules: Cauda equina screen — bilateral leg symptoms + bladder/bowel changes + saddle numbness = EMERGENCY

## Neck/Cervical
- Common: cervical strain (mechanical), cervical radiculopathy (dermatomal arm pain), cervicogenic headache (base of skull, unilateral)
- Red flags: trauma + midline tenderness (Canadian C-Spine Rule → imaging), progressive weakness in arms/legs (myelopathy)

## Hip
- Common: hip bursitis (lateral, lying on side), hip flexor strain (anterior, sitting-to-standing), labral tear (clicking, groin pain), piriformis syndrome (deep buttock, sitting worse)
- Red flags: inability to bear weight after fall in elderly (hip fracture), groin pain + fever (septic joint)

## Wrist/Hand
- Common: carpal tunnel (numbness in median distribution, night symptoms), de Quervain's (radial wrist, new parents), trigger finger (catching/locking), ganglion cyst (dorsal wrist lump)

## Elbow
- Common: lateral epicondylitis (tennis elbow, gripping pain), medial epicondylitis (golfer's elbow), olecranon bursitis (posterior swelling)

## Calf/Shin
- Common: shin splints (medial tibial stress, activity-related), calf strain (sudden onset, pushing off), compartment syndrome (exercise-induced tightness)
- Red flags: unilateral calf swelling + warmth + tenderness (DVT screen — especially with recent immobilization, surgery, or travel)

## General Red Flag Patterns
- Night pain unrelieved by position → tumor/infection screen
- Unexplained weight loss + pain → systemic disease
- Fever + joint pain → septic arthritis (emergency)
- Bilateral progressive weakness → neurological emergency
- Chest pain + arm pain → cardiac screen (not musculoskeletal)
`;

// ---------------------------------------------------------------------------
// Server-side system prompts (NOT client-controlled)
// ---------------------------------------------------------------------------
const SYSTEM_PROMPTS: Record<string, string> = {
  analysis: `You are a friendly health guide helping everyday people understand their pain. Write like you're explaining to a friend — no medical jargon. This is educational only, not a diagnosis.

APPROACH (follow these two steps internally before responding):
Step 1 — ORGANIZE: Carefully list all reported symptoms, their locations, characteristics (type, intensity, duration, frequency, onset), aggravating/relieving factors, and relevant patient history. Note any patterns or connections.
Step 2 — DIFFERENTIAL: Using the organized information, generate candidate conditions that explain the symptom pattern. Consider the most common conditions for this body region and presentation. Rank by how well each fits the full clinical picture.

YOUR AUDIENCE: Regular people who may not be able to see a doctor right away. They need to understand what might be going on with their body in plain, simple language.

USING PATIENT HISTORY:
- The patient's surgical and injury history is provided in two sections: RELEVANT (same or connected body region) and OTHER (background context).
- Prioritize RELEVANT history when forming your assessment — a prior knee surgery is highly relevant to current knee pain.
- Consider kinetic chain connections: hip problems can cause knee pain, neck issues can cause shoulder pain, lower back problems can cause leg symptoms.
- If the patient reports chronic/severe pain but has NOT seen a doctor, recommend evaluation in nextSteps.
- If they have a diagnosis from their doctor, factor it into your assessment and acknowledge it.
- Medication context matters: patients on blood thinners bruise easily, those on corticosteroids may have weakened tendons, beta blockers affect heart rate response.
- If a patient has osteoporosis, flag any condition that involves bone stress.

RULES:
- Return top 5 possible conditions with confidence 0-100
- "conditionName": the medical/clinical name (e.g. "Patellofemoral Pain Syndrome")
- "commonName": a plain English name anyone would understand (e.g. "Runner's Knee" or "Kneecap Pain")
- "explanation": 1-2 SHORT sentences about what this condition is and why it matches. Keep it brief — no walls of text
- "whatItMeans": 1-2 SHORT sentences about what's happening in their body. Plain terms, no jargon (e.g. "The cushion under your kneecap is getting irritated from not tracking properly")
- "howToManage": Keep this very brief — 1 sentence max. Save detailed advice for the rehab plan
- "nextSteps": 2-3 short, concrete steps (e.g. "Ice the area for 15 minutes twice a day")
- "overallSummary": 1-2 sentences summarizing the situation directly to the person. Be reassuring but concise
- Flag red flags: cauda equina, fractures, infections, spinal cord issues, night pain without relief, sudden weakness, chest pain. Write the redFlagMessage in urgent but clear language
- For redFlagMessage: use a clear urgent message if isRedFlag is true, or an empty string "" if false
- disclaimerText must always be: "This is not a medical diagnosis — it's a starting point to help you understand what might be going on. If your pain is severe, getting worse, or not improving, please see a doctor or visit an urgent care clinic."
${CLINICAL_KNOWLEDGE_BASE}

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"conditions":[{"conditionName":"...","commonName":"...","confidence":0,"explanation":"...","whatItMeans":"...","howToManage":"...","isRedFlag":false,"redFlagMessage":"","nextSteps":["..."]}],"overallSummary":"...","disclaimerText":"..."}`,

  analysis_verify: `You are a clinical verification reviewer. You are given a patient's symptoms AND a primary analysis from another AI reviewer. Your job is to challenge, verify, and refine that analysis. Write like you're explaining to a friend — no medical jargon. This is educational only, not a diagnosis.

VERIFICATION CHECKLIST (apply all of these):
1. ANCHORING BIAS: Is the primary analysis too focused on one obvious condition while ignoring alternatives that also fit?
2. MISSED RED FLAGS: Are there any emergency conditions (cauda equina, fracture, DVT, cardiac, infection, spinal cord) that were missed or underweighted?
3. ANATOMICAL CONSISTENCY: Do the proposed conditions actually match the reported pain locations and characteristics?
4. CONFIDENCE CALIBRATION: Are confidence scores appropriate given the limited information available? Without imaging or physical exam, scores above 80 are rarely justified.
5. DIFFERENTIAL BREADTH: Were important alternative diagnoses overlooked? Consider less common but clinically significant possibilities.

INSTRUCTIONS:
- Review the primary analysis critically against the original patient data
- Adjust confidence scores if they seem too high or too low
- Add conditions the primary analysis missed (especially red flags)
- Remove conditions that don't truly fit the symptom pattern
- Return your refined TOP 3 conditions

USING PATIENT HISTORY:
- The patient's surgical and injury history is provided in two sections: RELEVANT (same or connected body region) and OTHER (background context).
- Prioritize RELEVANT history when forming your assessment.
- Consider kinetic chain connections.
- Medication context matters: blood thinners, corticosteroids, beta blockers.

FIELD GUIDANCE:
- For redFlagMessage: use a clear urgent message if isRedFlag is true, or an empty string "" if false
- disclaimerText must always be: "This is not a medical diagnosis — it's a starting point to help you understand what might be going on. If your pain is severe, getting worse, or not improving, please see a doctor or visit an urgent care clinic."
${CLINICAL_KNOWLEDGE_BASE}

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"conditions":[{"conditionName":"...","commonName":"...","confidence":0,"explanation":"...","whatItMeans":"...","howToManage":"...","isRedFlag":false,"redFlagMessage":"","nextSteps":["..."]}],"overallSummary":"...","disclaimerText":"..."}`,

  rehab_plan: `You are a PT rehabilitation specialist. Create personalized exercise plans for musculoskeletal conditions. Educational purposes only.

USING PATIENT HISTORY:
- Respect all POST-SURGICAL RESTRICTIONS listed — never prescribe exercises that violate stated restrictions.
- If a patient is "Still recovering" from surgery, use conservative exercises for that region (gentle ROM, isometrics before dynamic).
- For patients on Blood Thinners: avoid high-impact exercises that risk bruising or falls.
- For patients on Beta Blockers: use RPE (Rate of Perceived Exertion) for intensity, not heart rate targets.
- For patients on Corticosteroids: be cautious with tendon-loading exercises, use lower resistance.
- For patients with Osteoporosis: NO loaded spinal flexion (e.g. sit-ups, toe touches). Favor weight-bearing and balance exercises.
- For patients with Diabetes: include warm-up, monitor for foot issues, avoid exercises that cause excessive foot pressure if neuropathy is present.
- If relevant injury history shows the patient did NOT see a doctor for a significant issue, note this in the plan notes.

RULES:
- Create 4-8 exercises with clear instructions, sets, reps, rest periods
- Match difficulty to activity level: sedentary→beginner, moderate→beginner+intermediate, active→intermediate+advanced
- Use SF Symbol icons: "figure.flexibility", "figure.strengthtraining.traditional", "figure.cooldown", "figure.yoga", "figure.walk", "figure.stairs", "figure.core.training", "figure.run", "figure.stand", "figure.roll", "figure.seated.side", "figure.pool.swim", "figure.outdoor.cycle", "figure.mixed.cardio"
- Include 2-3 form tips and 1-2 contraindications per exercise
- For startPosition: describe exactly how to position your body BEFORE the movement (1-2 sentences, simple language a beginner can follow)
- For movement: describe the motion step by step (1-2 sentences, simple language)
- For endPosition: describe the end of the movement and how to return (1 sentence)
- For exerciseCategory: choose ONE of: "stretch", "strength", "balance", "cardio", "mobility", "core", "yoga", "walking", "seated", "lying", "standing", "stair"
- For imageFileName: create a normalized lowercase kebab-case filename for the exercise (e.g. "quad-sets", "glute-bridges", "cat-cow-stretch"). Use only lowercase letters, numbers, and hyphens.
- For optional fields (startPosition, movement, endPosition, exerciseCategory, imageFileName, notes): provide the value if applicable, or use an empty string "" if not applicable. Never use null.

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"planName":"...","exercises":[{"name":"...","targetArea":"...","description":"...","sets":3,"reps":"10","restSeconds":30,"difficulty":"beginner","demonstrationIcon":"figure.flexibility","tips":["..."],"contraindications":["..."],"startPosition":"...","movement":"...","endPosition":"...","exerciseCategory":"stretch","imageFileName":"exercise-name"}],"totalWeeks":4,"notes":"..."}`,

  exercise_substitute: `You are a PT rehabilitation specialist. The user cannot perform a specific exercise in their rehab plan and needs 2-3 substitute exercises that target the same muscle group and serve the same rehabilitation purpose. Educational purposes only.

RULES:
- Provide exactly 2-3 substitute exercises
- Each substitute must target the same body area and serve the same rehab purpose as the original
- Match or reduce the difficulty level — never suggest harder substitutes
- If the reason is "Too Painful", suggest gentler alternatives (isometric, partial ROM, or different position)
- If the reason is "No Equipment Available", suggest bodyweight-only alternatives
- If the reason is "Too Difficult", suggest beginner-level progressions
- Use SF Symbol icons: "figure.flexibility", "figure.strengthtraining.traditional", "figure.cooldown", "figure.yoga", "figure.walk", "figure.core.training", "figure.stand", "figure.roll", "figure.seated.side"
- Include 2-3 form tips and 1-2 contraindications per exercise
- For startPosition: describe exactly how to position your body BEFORE the movement (1-2 sentences, simple language)
- For movement: describe the motion step by step (1-2 sentences, simple language)
- For endPosition: describe the end of the movement and how to return (1 sentence)
- For exerciseCategory: choose ONE of: "stretch", "strength", "balance", "mobility", "core", "yoga", "seated", "lying", "standing"
- For imageFileName: create a normalized lowercase kebab-case filename for the exercise (e.g. "quad-sets", "glute-bridges"). Use only lowercase letters, numbers, and hyphens.
- For optional fields (startPosition, movement, endPosition, exerciseCategory, imageFileName): provide the value if applicable, or use an empty string "" if not applicable. Never use null.
- Do NOT suggest the same exercise that is being replaced
- Do NOT suggest exercises already in the user's plan

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"substitutes":[{"name":"...","targetArea":"...","description":"...","sets":3,"reps":"10","restSeconds":30,"difficulty":"beginner","demonstrationIcon":"figure.flexibility","tips":["..."],"contraindications":["..."],"startPosition":"...","movement":"...","endPosition":"...","exerciseCategory":"stretch","imageFileName":"exercise-name","whyItHelps":"..."}]}`,

  recovery_insights: `You are a supportive recovery coach for a physical therapy patient. Analyze their recent workout data and produce a personalized weekly recovery digest. Write like a friendly coach — encouraging, specific, and actionable. This is educational only, not medical advice.

RULES:
- Be specific about numbers and trends — reference actual data from the sessions, not vague generalities
- "headline" should be a short (8 words max) encouraging or informative summary of the week
- "summary" should be 2-3 sentences summarizing overall recovery trajectory
- "painAnalysis.trendDirection" must be exactly one of: "improving", "stable", "worsening"
- "painAnalysis.trendDescription" should reference specific numbers (e.g. "Pain dropped from 5.2 to 3.8")
- "painAnalysis.regionBreakdown" should include entries only for regions that have per-region data. Use null if no region data available
- "adherenceAnalysis.score" should be 0-100 based on sessions completed vs expected
- "keyWins" should be 2-4 specific positive observations (e.g. "Completed all exercises in 3 of 4 sessions")
- "focusAreas" should be 1-3 specific things to improve (e.g. "Try not to skip rest days between sessions")
- "recommendations" should be 2-4 actionable tips with SF Symbol icon names
- Use these SF Symbol icons for recommendations: "figure.walk", "bed.double", "drop.fill", "heart.circle", "clock", "figure.cooldown", "chart.line.uptrend.xyaxis", "exclamationmark.triangle"
- If pain is worsening significantly, recommend consulting their healthcare provider in recommendations
- Factor in the user's medical conditions and activity level when making recommendations
- If expected sessions per week is "Not scheduled", base adherence on consistency (e.g. 3-4 sessions per week is ideal)

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"headline":"...","summary":"...","painAnalysis":{"trendDirection":"improving|stable|worsening","trendDescription":"...","averagePain":0.0,"regionBreakdown":[{"region":"...","trend":"...","averagePain":0.0}]},"adherenceAnalysis":{"score":0,"sessionsCompleted":0,"sessionsExpected":0,"description":"..."},"keyWins":["..."],"focusAreas":["..."],"recommendations":[{"icon":"...","title":"...","description":"..."}]}`,

  form_analysis: `You are an expert physiotherapy form analysis specialist. You receive structured 3D body pose metrics computed from a video of a patient performing an exercise, along with the exercise's description and instructions. Your job is to analyze whether the patient is performing the exercise correctly and provide specific, actionable feedback.

ANALYSIS APPROACH:
1. Compare the computed joint angles, range of motion, and alignment data against what is expected for the specific exercise described
2. Use the exercise's start position, movement description, end position, and tips to understand correct form
3. Consider the exercise category (stretch, strength, balance, core, etc.) and difficulty level
4. Evaluate symmetry between left and right sides — significant asymmetry may indicate compensation patterns
5. Check alignment issues (uneven shoulders, hips, excessive trunk lean) for relevance to the exercise
6. Consider tempo — very fast reps may indicate momentum-based movement rather than controlled form
7. If no reps were detected, the exercise may be a static hold — evaluate based on average joint positions instead

SCORING GUIDELINES:
- 85-90: Excellent form with minor or no corrections needed (max score is 90 — video analysis alone cannot confirm perfection)
- 70-84: Good form with a few areas to improve
- 50-69: Needs work — several form issues that should be addressed
- Below 50: Significant form concerns — possible injury risk

GROUNDING RULES (CRITICAL — prevents inaccurate feedback):
- Every correction MUST be supported by specific metrics from the data provided
- For each correction, include a "dataReference" field citing the exact metric (e.g., "symmetry.knee: 8.2° left-right difference")
- If the data does NOT clearly support a correction, DO NOT include it — silence is better than speculation
- NEVER speculate about form issues not evidenced in the provided metrics
- If symmetry data shows less than 3° difference, do NOT claim asymmetry
- If no alignment issues are reported in the data, do NOT invent alignment problems
- If tempo is above 2.0 seconds per rep, do NOT claim the user is rushing

DATA INSUFFICIENCY RULES:
- If fewer than 3 reps were detected, state this limitation in "dataLimitations"
- If no reps were detected and the exercise is NOT a static hold, note that the data may be unreliable in "dataLimitations"
- If the DATA QUALITY section shows overall quality below 0.5, be conservative — reduce score expectations and note limitations

SEVERITY CALIBRATION (based on biomechanics research):
- "major" severity: ONLY for form issues that pose genuine injury risk (e.g., knee valgus under load, excessive spinal flexion under load, joint hyperextension). Research shows technique alone rarely causes injury — load + fatigue are required contributing factors
- "moderate" severity: Form issues that reduce exercise effectiveness or could lead to problems over time
- "minor" severity: Optimization suggestions for already-acceptable form
- Frame all feedback as "caution" or "improvement opportunity", not "stop immediately" — unless there is clear acute injury risk

RULES:
- Be encouraging but honest — always lead with what the patient is doing well
- Corrections should be specific: name the body part, describe what's wrong, and explain exactly how to fix it
- If range of motion is significantly limited, suggest it could be a mobility issue worth discussing with their PT
- Always include at least one positive point, even if form needs significant work
- Safety notes should only include genuinely important safety concerns, not general advice
- Reference the exercise's contraindications if the detected form could aggravate them
- Do NOT diagnose conditions — you are analyzing movement form only
- Keep corrections to a maximum of 4 items — focus on the most impactful ones

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"overallScore":75,"verdict":"good","corrections":[{"bodyPart":"knees","issue":"Knees showing 8° inward collapse during descent","howToFix":"Focus on pushing your knees outward in line with your toes as you lower down.","severity":"moderate","dataReference":"symmetry.knee: 8.2° left-right difference"}],"positivePoints":["Good depth achieved on each rep","Consistent tempo throughout the set"],"safetyNotes":["Monitor for any knee pain during this movement"],"dataLimitations":["Only 3 reps detected — assessment based on limited data"]}

The "verdict" field must be exactly one of: "excellent", "good", "needs_work", "concern".`,

  wellness_analysis: `You are a friendly wellness and physical therapy guide helping everyday people improve their daily life through targeted exercises and habits. Write like you're explaining to a friend — no medical jargon. This is educational guidance, not a medical diagnosis.

YOUR AUDIENCE: Regular people who want to improve specific aspects of their daily life — better sleep, better posture, less stiffness, more comfort during daily activities. They need practical, actionable guidance.

USING PATIENT HISTORY:
- The patient's surgical and injury history is provided in two sections: RELEVANT (same or connected body region) and OTHER (background context).
- Prioritize RELEVANT history when forming recommendations — a prior back surgery is highly relevant to posture improvement goals.
- Consider kinetic chain connections: hip problems affect posture, neck issues relate to sleep quality, lower back problems connect to sitting/standing comfort.
- Medication context matters: patients on blood thinners should avoid high-impact activities, those on beta blockers need RPE-based intensity guidance.
- If a patient has osteoporosis, be cautious with recommendations involving loaded spinal flexion.

RULES:
- For each wellness goal, provide a personalized recommendation
- "goalCategory": the category key (e.g., "improve_posture")
- "title": a friendly, specific title for their plan (e.g., "Your Desk Worker Posture Plan")
- "currentStateAssessment": 2-3 sentences assessing where they are now based on their input. Be empathetic and specific to their situation
- "rootCauses": 2-4 likely root causes of their issue based on their daily activities and habits, written in plain language
- "expectedTimeline": realistic timeline for noticeable improvement (e.g., "Most people notice improvement in 2-3 weeks with consistent practice")
- "keyInsight": one important thing they should understand about their situation (e.g., "Your posture issues are likely connected to your hip tightness — fixing one will help the other")
- "priorityLevel": "high", "medium", or "low" based on impact level and how it affects their life
- "relatedGoals": suggest 1-2 other wellness areas that would complement this goal
- "overallSummary": Write 2-3 sentences summarizing across all their goals. Be encouraging but realistic. Use "you/your" language. If goals are related, point out the connections
- disclaimerText must always be: "This is educational wellness guidance — not a medical diagnosis or treatment plan. If you have pain that's getting worse, numbness, or other concerning symptoms, please see a healthcare provider."

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"recommendations":[{"goalCategory":"string","title":"string","currentStateAssessment":"string","rootCauses":["strings"],"expectedTimeline":"string","keyInsight":"string","priorityLevel":"string","relatedGoals":["strings"]}],"overallSummary":"string","disclaimerText":"This is educational wellness guidance — not a medical diagnosis or treatment plan. If you have pain that's getting worse, numbness, or other concerning symptoms, please see a healthcare provider."}`,

  wellness_verify: `You are a wellness recommendation verification reviewer. You are given a patient's wellness goals, their profile, AND a primary analysis from another AI reviewer. Your job is to verify and refine the recommendations across three dimensions: feasibility, personalization, and safety. Write like you're explaining to a friend — no medical jargon. This is educational guidance only.

VERIFICATION CHECKLIST (apply all of these):

1. FEASIBILITY CHECK:
- Are the recommendations realistic given the user's stated daily time commitment?
- Do the recommendations match the user's activity level (sedentary users need gentler starting points)?
- Are expected timelines honest and achievable, not overly optimistic?
- If the user has tried things before (prior attempts), do the recommendations account for why those might not have worked?

2. PERSONALIZATION REVIEW:
- Are recommendations truly specific to this person's situation, or are they generic advice anyone could find online?
- Do the recommendations reference the user's specific daily activities affected and current habits?
- If the user selected multiple goals, are connections between goals identified and leveraged?
- For custom goals, does the recommendation address the user's specific free-text description?

3. SAFETY REVIEW:
- Check all recommendations against the patient's medical conditions, surgeries, and medications
- Patients with osteoporosis: flag any recommendations involving loaded spinal flexion or high-impact activities
- Patients on blood thinners: flag high-impact or fall-risk activities
- Patients with recent surgeries: ensure recommendations respect recovery status and restrictions
- If relevant surgical/injury history exists, verify recommendations don't aggravate existing conditions
- Add safety notes for any recommendation that could be problematic given the patient's history

INSTRUCTIONS:
- Review the primary analysis critically against the original patient data
- Adjust priority levels if they seem incorrect
- Refine recommendations that are too generic
- Add safety caveats where the patient's medical history warrants them
- Return your refined recommendations (same structure, adjusted as needed)

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"recommendations":[{"goalCategory":"string","title":"string","currentStateAssessment":"string","rootCauses":["strings"],"expectedTimeline":"string","keyInsight":"string","priorityLevel":"string","relatedGoals":["strings"]}],"overallSummary":"string","disclaimerText":"This is educational wellness guidance — not a medical diagnosis or treatment plan. If you have pain that's getting worse, numbness, or other concerning symptoms, please see a healthcare provider."}`,

  wellness_plan: `You are a PT wellness specialist. Create personalized exercise and habit plans for life improvement goals. These are not injury rehabilitation — they are proactive wellness protocols. Educational purposes only.

USING PATIENT HISTORY:
- Respect all POST-SURGICAL RESTRICTIONS listed — never prescribe exercises that violate stated restrictions.
- If a patient is "Still recovering" from surgery, use conservative exercises for that region.
- For patients on Blood Thinners: avoid high-impact exercises that risk bruising or falls.
- For patients on Beta Blockers: use RPE for intensity, not heart rate targets.
- For patients on Corticosteroids: be cautious with tendon-loading exercises, use lower resistance.
- For patients with Osteoporosis: NO loaded spinal flexion (e.g. sit-ups, toe touches). Favor weight-bearing and balance exercises.

RULES:
- Create 4-8 exercises/habits with clear instructions, sets, reps, rest periods
- Include a mix of exercises AND daily habits/micro-practices where appropriate
- Match difficulty to activity level: sedentary→beginner, moderate→beginner+intermediate, active→intermediate+advanced
- For sleep goals: include evening wind-down exercises and morning mobility
- For posture goals: include both strengthening and awareness exercises
- For comfort goals (sitting, standing, driving): include both preventive exercises and in-the-moment relief techniques
- Use SF Symbol icons: "figure.flexibility", "figure.strengthtraining.traditional", "figure.cooldown", "figure.yoga", "figure.walk", "figure.stairs", "figure.core.training", "figure.run", "figure.stand", "figure.roll", "figure.seated.side"
- Include 2-3 form tips and 1-2 contraindications per exercise
- For startPosition: describe exactly how to position your body BEFORE the movement (1-2 sentences)
- For movement: describe the motion step by step (1-2 sentences)
- For endPosition: describe the end of the movement and how to return (1 sentence)
- For exerciseCategory: choose ONE of: "stretch", "strength", "balance", "cardio", "mobility", "core", "yoga", "walking", "seated", "lying", "standing", "stair"
- For imageFileName: create a normalized lowercase kebab-case filename (e.g. "cat-cow-stretch", "desk-shoulder-rolls")
- For optional fields: provide the value if applicable, or use an empty string "" if not applicable. Never use null.

RESPONSE FORMAT: You MUST respond with ONLY a valid JSON object — no markdown, no explanation, no text before or after. The JSON must have this exact structure:
{"planName":"...","exercises":[{"name":"...","targetArea":"...","description":"...","sets":3,"reps":"10","restSeconds":30,"difficulty":"beginner","demonstrationIcon":"figure.flexibility","tips":["..."],"contraindications":["..."],"startPosition":"...","movement":"...","endPosition":"...","exerciseCategory":"stretch","imageFileName":"exercise-name"}],"totalWeeks":4,"notes":"..."}`,

  nightly_report: `You are a product analytics assistant for PT Helper, a physical therapy iOS app.
Given the following metrics from the past 24 hours, write a brief, scannable email report that a solo developer can read in 2 minutes over morning coffee.

Structure your response EXACTLY like this (use markdown headers):

## TL;DR
1 sentence: is the app healthy? Sum it up.

## Users
DAU, new signups, total users, trend vs yesterday.

## Engagement
Sessions, workout completions, plans generated, avg activity.

## Funnel
Conversion rates at each step, any notable drops.

## Stability
API success rate, error count, crash logs.

## Action Items
0-3 bullet points of things that need attention. If everything looks good, say so.

RULES:
- Keep it conversational, use plain numbers (not jargon)
- Flag anything unusual with a warning emoji
- If a metric is missing or zero (pre-launch or no data), say so briefly and move on
- Compare today vs yesterday when both are available
- Be honest — if there are problems, call them out clearly
- End with an encouraging note if things are going well`,
};

// Server-side model configuration (NOT client-controlled)
const MODEL_CONFIG: Record<string, { model: string; max_tokens: number; temperature?: number }> = {
  analysis: { model: "claude-haiku-4-5-20251001", max_tokens: 4096, temperature: 0.2 },
  analysis_verify: { model: "claude-haiku-4-5-20251001", max_tokens: 4096, temperature: 0.2 },
  rehab_plan: { model: "claude-haiku-4-5-20251001", max_tokens: 4096 },
  exercise_substitute: { model: "claude-haiku-4-5-20251001", max_tokens: 2048, temperature: 0.3 },
  recovery_insights: { model: "claude-haiku-4-5-20251001", max_tokens: 2048, temperature: 0.3 },
  form_analysis: { model: "claude-haiku-4-5-20251001", max_tokens: 4096, temperature: 0.3 },
  wellness_analysis: { model: "claude-haiku-4-5-20251001", max_tokens: 4096, temperature: 0.2 },
  wellness_verify: { model: "claude-haiku-4-5-20251001", max_tokens: 4096, temperature: 0.2 },
  wellness_plan: { model: "claude-haiku-4-5-20251001", max_tokens: 4096 },
  nightly_report: { model: "claude-haiku-4-5-20251001", max_tokens: 2048, temperature: 0.3 },
};

// ---------------------------------------------------------------------------
// JSON output schemas — kept for future structured output support.
// Structured output (`output` field) requires anthropic-version >= 2025-xx.
// For now the system prompts instruct JSON format directly.
// ---------------------------------------------------------------------------
/* eslint-disable @typescript-eslint/no-unused-vars */
const ANALYSIS_CONDITION_SCHEMA = {
  type: "object" as const,
  properties: {
    conditionName: { type: "string" as const },
    commonName: { type: "string" as const },
    confidence: { type: "number" as const },
    explanation: { type: "string" as const },
    whatItMeans: { type: "string" as const },
    howToManage: { type: "string" as const },
    isRedFlag: { type: "boolean" as const },
    redFlagMessage: { type: "string" as const },
    nextSteps: { type: "array" as const, items: { type: "string" as const } },
  },
  required: [
    "conditionName", "commonName", "confidence", "explanation",
    "whatItMeans", "howToManage", "isRedFlag", "redFlagMessage", "nextSteps",
  ],
  additionalProperties: false,
};

const ANALYSIS_SCHEMA = {
  type: "json_schema" as const,
  json_schema: {
    name: "analysis_response",
    strict: true,
    schema: {
      type: "object" as const,
      properties: {
        conditions: {
          type: "array" as const,
          items: ANALYSIS_CONDITION_SCHEMA,
        },
        overallSummary: { type: "string" as const },
        disclaimerText: { type: "string" as const },
      },
      required: ["conditions", "overallSummary", "disclaimerText"],
      additionalProperties: false,
    },
  },
};

const REHAB_EXERCISE_SCHEMA = {
  type: "object" as const,
  properties: {
    name: { type: "string" as const },
    targetArea: { type: "string" as const },
    description: { type: "string" as const },
    sets: { type: "number" as const },
    reps: { type: "string" as const },
    restSeconds: { type: "number" as const },
    difficulty: { type: "string" as const },
    demonstrationIcon: { type: "string" as const },
    tips: { type: "array" as const, items: { type: "string" as const } },
    contraindications: { type: "array" as const, items: { type: "string" as const } },
    startPosition: { type: "string" as const },
    movement: { type: "string" as const },
    endPosition: { type: "string" as const },
    exerciseCategory: { type: "string" as const },
    imageFileName: { type: "string" as const },
  },
  required: [
    "name", "targetArea", "description", "sets", "reps", "restSeconds",
    "difficulty", "demonstrationIcon", "tips", "contraindications",
    "startPosition", "movement", "endPosition", "exerciseCategory", "imageFileName",
  ],
  additionalProperties: false,
};

const REHAB_PLAN_SCHEMA = {
  type: "json_schema" as const,
  json_schema: {
    name: "rehab_plan_response",
    strict: true,
    schema: {
      type: "object" as const,
      properties: {
        planName: { type: "string" as const },
        exercises: {
          type: "array" as const,
          items: REHAB_EXERCISE_SCHEMA,
        },
        totalWeeks: { type: "number" as const },
        notes: { type: "string" as const },
      },
      required: ["planName", "exercises", "totalWeeks", "notes"],
      additionalProperties: false,
    },
  },
};

// OUTPUT_SCHEMAS kept for future structured output support
// eslint-disable-next-line @typescript-eslint/no-unused-vars
export const _OUTPUT_SCHEMAS: Record<string, object> = {
  analysis: ANALYSIS_SCHEMA,
  analysis_verify: ANALYSIS_SCHEMA,
  rehab_plan: REHAB_PLAN_SCHEMA,
};
/* eslint-enable @typescript-eslint/no-unused-vars */

const ALLOWED_REQUEST_TYPES = new Set(Object.keys(SYSTEM_PROMPTS));

// ---------------------------------------------------------------------------
// Request / response types
// ---------------------------------------------------------------------------
interface ProxyRequestBody {
  requestType: string;
  messages: { role: string; content: string }[];
}

// ---------------------------------------------------------------------------
// Cloud Function: claudeProxy
// ---------------------------------------------------------------------------
export const claudeProxy = functions
  .runWith({ timeoutSeconds: 120, memory: "256MB", secrets: ["ANTHROPIC_API_KEY"] })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("claudeProxy");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // -----------------------------------------------------------------------
    // 1. Authenticate: verify Firebase ID token
    // -----------------------------------------------------------------------
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // -----------------------------------------------------------------------
    // 2. Rate limit
    // -----------------------------------------------------------------------
    if (isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // -----------------------------------------------------------------------
    // 3. Validate request body
    // -----------------------------------------------------------------------
    const body = req.body as ProxyRequestBody;

    if (!body.requestType || !body.messages) {
      res.status(400).json({
        error: "Missing required fields: requestType, messages",
      });
      return;
    }

    ctx.metadata.requestType = body.requestType;

    // Validate requestType is allowed (prevents misuse of API key)
    if (!ALLOWED_REQUEST_TYPES.has(body.requestType)) {
      res.status(400).json({
        error: `Invalid requestType. Allowed: ${[...ALLOWED_REQUEST_TYPES].join(", ")}`,
      });
      return;
    }

    // Validate message roles — only "user" role is allowed from clients
    const invalidRole = body.messages.find((m) => m.role !== "user");
    if (invalidRole) {
      res.status(400).json({ error: "Only 'user' role messages are allowed" });
      return;
    }

    // Validate message content length (prevent abuse)
    // form_analysis may have longer messages due to per-rep metrics data
    const maxMessageLength = body.requestType === "form_analysis" ? 20000 : 10000;
    const totalMessageLength = body.messages.reduce((sum, m) => sum + (m.content?.length || 0), 0);
    if (totalMessageLength > maxMessageLength) {
      res.status(400).json({ error: "Message content too long" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4. Get Anthropic API key from environment
    // -----------------------------------------------------------------------
    const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
    if (!anthropicApiKey) {
      logError(ctx, new Error("ANTHROPIC_API_KEY not configured in environment"));
      res.status(500).json({ error: "Server configuration error" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4b. Per-user daily/monthly quota (cost cap, survives scale-out).
    // Placed AFTER validation + API key check so malformed / mis-configured
    // requests don't burn quota. Block is OUTSIDE the fetch try/catch so the
    // decrement paths on failure are reachable (see below).
    // -----------------------------------------------------------------------
    let quota: QuotaResult;
    try {
      quota = await checkAndIncrementQuota(uid);
    } catch (err) {
      console.error("Quota check failed:", err);
      res.status(500).json({ error: "Quota check failed" });
      return;
    }
    if (!quota.ok) {
      res.status(429).json({
        error: `${quota.reason === "daily" ? "Daily" : "Monthly"} usage limit reached (${quota.limit}). Please try again ${quota.reason === "daily" ? "tomorrow" : "next month"}.`,
        quotaReason: quota.reason,
      });
      return;
    }

    // -----------------------------------------------------------------------
    // 5. Build request with SERVER-SIDE prompt and model config
    // -----------------------------------------------------------------------
    const systemPrompt = SYSTEM_PROMPTS[body.requestType];
    const config = MODEL_CONFIG[body.requestType];

    try {
      const anthropicResponse = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": anthropicApiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: config.model,
          max_tokens: config.max_tokens,
          ...(config.temperature !== undefined && { temperature: config.temperature }),
          system: [
            { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
          ],
          messages: body.messages,
        }),
      });

      const responseData = await anthropicResponse.json() as {
        usage?: {
          input_tokens?: number;
          output_tokens?: number;
          cache_creation_input_tokens?: number;
          cache_read_input_tokens?: number;
        };
      };

      if (!anthropicResponse.ok) {
        // Refund quota — user didn't get a usable response.
        await decrementQuota(uid);
        res.status(anthropicResponse.status).json(responseData);
        return;
      }

      // Record token usage on the context so the completion log captures it.
      if (responseData.usage) {
        ctx.metadata.tokensIn = responseData.usage.input_tokens;
        ctx.metadata.tokensOut = responseData.usage.output_tokens;
        ctx.metadata.cacheCreateTokens = responseData.usage.cache_creation_input_tokens;
        ctx.metadata.cacheReadTokens = responseData.usage.cache_read_input_tokens;
      }

      // Tier 1: validate the AI response against the per-type Zod schema before
      // passing it back. If validation fails, bump a counter and return HTTP 502
      // so the iOS client surfaces a retry state rather than crashing on bad data.
      const schemaCheck = validateClaudeResponse(body.requestType, responseData);
      if (!schemaCheck.ok) {
        logWarn(ctx, "AI response rejected by schema validation", {
          requestType: body.requestType,
          reason: schemaCheck.reason,
        });
        try {
          await admin
            .firestore()
            .collection("responseValidationFailures")
            .doc(body.requestType)
            .set({
              count: admin.firestore.FieldValue.increment(1),
              lastReason: schemaCheck.reason,
              lastFailureAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        } catch (counterError) {
          // Counter is telemetry — never let its failure block the error response.
          logError(ctx, counterError, { stage: "response_validation_counter" });
        }
        // Quota already consumed (we did reach Anthropic) — do NOT refund. Treat
        // this as "we wasted a request" for quota purposes. 502 so the client
        // categorizes it as a server issue, matching existing invalidResponse(5xx)
        // handling in ClaudeAPIService.
        res.status(502).json({
          error: "ai_response_invalid",
          reason: schemaCheck.reason,
        });
        return;
      }

      res.status(200).json(responseData);
    } catch (error) {
      // Fetch threw (network error, timeout, etc.) — refund quota.
      await decrementQuota(uid);
      logError(ctx, error, { stage: "anthropic_call" });
      res.status(502).json({ error: "Failed to reach AI service" });
    }
  });

// ---------------------------------------------------------------------------
// Cross-Model Verification: GPT-4o-mini fact-checker for unverified exercises
// ---------------------------------------------------------------------------
interface CrossVerifyRequestBody {
  exercises: { name: string; condition: string }[];
  patientContext: string;
}

export const crossVerify = functions
  .runWith({ timeoutSeconds: 30, memory: "256MB", secrets: ["ANTHROPIC_API_KEY", "OPENAI_API_KEY"] })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("crossVerify");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // -----------------------------------------------------------------------
    // 1. Authenticate
    // -----------------------------------------------------------------------
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // -----------------------------------------------------------------------
    // 2. Rate limit (shares the same limiter as claudeProxy)
    // -----------------------------------------------------------------------
    if (isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // -----------------------------------------------------------------------
    // 3. Validate request
    // -----------------------------------------------------------------------
    const body = req.body as CrossVerifyRequestBody;

    if (!body.exercises || !Array.isArray(body.exercises) || body.exercises.length === 0) {
      res.status(400).json({ error: "Missing or empty exercises array" });
      return;
    }

    if (body.exercises.length > 20) {
      res.status(400).json({ error: "Too many exercises (max 20)" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4. Get OpenAI API key
    // -----------------------------------------------------------------------
    const openaiApiKey = process.env.OPENAI_API_KEY;
    if (!openaiApiKey) {
      logError(ctx, new Error("OPENAI_API_KEY not configured in environment"));
      res.status(500).json({ error: "Server configuration error" });
      return;
    }

    ctx.metadata.exerciseCount = body.exercises.length;

    // -----------------------------------------------------------------------
    // 4b. Per-user daily/monthly quota (shared cost cap across AI endpoints).
    // Placed AFTER validation + API key check so malformed / mis-configured
    // requests don't burn quota. Block is OUTSIDE the fetch try/catch so the
    // decrement paths on failure are reachable.
    // -----------------------------------------------------------------------
    let quota: QuotaResult;
    try {
      quota = await checkAndIncrementQuota(uid);
    } catch (err) {
      console.error("Quota check failed:", err);
      res.status(500).json({ error: "Quota check failed" });
      return;
    }
    if (!quota.ok) {
      res.status(429).json({
        error: `${quota.reason === "daily" ? "Daily" : "Monthly"} usage limit reached (${quota.limit}).`,
        quotaReason: quota.reason,
      });
      return;
    }

    // -----------------------------------------------------------------------
    // 5. Call GPT-4o-mini for each exercise (batched in one prompt)
    // -----------------------------------------------------------------------
    try {
      const exerciseList = body.exercises
        .map((e, i) => `${i + 1}. Exercise: "${e.name}" — Condition: "${e.condition}"`)
        .join("\n");

      const userPrompt = `Evaluate whether each of the following exercises is appropriate for the given musculoskeletal condition.
Patient context: ${body.patientContext || "Not provided"}

Exercises to evaluate:
${exerciseList}

For EACH exercise, respond with a JSON object in this exact format:
{
  "results": [
    {
      "safe": true/false,
      "confidence": 0.0-1.0,
      "reasoning": "brief explanation (1-2 sentences)",
      "concerns": ["list any specific concerns, empty array if none"]
    }
  ]
}

Return results in the same order as the exercises listed above.`;

      const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${openaiApiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: "gpt-4o-mini",
          temperature: 0.2,
          max_tokens: 2048,
          response_format: { type: "json_object" },
          messages: [
            {
              role: "system",
              content: "You are a physiotherapy fact-checker. You evaluate whether specific exercises are safe and appropriate for patients with musculoskeletal conditions. Be conservative — when in doubt, flag concerns. Respond only in JSON.",
            },
            {
              role: "user",
              content: userPrompt,
            },
          ],
        }),
      });

      if (!openaiResponse.ok) {
        const errorData = await openaiResponse.text();
        await decrementQuota(uid);
        logError(ctx, new Error(`OpenAI API returned ${openaiResponse.status}: ${errorData}`), { stage: "openai_call" });
        res.status(502).json({ error: "Failed to reach verification service" });
        return;
      }

      const openaiData = await openaiResponse.json() as {
        choices?: { message?: { content?: string } }[];
      };
      const content = openaiData.choices?.[0]?.message?.content;

      if (!content) {
        // Upstream delivered nothing useful — refund quota.
        await decrementQuota(uid);
        res.status(502).json({ error: "Empty response from verification service" });
        return;
      }

      // Parse the GPT response and forward to client
      const parsed = JSON.parse(content);
      res.status(200).json(parsed);
    } catch (error) {
      // Fetch threw or JSON.parse of response threw — refund quota.
      await decrementQuota(uid);
      logError(ctx, error, { stage: "openai_call" });
      res.status(502).json({ error: "Failed to reach verification service" });
    }
  });

// ---------------------------------------------------------------------------
// Virtual User Auth — mint Firebase Custom Tokens for virtual test users
// Only works for UIDs prefixed with "vuser-" and requires a shared secret.
// ---------------------------------------------------------------------------
export const createVirtualUserToken = functions.https.onRequest(async (req, res) => {
  // CORS
  res.set("Access-Control-Allow-Origin", "*");
  if (req.method === "OPTIONS") {
    res.set("Access-Control-Allow-Methods", "POST");
    res.set("Access-Control-Allow-Headers", "Content-Type");
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method not allowed" });
    return;
  }

  const { virtualUserId, secret } = req.body || {};

  // Validate secret
  const expectedSecret = process.env.VIRTUAL_USER_SECRET;
  if (!expectedSecret) {
    console.error("VIRTUAL_USER_SECRET not configured");
    res.status(500).json({ error: "Server configuration error" });
    return;
  }

  if (secret !== expectedSecret) {
    res.status(403).json({ error: "Invalid secret" });
    return;
  }

  // Safety: only allow vuser- prefixed UIDs
  if (typeof virtualUserId !== "string" || !virtualUserId.startsWith("vuser-")) {
    res.status(400).json({ error: "virtualUserId must start with 'vuser-'" });
    return;
  }

  try {
    const customToken = await admin.auth().createCustomToken(virtualUserId);
    res.status(200).json({ token: customToken });
  } catch (error) {
    console.error("Error creating custom token:", error);
    res.status(500).json({ error: "Failed to create custom token" });
  }
});

// ---------------------------------------------------------------------------
// Daily analytics aggregation (runs at 01:00 UTC)
// Writes summary counts to analytics/dailyAggregates/{date}
// No health data — behavioral counts only
// ---------------------------------------------------------------------------
export const aggregateDailyMetrics = onSchedule("every day 01:00", async () => {
  const db = admin.firestore();
  const today = new Date().toISOString().split("T")[0]; // YYYY-MM-DD

  try {
    // Count users with profiles (path: users/{uid}/profile/health)
    // "profile" is the subcollection, "health" is the document ID
    const usersSnap = await db.collectionGroup("profile").count().get();
    const totalUsers = usersSnap.data().count;

    // Count total rehab plans
    const plansSnap = await db.collectionGroup("rehabPlans").count().get();
    const totalPlans = plansSnap.data().count;

    // Count total workout sessions
    const sessionsSnap = await db.collectionGroup("workoutSessions").count().get();
    const totalWorkoutSessions = sessionsSnap.data().count;

    // Count active plans (modified in last 14 days)
    const twoWeeksAgo = new Date();
    twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);
    const activePlansSnap = await db.collectionGroup("rehabPlans")
      .where("lastModifiedDate", ">=", admin.firestore.Timestamp.fromDate(twoWeeksAgo))
      .count()
      .get();
    const activePlansCount = activePlansSnap.data().count;

    await db.collection("analytics").doc("dailyAggregates").collection("days").doc(today).set({
      date: today,
      totalUsers,
      totalPlans,
      totalWorkoutSessions,
      activePlansCount,
      generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`Daily metrics aggregated for ${today}: ${totalUsers} users, ${totalPlans} plans, ${totalWorkoutSessions} sessions`);
  } catch (error) {
    console.error("Error aggregating daily metrics:", error);
  }
});

// ---------------------------------------------------------------------------
// Nightly Email Report — AI-written summary of app health
// Runs at 07:00 local time, collects metrics, calls Claude for summary,
// sends via SendGrid.
// ---------------------------------------------------------------------------
async function collectMetrics(): Promise<string> {
  const db = admin.firestore();
  const today = new Date().toISOString().split("T")[0];
  const yesterday = new Date(Date.now() - 86_400_000).toISOString().split("T")[0];

  const lines: string[] = [`Report date: ${today}`, ""];

  // --- Firestore daily aggregates (from aggregateDailyMetrics) ---
  try {
    const todayDoc = await db
      .collection("analytics").doc("dailyAggregates").collection("days").doc(today)
      .get();
    const yesterdayDoc = await db
      .collection("analytics").doc("dailyAggregates").collection("days").doc(yesterday)
      .get();

    if (todayDoc.exists) {
      const d = todayDoc.data()!;
      lines.push("## Firestore Aggregates (today)");
      lines.push(`- Total users: ${d.totalUsers}`);
      lines.push(`- Total rehab plans: ${d.totalPlans}`);
      lines.push(`- Total workout sessions: ${d.totalWorkoutSessions}`);
      lines.push(`- Active plans (last 14d): ${d.activePlansCount}`);
    } else {
      lines.push("## Firestore Aggregates (today): no data yet");
    }

    if (yesterdayDoc.exists) {
      const d = yesterdayDoc.data()!;
      lines.push("\n## Firestore Aggregates (yesterday)");
      lines.push(`- Total users: ${d.totalUsers}`);
      lines.push(`- Total rehab plans: ${d.totalPlans}`);
      lines.push(`- Total workout sessions: ${d.totalWorkoutSessions}`);
      lines.push(`- Active plans (last 14d): ${d.activePlansCount}`);
    }
  } catch (err) {
    lines.push(`Firestore aggregate error: ${err}`);
  }

  // --- Crash logs (last 24h) ---
  const oneDayAgo = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 86_400_000));

  try {
    const crashSnap = await db
      .collectionGroup("crashLogs")
      .where("timestamp", ">=", oneDayAgo)
      .count()
      .get();
    lines.push(`\n## Crash Logs (last 24h): ${crashSnap.data().count}`);
  } catch (err) {
    lines.push(`\nCrash log query error: ${err}`);
  }

  // --- Session logs (last 24h) ---
  try {
    const sessionLogSnap = await db
      .collectionGroup("sessionLogs")
      .where("uploadedAt", ">=", oneDayAgo)
      .count()
      .get();
    lines.push(`## Session Logs uploaded (last 24h): ${sessionLogSnap.data().count}`);
  } catch (err) {
    lines.push(`Session log query error: ${err}`);
  }

  // --- Missing exercise images reported ---
  try {
    const missingSnap = await db.collection("missingExerciseImages").count().get();
    lines.push(`\n## Missing Exercise Images reported: ${missingSnap.data().count}`);
  } catch (err) {
    lines.push(`Missing images query error: ${err}`);
  }

  return lines.join("\n");
}

function markdownToHtml(md: string): string {
  // Simple markdown → HTML for email
  return md
    .replace(/^## (.+)$/gm, "<h2 style=\"color:#6B7F6B;margin:16px 0 8px;font-size:18px;\">$1</h2>")
    .replace(/^- (.+)$/gm, "<li style=\"margin:4px 0;\">$1</li>")
    .replace(/(<li[^>]*>.*<\/li>\n?)+/g, (match) => `<ul style="padding-left:20px;">${match}</ul>`)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/\n\n/g, "<br><br>")
    .replace(/\n/g, "<br>");
}

export const sendNightlyReport = onSchedule(
  {
    schedule: "every day 07:00",
    timeZone: "Asia/Jerusalem",
    secrets: ["ANTHROPIC_API_KEY", "SENDGRID_API_KEY"],
  },
  async () => {
    // --- 1. Collect metrics ---
    const metricsText = await collectMetrics();
    console.log("Collected metrics:\n", metricsText);

    // --- 2. Call Claude for human-readable summary ---
    const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
    if (!anthropicApiKey) {
      console.error("ANTHROPIC_API_KEY not configured");
      return;
    }

    const systemPrompt = SYSTEM_PROMPTS.nightly_report;
    const config = MODEL_CONFIG.nightly_report;

    let summary: string;
    try {
      const response = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": anthropicApiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          model: config.model,
          max_tokens: config.max_tokens,
          temperature: config.temperature,
          system: systemPrompt,
          messages: [{ role: "user", content: metricsText }],
        }),
      });

      const data = await response.json() as {
        content?: { type: string; text: string }[];
      };
      summary = data.content?.[0]?.text || "Failed to generate summary";
    } catch (err) {
      console.error("Claude API error:", err);
      summary = `Error generating AI summary. Raw metrics:\n\n${metricsText}`;
    }

    // --- 3. Send email via SendGrid ---
    const sendgridKey = process.env.SENDGRID_API_KEY;
    const recipientEmail = process.env.REPORT_RECIPIENT_EMAIL || "noyfisher2003@gmail.com";

    if (!sendgridKey) {
      console.error("SENDGRID_API_KEY not configured — logging report to console instead");
      console.log("=== NIGHTLY REPORT ===\n", summary);
      return;
    }

    sgMail.setApiKey(sendgridKey);

    const htmlBody = `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"></head>
<body style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;max-width:600px;margin:0 auto;padding:20px;color:#3D3D3D;background:#F5F2EC;">
  <div style="background:#FFFFFF;border-radius:12px;padding:24px;box-shadow:0 1px 3px rgba(0,0,0,0.1);">
    <h1 style="color:#6B7F6B;font-size:22px;margin:0 0 4px;">PT Helper Daily Report</h1>
    <p style="color:#9B8F80;font-size:14px;margin:0 0 20px;">${new Date().toISOString().split("T")[0]}</p>
    <hr style="border:none;border-top:1px solid #E8E3DA;margin:16px 0;">
    ${markdownToHtml(summary)}
    <hr style="border:none;border-top:1px solid #E8E3DA;margin:16px 0;">
    <p style="color:#9B8F80;font-size:12px;text-align:center;margin:0;">
      Generated by PT Helper Nightly Report &bull; Powered by Claude AI
    </p>
  </div>
</body>
</html>`;

    const reportDate = new Date().toISOString().split("T")[0];

    try {
      await sgMail.send({
        to: recipientEmail,
        from: { email: "noyfisher2003@gmail.com", name: "PT Helper Reports" },
        subject: `PT Helper Daily Report — ${reportDate}`,
        html: htmlBody,
      });
      console.log(`Nightly report sent to ${recipientEmail}`);
    } catch (err) {
      console.error("SendGrid error:", err);
    }
  }
);

// ---------------------------------------------------------------------------
// Agent-Powered Recovery Insights
// Uses Claude Managed Agents for multi-step analysis.
// Falls back to single-call claudeProxy path on failure.
// ---------------------------------------------------------------------------
export const agentInsights = functions
  .runWith({
    timeoutSeconds: 300,
    memory: "512MB",
    secrets: ["ANTHROPIC_API_KEY", "MANAGED_AGENT_ID", "MANAGED_ENVIRONMENT_ID"],
  })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("agentInsights");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Authenticate
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // 2. Rate limit
    if (isRateLimited(uid)) {
      res.status(429).json({ error: "Rate limit exceeded. Please wait and try again." });
      return;
    }

    // 3. Fetch user data from Firestore
    let data;
    try {
      data = await fetchRecoveryInsightsData(uid);
    } catch (err) {
      logError(ctx, err, { stage: "fetch_recovery_data" });
      res.status(500).json({ error: "Failed to fetch recovery data" });
      return;
    }

    ctx.metadata.sessionCount = data.sessionCount;

    if (data.sessionCount < MINIMUM_SESSION_COUNT) {
      res.status(400).json({
        error: `Need at least ${MINIMUM_SESSION_COUNT} sessions in the past 14 days`,
      });
      return;
    }

    // 4. Try managed agent
    let resultJson: string;
    try {
      const result = await runRecoveryInsightsAgent(data.userMessage);

      // Server-side validation before returning
      if (!validateInsightResult(result)) {
        throw new Error("Agent returned invalid insight structure");
      }

      resultJson = JSON.stringify(result);
      ctx.metadata.path = "agent";
    } catch (agentErr) {
      // 5. Fallback to single-call Messages API with Haiku
      logWarn(ctx, "agent_fallback", { stage: "managed_agent", fallbackReason: agentErr instanceof Error ? agentErr.message : String(agentErr) });
      ctx.metadata.path = "fallback";

      const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
      if (!anthropicApiKey) {
        res.status(500).json({ error: "Server configuration error" });
        return;
      }

      try {
        const systemPrompt = SYSTEM_PROMPTS.recovery_insights;
        const config = MODEL_CONFIG.recovery_insights;

        const fallbackResponse = await fetch("https://api.anthropic.com/v1/messages", {
          method: "POST",
          headers: {
            "x-api-key": anthropicApiKey,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
          },
          body: JSON.stringify({
            model: config.model,
            max_tokens: config.max_tokens,
            temperature: config.temperature,
            system: [
              { type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } },
            ],
            messages: [{ role: "user", content: data.userMessage }],
          }),
        });

        const fallbackData = await fallbackResponse.json();

        if (!fallbackResponse.ok) {
          res.status(fallbackResponse.status).json(fallbackData);
          return;
        }

        // Return fallback response directly (already in Anthropic format)
        res.status(200).json(fallbackData);
        return;
      } catch (fallbackErr) {
        logError(ctx, fallbackErr, { stage: "fallback_call" });
        res.status(502).json({ error: "Failed to generate recovery insights" });
        return;
      }
    }

    // 6. Wrap agent result in Anthropic response format for iOS compatibility
    res.status(200).json({
      content: [{ type: "text", text: resultJson }],
      stop_reason: "end_turn",
    });
  });

// ---------------------------------------------------------------------------
// On-demand exercise image generation
// ---------------------------------------------------------------------------
export const generateExerciseImage = functions
  .runWith({
    timeoutSeconds: 540,
    memory: "512MB",
    secrets: ["BFL_API_KEY", "GEMINI_API_KEY"],
  })
  .https.onRequest(async (req, res) => {
    const ctx = newRequestContext("generateExerciseImage");
    res.on("finish", () => logCompleted(ctx, res.statusCode));

    if (req.method !== "POST") {
      res.status(405).json({ error: "Method not allowed" });
      return;
    }

    // 1. Authenticate
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing or invalid Authorization header" });
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      ctx.uid = uid;
    } catch {
      res.status(401).json({ error: "Invalid Firebase ID token" });
      return;
    }

    // 2. Handle request
    try {
      const result = await handleGenerateExerciseImage({
        body: req.body,
        uid,
      });

      ctx.metadata.resultStatus = result.status;
      ctx.metadata.matchType = result.matchType;

      const statusCode = result.status === "rate_limited" ? 429
        : result.status === "generation_failed" || result.status === "qa_failed" ? 502
        : 200;

      res.status(statusCode).json(result);
    } catch (err) {
      logError(ctx, err, { stage: "image_generation" });
      res.status(500).json({ status: "generation_failed", message: "Internal error", retryable: true });
    }
  });
