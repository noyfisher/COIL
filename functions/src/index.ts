import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

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
};

// Server-side model configuration (NOT client-controlled)
const MODEL_CONFIG: Record<string, { model: string; max_tokens: number; temperature?: number }> = {
  analysis: { model: "claude-haiku-4-5-20251001", max_tokens: 4096, temperature: 0.2 },
  analysis_verify: { model: "claude-haiku-4-5-20251001", max_tokens: 4096, temperature: 0.2 },
  rehab_plan: { model: "claude-haiku-4-5-20251001", max_tokens: 4096 },
  exercise_substitute: { model: "claude-haiku-4-5-20251001", max_tokens: 2048, temperature: 0.3 },
  recovery_insights: { model: "claude-haiku-4-5-20251001", max_tokens: 2048, temperature: 0.3 },
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
    const totalMessageLength = body.messages.reduce((sum, m) => sum + (m.content?.length || 0), 0);
    if (totalMessageLength > 10000) {
      res.status(400).json({ error: "Message content too long" });
      return;
    }

    // -----------------------------------------------------------------------
    // 4. Get Anthropic API key from environment
    // -----------------------------------------------------------------------
    const anthropicApiKey = process.env.ANTHROPIC_API_KEY;
    if (!anthropicApiKey) {
      console.error("ANTHROPIC_API_KEY not configured in environment");
      res.status(500).json({ error: "Server configuration error" });
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
          system: systemPrompt,
          messages: body.messages,
        }),
      });

      const responseData = await anthropicResponse.json();

      if (!anthropicResponse.ok) {
        res.status(anthropicResponse.status).json(responseData);
        return;
      }

      res.status(200).json(responseData);
    } catch (error) {
      console.error("Error calling Anthropic API:", error);
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
      console.error("OPENAI_API_KEY not configured in environment");
      res.status(500).json({ error: "Server configuration error" });
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
        console.error(`OpenAI API error (${openaiResponse.status}):`, errorData);
        res.status(502).json({ error: "Failed to reach verification service" });
        return;
      }

      const openaiData = await openaiResponse.json() as {
        choices?: { message?: { content?: string } }[];
      };
      const content = openaiData.choices?.[0]?.message?.content;

      if (!content) {
        res.status(502).json({ error: "Empty response from verification service" });
        return;
      }

      // Parse the GPT response and forward to client
      const parsed = JSON.parse(content);
      res.status(200).json(parsed);
    } catch (error) {
      console.error("Error calling OpenAI API:", error);
      res.status(502).json({ error: "Failed to reach verification service" });
    }
  });
