#!/usr/bin/env python3
"""
Tier 3 PR E followup — capture real Claude responses to replace the
hand-authored goldens in `cases.json`.

Why: the v1 cases ship with dev-authored golden responses that match the
AIAnalysisResponse shape. They detect MY validator changes (good), but
they're not real Claude output, so they can't detect Claude model drift.
Once you run this script, the goldens reflect what the production model
actually returns at the pinned model version.

Pipeline
  1. Read the cases.json file.
  2. For each case:
     a. Build the same user message that `InjuryAnalyzer.buildUserMessage`
        would build for that synthetic patient.
     b. Call Anthropic with the production system prompt for `analysis`.
     c. Replace the case's `goldenAnalysisResponse` field with the parsed
        Claude output.
     d. (Optional) call again with `analysis_verify` system prompt to
        capture the verify response.
  3. Write the updated cases.json.

What it deliberately does NOT change
  - patient profiles (those are the test fixtures)
  - expectedOutcomes (those are the regression assertions)
  - cases.json's `modelVersion` field (gets updated separately if you
    intentionally bump the pinned model)

Usage
  ANTHROPIC_API_KEY=sk-... python3 scripts/capture_kg_regression_goldens.py
  ANTHROPIC_API_KEY=sk-... python3 scripts/capture_kg_regression_goldens.py --only-case 02-cardiac-emergency
  python3 scripts/capture_kg_regression_goldens.py --dry-run

Cost: ~$0.10-0.30 for the full 30-case set at Haiku pricing.

Important: the system prompts here are mirrors of what's in
`functions/src/index.ts`. If you bump prompts on the server, also bump
them here OR re-capture the goldens against the new server-side prompts.
The runner's model-version pin guard catches model changes; there's no
parallel guard for prompt drift, so be deliberate.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

try:
    from anthropic import Anthropic
except ImportError:
    print("ERROR: anthropic SDK not installed. Run: pip install anthropic", file=sys.stderr)
    sys.exit(1)


REPO_ROOT = Path(__file__).resolve().parent.parent
CASES_PATH = REPO_ROOT / "ios/PT-Helper/PT-Helper/PT-HelperTests/GroundTruth/cases.json"
# Fallback (the path above is wrong — fix to test target's real location):
ALT_CASES_PATH = REPO_ROOT / "ios/PT-Helper/PT-HelperTests/GroundTruth/cases.json"


# ---------------------------------------------------------------------------
# System prompts — mirrored from functions/src/index.ts
# ---------------------------------------------------------------------------
# Keep these in sync with the server. The runner pins MODEL via
# cases.json.modelVersion; prompt drift is tracked manually.

ANALYSIS_PROMPT = """You are a friendly health guide helping everyday people understand their pain. Write like you're explaining to a friend — no medical jargon. This is educational only, not a diagnosis.

APPROACH:
Step 1 — ORGANIZE: List symptoms, locations, characteristics, aggravating/relieving factors, history.
Step 2 — DIFFERENTIAL: Generate candidate conditions ranked by clinical fit.

RULES:
- Return top 5 possible conditions with confidence 0-100
- "conditionName": medical name (e.g. "Patellofemoral Pain Syndrome")
- "commonName": plain English (e.g. "Runner's Knee")
- "explanation": 1-2 SHORT sentences
- "whatItMeans": 1-2 SHORT sentences in plain terms
- "howToManage": 1 sentence max
- "nextSteps": 2-3 short concrete steps
- "overallSummary": 1-2 sentences directly to the person
- Flag red flags: cauda equina, fractures, infections, spinal cord, night pain, sudden weakness, chest pain
- For redFlagMessage: clear urgent message if isRedFlag true, "" otherwise
- disclaimerText must be: "This is not a medical diagnosis — it's a starting point to help you understand what might be going on. If your pain is severe, getting worse, or not improving, please see a doctor or visit an urgent care clinic."

RESPONSE FORMAT: Respond with ONLY a valid JSON object:
{"conditions":[{"conditionName":"...","commonName":"...","confidence":0,"explanation":"...","whatItMeans":"...","howToManage":"...","isRedFlag":false,"redFlagMessage":"","nextSteps":["..."]}],"overallSummary":"...","disclaimerText":"..."}"""


def cases_path() -> Path:
    if ALT_CASES_PATH.exists():
        return ALT_CASES_PATH
    if CASES_PATH.exists():
        return CASES_PATH
    print(f"ERROR: cases.json not found. Tried {ALT_CASES_PATH} and {CASES_PATH}", file=sys.stderr)
    sys.exit(2)


def build_user_message(patient: dict) -> str:
    """Build the user message Claude sees. Mirrors the shape that
    InjuryAnalyzer.buildUserMessage produces — kept simple here since
    the test cases use a smaller patient schema."""
    sex = patient.get("sex", "unknown")
    age = patient.get("age", "unknown")
    region = patient.get("primaryRegion", "unknown").replace("_", " ")
    intensity = patient.get("painIntensity", 0)
    onset = patient.get("painOnset", "unknown")
    aggravating = ", ".join(patient.get("aggravatingFactors", []))
    relieving = ", ".join(patient.get("relievingFactors", []))
    conditions = ", ".join(patient.get("medicalConditions", [])) or "None"
    medications = ", ".join(patient.get("medications", [])) or "None"

    return (
        f"PATIENT PROFILE:\n"
        f"- Age: {age}\n"
        f"- Sex: {sex}\n"
        f"- Activity Level: Moderate\n"
        f"- Medical Conditions: {conditions}\n"
        f"- Medications: {medications}\n\n"
        f"PAIN ASSESSMENT:\n"
        f"- Region: {region.title()}\n"
        f"- Intensity: {intensity}/10\n"
        f"- Onset: {onset}\n"
        f"- Aggravating: {aggravating or 'None'}\n"
        f"- Relieving: {relieving or 'None'}\n"
    )


def call_claude(client: Anthropic, system_prompt: str, user_message: str, model: str) -> dict:
    """Single Claude call — returns the parsed JSON object."""
    response = client.messages.create(
        model=model,
        max_tokens=4096,
        temperature=0.2,
        system=system_prompt,
        messages=[{"role": "user", "content": user_message}],
    )
    text = "".join(b.text for b in response.content if hasattr(b, "text"))
    # Strip markdown fences just in case (Haiku usually obeys but defensive).
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[1] if "\n" in cleaned else cleaned[3:]
    if cleaned.endswith("```"):
        cleaned = cleaned.rsplit("```", 1)[0]
    cleaned = cleaned.strip()
    return json.loads(cleaned)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cases-file", type=Path, default=None)
    parser.add_argument("--only-case", type=str, default=None,
                        help="Only re-capture this specific case id")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be called without hitting the API")
    args = parser.parse_args()

    path = args.cases_file or cases_path()
    cases_doc = json.loads(path.read_text())
    pinned_model = cases_doc["modelVersion"]
    cases = cases_doc.get("cases", [])
    print(f"Loaded {len(cases)} cases from {path}")
    print(f"Pinned model: {pinned_model}")

    if args.only_case:
        cases = [c for c in cases if c["id"] == args.only_case]
        if not cases:
            print(f"ERROR: case '{args.only_case}' not found", file=sys.stderr)
            return 2
        print(f"Filtering to single case: {args.only_case}")

    if args.dry_run:
        print("\nDry run — would call Claude for these cases:")
        for c in cases:
            print(f"  {c['id']}: {c['description'][:80]}")
        return 0

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print("ERROR: set ANTHROPIC_API_KEY env var", file=sys.stderr)
        return 1
    client = Anthropic(api_key=api_key)

    updated = 0
    for case in cases:
        cid = case["id"]
        print(f"\nCapturing {cid}...")
        try:
            user_msg = build_user_message(case["patient"])
            golden = call_claude(client, ANALYSIS_PROMPT, user_msg, pinned_model)
            # Replace the case's goldenAnalysisResponse with the real output.
            case["goldenAnalysisResponse"] = golden
            # If the case had a goldenVerifyResponse, drop it — re-capture
            # would need the verify prompt + the primary response in context.
            # Out of scope for v1; runner falls back to using the analysis
            # response for both calls when verify is null.
            case["goldenVerifyResponse"] = None
            # If the case used rawGoldenResponse (preamble test), preserve
            # the dev-authored value — we WANT the malformed shape there.
            if case.get("rawGoldenResponse"):
                print(f"  (skipping {cid}: has rawGoldenResponse, kept as-is)")
                continue
            updated += 1
            n_conditions = len(golden.get("conditions", []))
            print(f"  Got {n_conditions} conditions")
        except Exception as e:
            print(f"  ERROR on {cid}: {e}", file=sys.stderr)

    # Update the file in-place by replacing the cases array.
    if args.only_case:
        # Merge back into the full doc.
        full_doc = json.loads(path.read_text())
        for i, c in enumerate(full_doc["cases"]):
            if c["id"] == args.only_case:
                full_doc["cases"][i] = cases[0]
                break
        cases_doc = full_doc
    else:
        cases_doc["cases"] = cases

    path.write_text(json.dumps(cases_doc, indent=2))
    print(f"\nUpdated {updated} cases in {path}")
    print("Run `xcodebuild test -only-testing:PT-HelperTests/ValidationRegressionRunner`")
    print("to verify the new goldens still satisfy expectedOutcomes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
