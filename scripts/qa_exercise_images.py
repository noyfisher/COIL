#!/usr/bin/env python3
"""
QA exercise illustration images using Gemini 2.5 Flash vision.

Runs automated quality checks on generated exercise images to catch
critical defects (extra limbs, wrong orientation, headshots, etc.)
before images go into the app.

Usage:
    python qa_exercise_images.py --api-key YOUR_GEMINI_KEY
    python qa_exercise_images.py --api-key YOUR_KEY --filter-position prone --verbose
    python qa_exercise_images.py --api-key YOUR_KEY --filter-name quad-sets,bird-dog
    python qa_exercise_images.py --api-key YOUR_KEY --recheck

Prerequisites:
    pip install google-genai pydantic Pillow
"""

import argparse
import asyncio
import json
import sys
import time
from pathlib import Path

try:
    from google import genai
except ImportError:
    print("ERROR: google-genai package not installed.")
    print("Run: pip install google-genai")
    sys.exit(1)

try:
    from pydantic import BaseModel, Field
except ImportError:
    print("ERROR: pydantic package not installed.")
    print("Run: pip install pydantic")
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow package not installed.")
    print("Run: pip install Pillow")
    sys.exit(1)

# Import shared utilities from the generation script
from generate_exercise_images import CHARACTER_DESC, load_exercise_list

# ---------- Constants ----------

SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output"
DEFAULT_REPORT_PATH = OUTPUT_DIR / "qa_report.json"
GEMINI_MODEL = "gemini-2.5-flash"
MAX_CONCURRENT = 10
RATE_LIMIT_DELAY = 0.5  # seconds between API calls


# ---------- Body position descriptions for prompt ----------

BODY_POSITION_DESCRIPTIONS = {
    "supine": "lying on back, face up, back on the ground",
    "prone": "lying on stomach, face down, chest on the ground",
    "quadruped": "on all fours, hands and knees on the ground",
    "standing": "upright on feet",
    "seated": "sitting down",
    "side_lying": "lying on one side",
    "kneeling": "on knees",
    "foam_roller": "on the ground with a foam roller",
    "wall_sit": "back against a wall, knees bent at 90 degrees",
}


# ---------- Pydantic schemas for structured output ----------

class CheckResult(BaseModel):
    """Result of a single QA check."""
    observation: str = Field(
        description="Brief factual description of what was observed in the image for this check"
    )
    passed: bool = Field(
        description="Whether the image passes this check"
    )


class QAResult(BaseModel):
    """Complete QA result for a single exercise image."""
    exercise_name: str = Field(description="Name of the exercise")
    filename: str = Field(description="Image filename")

    # Phase 1: Basic Quality Gates
    anatomy: CheckResult = Field(
        description="ANATOMY: Does the figure have exactly 2 arms and 2 legs?"
    )
    subject: CheckResult = Field(
        description="SUBJECT: Is there a single human male figure?"
    )
    full_body: CheckResult = Field(
        description="FULL_BODY: Is the full body visible from head to toe?"
    )
    clothing: CheckResult = Field(
        description="CLOTHING: Is the figure wearing a t-shirt and shorts?"
    )
    background: CheckResult = Field(
        description="BACKGROUND: Is the background clean and plain?"
    )
    no_text: CheckResult = Field(
        description="NO_TEXT: Is the image free of text, labels, watermarks?"
    )
    art_style: CheckResult = Field(
        description="ART_STYLE: Is the style photo-realistic or clean illustration?"
    )

    # Phase 2: Exercise-Specific
    body_orientation: CheckResult = Field(
        description="BODY_ORIENTATION: Does the body position match the expected position?"
    )
    pose_accuracy: CheckResult = Field(
        description="POSE_ACCURACY: Does the pose match the expected exercise description?"
    )
    pose_score: int = Field(
        ge=1, le=5,
        description="Pose accuracy score from 1 (completely wrong) to 5 (perfect match)"
    )

    # Aggregate (recomputed server-side)
    overall_pass: bool = Field(
        description="True only if ALL checks passed AND pose_score > 2"
    )
    critical_failures: list[str] = Field(
        description="List of check names that failed"
    )


# ---------- Prompt template ----------

QA_PROMPT_TEMPLATE = """You are a quality assurance inspector for physical therapy exercise illustrations.

Analyze this image against the following specifications and checks.

## Expected Character Appearance
{character_desc}

## Expected Exercise
- Exercise Name: {exercise_name}
- Expected Body Position: {body_position} ({body_position_description})
- Expected Pose: {pose_description}

## Instructions
For each check below, first describe what you OBSERVE in the image, then determine if it passes.
Be strict on Phase 1 checks. Be reasonable on Phase 2 — minor pose variations are acceptable.

### Phase 1: Basic Quality Gates
1. **ANATOMY**: Count the limbs. The figure must have exactly 2 arms and 2 legs. Extra fingers are OK, but extra or missing limbs fail.
2. **SUBJECT**: There must be exactly one human male figure. Fail if: multiple people, female figure, animal, object-only, medical diagram, skeleton/anatomy chart.
3. **FULL_BODY**: The entire body must be visible from head to toe. Fail if: head cut off, feet cut off, only upper body shown, portrait/headshot only.
4. **CLOTHING**: The figure must be wearing a t-shirt (or athletic shirt) and shorts. Fail if: shirtless, suit/formal wear, long pants, no clothing visible.
5. **BACKGROUND**: The background must be clean, plain, and light-colored (white or near-white). Fail if: complex scene, gym equipment as background, outdoor scene, dark background, bed/furniture.
6. **NO_TEXT**: The image must be free of readable text, labels, watermarks, or annotations overlaid on the image. Fail if: readable words or sentences, exercise labels with arrows, watermark overlay, large visible logos. Small brand-style logos on clothing or shoes (Nike swoosh, Adidas stripes, etc.) are OK and should PASS — these are incidental AI artifacts, not meaningful text.
7. **ART_STYLE**: The style must be photo-realistic or clean digital illustration. Fail if: cartoon/comic style, anime, abstract art, stick figures, overly stylized/fantasy.

### Phase 2: Exercise-Specific Validation
8. **BODY_ORIENTATION**: The figure's body position must match "{body_position}":
   - supine = lying on back, face up
   - prone = lying on stomach, face down
   - quadruped = on all fours (hands and knees)
   - standing = upright on feet
   - seated = sitting
   - side_lying = lying on side
   - kneeling = on knees
   - foam_roller = on ground with foam roller
   - wall_sit = back against wall, knees bent
   Fail if the orientation is fundamentally wrong (e.g., standing when should be supine).

9. **POSE_ACCURACY**: Rate how well the pose matches the expected description on a scale of 1-5:
   - 1: Completely wrong exercise or unrelated pose (e.g., standing when should be lying down)
   - 2: Unrecognizable as the exercise — a user would not understand what exercise this is
   - 3: Recognizable as the exercise with some inaccuracies (e.g., high plank vs forearm plank, slight variation in limb positions). This is a PASS.
   - 4: Good representation with only minor deviations from the description
   - 5: Excellent match to the description
   Fail ONLY if score is 1. Score of 2 or above passes.
   Be generous — if a user could look at the image and understand the general exercise, it passes.

Return your analysis as structured JSON matching the required schema."""


# ---------- Core functions ----------

def build_qa_prompt(exercise: dict) -> str:
    """Build the QA prompt for a single exercise."""
    body_pos = exercise.get("body_position", "standing")
    body_pos_desc = BODY_POSITION_DESCRIPTIONS.get(body_pos, body_pos)

    pose_desc = exercise.get("pose_description", "")
    if not pose_desc:
        category = exercise.get("category", "general")
        target_area = exercise.get("target_area", "General")
        pose_desc = f"A {category} exercise targeting the {target_area}."

    return QA_PROMPT_TEMPLATE.format(
        character_desc=CHARACTER_DESC,
        exercise_name=exercise["name"],
        body_position=body_pos,
        body_position_description=body_pos_desc,
        pose_description=pose_desc,
    )


def _recompute_result(result: QAResult, exercise: dict) -> QAResult:
    """Recompute overall_pass and critical_failures server-side."""
    checks = {
        "ANATOMY": result.anatomy,
        "SUBJECT": result.subject,
        "FULL_BODY": result.full_body,
        "CLOTHING": result.clothing,
        "BACKGROUND": result.background,
        "NO_TEXT": result.no_text,
        "ART_STYLE": result.art_style,
        "BODY_ORIENTATION": result.body_orientation,
        "POSE_ACCURACY": result.pose_accuracy,
    }
    failures = [name for name, check in checks.items() if not check.passed]
    if result.pose_score <= 1 and "POSE_ACCURACY" not in failures:
        failures.append("POSE_ACCURACY")

    result.critical_failures = failures
    result.overall_pass = len(failures) == 0
    result.exercise_name = exercise["name"]
    result.filename = f"{exercise['normalized_filename']}.png"
    return result


def _make_error_result(exercise: dict, error_msg: str, error_type: str) -> QAResult:
    """Create a synthetic failure result for API or file errors."""
    fail_check = CheckResult(observation=error_msg, passed=False)
    return QAResult(
        exercise_name=exercise["name"],
        filename=f"{exercise['normalized_filename']}.png",
        anatomy=fail_check,
        subject=fail_check,
        full_body=fail_check,
        clothing=fail_check,
        background=fail_check,
        no_text=fail_check,
        art_style=fail_check,
        body_orientation=fail_check,
        pose_accuracy=fail_check,
        pose_score=1,
        overall_pass=False,
        critical_failures=[error_type],
    )


def analyze_image(
    client: genai.Client,
    image_path: Path,
    exercise: dict,
) -> QAResult:
    """
    Run QA analysis on a single exercise image synchronously.

    Sends the image + QA prompt to Gemini with structured output enforcement,
    then recomputes aggregates server-side.
    """
    if not image_path.exists():
        return _make_error_result(exercise, "Image file not found on disk", "IMAGE_NOT_FOUND")

    try:
        img = Image.open(image_path)
        prompt = build_qa_prompt(exercise)

        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[img, prompt],
            config={
                "response_mime_type": "application/json",
                "response_schema": QAResult,
            },
        )

        result = QAResult.model_validate_json(response.text)
        return _recompute_result(result, exercise)

    except Exception as e:
        return _make_error_result(exercise, f"API error: {e}", "API_ERROR")


async def analyze_image_async(
    client: genai.Client,
    image_path: Path,
    exercise: dict,
) -> QAResult:
    """Async wrapper around analyze_image using a thread executor."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(
        None, analyze_image, client, image_path, exercise
    )


# ---------- Batch processing ----------

async def run_batch_qa(
    client: genai.Client,
    exercises: list[dict],
    *,
    max_concurrent: int = MAX_CONCURRENT,
    verbose: bool = False,
) -> dict[str, QAResult]:
    """Run QA on all exercises concurrently with rate limiting."""
    semaphore = asyncio.Semaphore(max_concurrent)
    results: dict[str, QAResult] = {}

    async def process_one(exercise: dict) -> tuple[str, QAResult]:
        filename = exercise["normalized_filename"]
        image_path = OUTPUT_DIR / f"{filename}.png"

        async with semaphore:
            # Small delay to avoid rate limiting
            await asyncio.sleep(RATE_LIMIT_DELAY)
            result = await analyze_image_async(client, image_path, exercise)

            status = "PASS" if result.overall_pass else f"FAIL ({', '.join(result.critical_failures)})"
            if verbose:
                print(f"  [{filename}] {status}")
            else:
                symbol = "." if result.overall_pass else "F"
                print(symbol, end="", flush=True)

            return filename, result

    tasks = [process_one(ex) for ex in exercises]
    completed = await asyncio.gather(*tasks, return_exceptions=True)

    for item in completed:
        if isinstance(item, Exception):
            print(f"\n  Unexpected error: {item}")
            continue
        filename, result = item
        results[filename] = result

    if not verbose:
        print()  # newline after progress dots

    return results


# ---------- Report functions ----------

def build_report(results: dict[str, QAResult], skipped: int = 0) -> dict:
    """Aggregate individual results into a full QA report dict."""
    passed = sum(1 for r in results.values() if r.overall_pass)
    failed = sum(1 for r in results.values() if not r.overall_pass)

    failures_by_check: dict[str, int] = {}
    for r in results.values():
        for f in r.critical_failures:
            failures_by_check[f] = failures_by_check.get(f, 0) + 1

    return {
        "total_images": len(results),
        "passed": passed,
        "failed": failed,
        "skipped": skipped,
        "failures_by_check": dict(
            sorted(failures_by_check.items(), key=lambda x: -x[1])
        ),
        "results": {k: v.model_dump() for k, v in results.items()},
    }


def save_report(report: dict, output_path: Path) -> None:
    """Write QA report to JSON file."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\nReport saved: {output_path}")


def print_summary(report: dict) -> None:
    """Print human-readable summary to console."""
    total = report["total_images"]
    passed = report["passed"]
    failed = report["failed"]

    print(f"\n{'=' * 60}")
    print("  IMAGE QA SUMMARY")
    print(f"{'=' * 60}")
    print(f"  Total:   {total}")
    print(f"  Passed:  {passed} ({passed / max(total, 1) * 100:.0f}%)")
    print(f"  Failed:  {failed}")
    print(f"  Skipped: {report['skipped']}")

    if report["failures_by_check"]:
        print(f"\n  Failures by check:")
        for check, count in report["failures_by_check"].items():
            print(f"    {check}: {count}")

    # Pose score distribution
    results = report["results"]
    scores = [r["pose_score"] for r in results.values() if isinstance(r, dict)]
    if scores:
        avg = sum(scores) / len(scores)
        print(f"\n  Pose score: avg={avg:.1f}, min={min(scores)}, max={max(scores)}")


def print_failures(report: dict) -> None:
    """Print detailed failure information."""
    results = report["results"]
    failed = {k: v for k, v in results.items() if not v.get("overall_pass", False)}

    if not failed:
        print("\n  No failures!")
        return

    print(f"\n{'=' * 60}")
    print(f"  FAILED IMAGES ({len(failed)})")
    print(f"{'=' * 60}")

    for filename, result in failed.items():
        name = result.get("exercise_name", filename)
        failures = result.get("critical_failures", [])
        print(f"\n  {filename}.png ({name}):")
        print(f"    Failures: {', '.join(failures)}")

        for check_name in failures:
            check_key = check_name.lower()
            if check_key in ("api_error", "image_not_found"):
                continue
            check = result.get(check_key, {})
            if isinstance(check, dict) and "observation" in check:
                print(f"      {check_name}: {check['observation']}")

        pose_score = result.get("pose_score", 0)
        if pose_score <= 2:
            print(f"      POSE_SCORE: {pose_score}/5")


# ---------- Recheck support ----------

def load_previous_failures(report_path: Path) -> set[str]:
    """Load normalized_filenames of previously failed images."""
    if not report_path.exists():
        return set()
    with open(report_path) as f:
        data = json.load(f)
    return {
        k for k, v in data.get("results", {}).items()
        if not v.get("overall_pass", False)
    }


# ---------- Integration hook ----------

def qa_single_image(
    api_key: str,
    image_path: Path,
    exercise: dict,
) -> QAResult:
    """
    Convenience function for QA on a single image.
    Can be called from generate_exercise_images.py.
    """
    client = genai.Client(api_key=api_key)
    return analyze_image(client, image_path, exercise)


# ---------- Main ----------

def main():
    parser = argparse.ArgumentParser(
        description="QA exercise illustration images using Gemini 2.5 Flash vision"
    )
    parser.add_argument(
        "--api-key", required=True,
        help="Google AI / Gemini API key",
    )
    parser.add_argument(
        "--filter-name", type=str, default="",
        help="Comma-separated normalized filenames to test",
    )
    parser.add_argument(
        "--filter-position", type=str, default="",
        help="Comma-separated body_position values to test",
    )
    parser.add_argument(
        "--output", type=str, default=str(DEFAULT_REPORT_PATH),
        help=f"Path for QA report JSON (default: {DEFAULT_REPORT_PATH})",
    )
    parser.add_argument(
        "--recheck", action="store_true",
        help="Only re-check previously failed images from existing report",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="Print detailed per-image results",
    )
    parser.add_argument(
        "--max-concurrent", type=int, default=MAX_CONCURRENT,
        help=f"Max concurrent API requests (default: {MAX_CONCURRENT})",
    )
    args = parser.parse_args()

    # Load exercises
    exercises = load_exercise_list()
    print(f"Loaded {len(exercises)} exercises")

    # Apply filters
    if args.filter_position:
        allowed = set(p.strip() for p in args.filter_position.split(","))
        exercises = [e for e in exercises if e.get("body_position", "") in allowed]
        print(f"Filtered to {len(exercises)} exercises by body_position: {allowed}")

    if args.filter_name:
        names = set(n.strip() for n in args.filter_name.split(","))
        exercises = [e for e in exercises if e["normalized_filename"] in names]
        print(f"Filtered to {len(exercises)} exercises by name")

    report_path = Path(args.output)

    if args.recheck:
        previous_failures = load_previous_failures(report_path)
        exercises = [e for e in exercises if e["normalized_filename"] in previous_failures]
        print(f"Rechecking {len(exercises)} previously failed images...")

    if not exercises:
        print("No exercises to check.")
        return

    # Run QA
    print(f"\nRunning QA on {len(exercises)} images using {GEMINI_MODEL}...")
    print(f"Max concurrent: {args.max_concurrent}\n")

    client = genai.Client(api_key=args.api_key)

    start_time = time.time()
    results = asyncio.run(
        run_batch_qa(
            client, exercises,
            max_concurrent=args.max_concurrent,
            verbose=args.verbose,
        )
    )
    elapsed = time.time() - start_time

    # If rechecking, merge with previous results
    if args.recheck and report_path.exists():
        with open(report_path) as f:
            prev_data = json.load(f)
        prev_results = prev_data.get("results", {})
        # Overwrite failed entries with new results
        for k, v in results.items():
            prev_results[k] = v.model_dump()
        # Rebuild results for report
        merged_results = {}
        for k, v in prev_results.items():
            if isinstance(v, dict):
                try:
                    merged_results[k] = QAResult.model_validate(v)
                except Exception:
                    pass  # skip corrupt entries
        results = merged_results

    report = build_report(results)
    save_report(report, report_path)
    print_summary(report)

    if args.verbose or report["failed"] > 0:
        print_failures(report)

    print(f"\n  Time: {elapsed:.1f}s ({elapsed / max(len(results), 1):.1f}s per image)")

    sys.exit(1 if report["failed"] > 0 else 0)


if __name__ == "__main__":
    main()
