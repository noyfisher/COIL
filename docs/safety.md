# Safety Documentation

PT Helper provides wellness guidance, not medical diagnosis. This document describes the safety systems that protect users from harmful AI output.

## Disclaimer

Every analysis includes this disclaimer:

> This is not a medical diagnosis — it's a starting point to help you understand what might be going on. If your pain is severe, getting worse, or not improving, please see a doctor or visit an urgent care clinic.

Users must acknowledge a disclaimer during onboarding before using the app.

## Safety Pipeline Overview

The app validates AI responses through multi-step pipelines before displaying results.

### Analysis Validation (6 steps)

**Step 1: Content Validation** (`AnalysisContentValidator`)
- Verifies 1-3 conditions returned (trims excess)
- Validates confidence scores are 0-100
- Flags confidence >= 95 as unreliable (even doctors are ~70-80% accurate)
- Checks red flag conditions have corresponding messages
- Detects duplicate conditions
- Verifies summary is non-empty

**Step 2: Symptom Red Flag Detection** (`MedicalRedFlagDetector.check`)
- Scans user-reported symptoms for emergency patterns:
  - Chest pain + shortness of breath (cardiac)
  - Sudden one-sided weakness/numbness (stroke)
  - Severe headache + stiff neck + fever (meningitis)
  - Bladder/bowel loss + back pain + leg weakness (cauda equina)
  - Saddle numbness + back pain (cauda equina)
  - Calf pain + swelling + redness (DVT)
  - Deformity + inability to bear weight (fracture)
  - Night pain + weight loss (serious pathology)
- Pain >= 9/10 with sudden onset triggers urgent warning
- Pain >= 9/10 triggers caution warning

**Step 3: Condition Red Flag Detection** (`MedicalRedFlagDetector.checkConditions`)
- Checks AI-returned condition names against dangerous self-management keywords:
  - fracture, dislocation, cauda equina, spinal cord, infection, septic, tumor, cancer, DVT, embolism, compartment syndrome, avascular necrosis, osteomyelitis
- If AI didn't flag these as red flags, the pipeline adds urgent warnings

**Step 4: Anatomical Relevance Check** (`AnatomicalRelevanceChecker`)
- Maps each body region to expected conditions (e.g., knee -> patellofemoral, meniscus, ACL)
- Flags conditions that don't match the assessed body region
- Warns user about possible referred pain patterns

**Step 5: Confidence Calibration** (`ConfidenceCalibrator`)
- Caps all confidence scores at 85% maximum
- Maps to human-friendly labels: Strong Match (65+), Possible Match (35-64), Less Likely (<35)

**Step 6: Deduplication**
- Removes duplicate conditions by name

### Rehab Plan Validation (9 steps)

**Step 1: Exercise Contraindication Check** (`ExerciseContraindicationChecker`)
- Cross-references exercises against diagnosed conditions:
  - Herniated disc: no deadlifts, sit-ups, crunches, toe touches
  - ACL injury: no deep squats, plyometrics, cutting movements
  - Rotator cuff: no overhead press, behind-neck movements
  - Impingement: no overhead press, lateral raises above shoulder
  - Fracture: no impact, jumping, running, heavy loading
  - Osteoporosis: no high impact, jumping, heavy deadlifts
  - Spinal stenosis: no extension, back bends
  - Sciatica: no sit-ups, crunches, toe touches
  - Plantar fasciitis: no jumping, running
  - Carpal tunnel / tennis elbow / golfer's elbow: specific restrictions

**Step 1.5: Knowledge Graph Validation** (`KnowledgeGraphValidator` via `KnowledgeGraphService`)
- Deterministic exercise-condition verification
- Classifies exercises as: verified, unverified, or contraindicated
- Adds warnings for contraindicated exercises

**Step 2: Parameter Range Validation**
- Sets: must be 1-10
- Rest period: must be 0-300 seconds

**Step 3: Exercise Count Check**
- Warns if no exercises generated (triggers fallback)

**Step 4: Plan Duration Check**
- Flags plans < 1 week or > 24 weeks as unusual

**Step 5: Age-Based Safety**
- Users 65+ get warnings about advanced exercises

**Step 6: Medical Condition Safety**
- Osteoporosis: flags impact exercises
- Heart disease: adds heart rate monitoring warning

**Step 7: Medication-Aware Safety**
- Blood thinners: warns about fall risk and bruising for balance/impact exercises
- Corticosteroids: warns about weakened tendons, recommends lower resistance
- Beta blockers: recommends RPE over heart rate for intensity

**Step 8: Post-Surgical Restriction Check**
- Flags active surgical recovery (status = "Still recovering" or "Have restrictions")
- Names the specific surgeries for user awareness

### Form Feedback Validation

**`FormFeedbackValidationPipeline`**
- Validates AI-generated exercise form feedback for safety
- Ensures form corrections don't introduce injury risk

**`BiomechanicalRuleEngine`**
- Exercise-specific form rules (knee valgus detection, spinal alignment, etc.)
- Per-rep symmetry analysis via `PoseAnalysisEngine`
- Validates joint angles are within safe ranges

### Wellness Analysis Validation
- Same two-call pipeline as injury analysis (`wellness_analysis` + `wellness_verify`)
- Validation follows analysis pipeline steps adapted for wellness context

## Input Sanitization

User text is sanitized before being sent to the AI (`InputSanitizer`):

- **Length limit**: 500 characters per field
- **Prompt injection patterns stripped**:
  - "ignore previous instructions", "disregard all", "forget your instructions"
  - "override your instructions", "you are now", "new instructions:"
  - Chat template markers (`[INST]`, `<|im_start|>`, etc.)
- **XML delimiters**: User content is wrapped in `<user_label>` tags to help the AI distinguish user data from instructions

## Server-Side Protections

The Firebase Cloud Function adds additional security:

- **Authentication required**: Valid Firebase ID token mandatory
- **Rate limiting**: 20 requests/minute per user (in-memory sliding window)
- **Request type whitelist**: Only configured request types in `SYSTEM_PROMPTS` are accepted (currently 10: `analysis`, `analysis_verify`, `rehab_plan`, `exercise_substitute`, `recovery_insights`, `form_analysis`, `wellness_analysis`, `wellness_verify`, `wellness_plan`, `nightly_report`)
- **Message length cap**: 10,000 characters total across all messages
- **Server-side prompts**: System prompts are NOT client-controlled — they live in the Cloud Function
- **Server-side model config**: Model selection and token limits are server-controlled

## Health History Relevance

The `HistoryRelevanceFilter` ensures the AI receives properly contextualized health history:

- **Directly relevant**: Same body region or active recovery/restrictions (full detail in prompt)
- **Possibly relevant**: Connected via kinetic chain (moderate detail)
- **Background only**: Unrelated or old/recovered (condensed to one line)

This prevents the AI from being overwhelmed by irrelevant history while ensuring critical context (like an active knee surgery recovery when assessing knee pain) is prominent.

## Red Flag Auto-Upload

When red flags are detected, the session log is automatically uploaded to Firestore for monitoring and review.

## What This System Does NOT Do

- It does not replace medical diagnosis
- It does not guarantee the AI will always produce safe output
- It does not prevent all possible harmful recommendations
- It validates exercise form feedback but does not replace professional form coaching

Users should always consult healthcare providers for serious or worsening conditions.
