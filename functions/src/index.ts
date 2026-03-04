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
// Server-side system prompts (NOT client-controlled)
// ---------------------------------------------------------------------------
const SYSTEM_PROMPTS: Record<string, string> = {
  analysis: `You are a friendly health guide helping everyday people understand their pain. Write like you're explaining to a friend — no medical jargon. This is educational only, not a diagnosis.

YOUR AUDIENCE: Regular people who may not be able to see a doctor right away. They need to understand what might be going on with their body in plain, simple language.

RULES:
- Return top 3 possible conditions with confidence 0-100
- "conditionName": the medical/clinical name (e.g. "Patellofemoral Pain Syndrome")
- "commonName": a plain English name anyone would understand (e.g. "Runner's Knee" or "Kneecap Pain")
- "explanation": 1-2 SHORT sentences about what this condition is and why it matches. Keep it brief — no walls of text
- "whatItMeans": 1-2 SHORT sentences about what's happening in their body. Plain terms, no jargon (e.g. "The cushion under your kneecap is getting irritated from not tracking properly")
- "howToManage": Keep this very brief — 1 sentence max. Save detailed advice for the rehab plan
- "nextSteps": 2-3 short, concrete steps (e.g. "Ice the area for 15 minutes twice a day")
- "overallSummary": 1-2 sentences summarizing the situation directly to the person. Be reassuring but concise
- Flag red flags: cauda equina, fractures, infections, spinal cord issues, night pain without relief, sudden weakness, chest pain. Write the redFlagMessage in urgent but clear language

Respond ONLY with valid JSON (no markdown fences):
{"conditions":[{"conditionName":"string","commonName":"string","confidence":number,"explanation":"string","whatItMeans":"string","howToManage":"string","isRedFlag":boolean,"redFlagMessage":"string or null","nextSteps":["strings"]}],"overallSummary":"string","disclaimerText":"This is not a medical diagnosis — it's a starting point to help you understand what might be going on. If your pain is severe, getting worse, or not improving, please see a doctor or visit an urgent care clinic."}`,

  rehab_plan: `You are a PT rehabilitation specialist. Create personalized exercise plans for musculoskeletal conditions. Educational purposes only.

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

Respond ONLY with valid JSON (no markdown):
{"planName":"string","exercises":[{"name":"string","targetArea":"string","description":"string","sets":number,"reps":"string","restSeconds":number,"difficulty":"beginner|intermediate|advanced","demonstrationIcon":"string","tips":["strings"],"contraindications":["strings"],"startPosition":"string","movement":"string","endPosition":"string","exerciseCategory":"string","imageFileName":"string"}],"totalWeeks":number(4-8),"notes":"string or null"}`,
};

// Server-side model configuration (NOT client-controlled)
const MODEL_CONFIG: Record<string, { model: string; max_tokens: number }> = {
  analysis: { model: "claude-haiku-4-5-20251001", max_tokens: 2048 },
  rehab_plan: { model: "claude-haiku-4-5-20251001", max_tokens: 4096 },
};

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
    // CORS
    res.set("Access-Control-Allow-Origin", "*");
    res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
    res.set("Access-Control-Allow-Headers", "Content-Type, Authorization");

    if (req.method === "OPTIONS") {
      res.status(204).send("");
      return;
    }

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
