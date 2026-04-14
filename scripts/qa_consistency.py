#!/usr/bin/env python3
"""
Consistency QA for start/end exercise image pairs.

Compares start and end images side-by-side to check visual consistency
(camera angle, character appearance, scene setup, equipment) and
movement correctness (logical progression from start to end).

Uses Gemini 2.5 Flash vision with both images in a single prompt.

Usage:
    python qa_consistency.py --api-key YOUR_GEMINI_KEY
    python qa_consistency.py --api-key KEY --filter-name bird-dog,clamshells --verbose
    python qa_consistency.py --api-key KEY --recheck

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
    print("ERROR: google-genai package not installed. Run: pip install google-genai")
    sys.exit(1)

try:
    from pydantic import BaseModel, Field
except ImportError:
    print("ERROR: pydantic package not installed. Run: pip install pydantic")
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow package not installed. Run: pip install Pillow")
    sys.exit(1)

# ---------- Constants ----------

SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output"
DEFAULT_REPORT_PATH = OUTPUT_DIR / "consistency_report.json"
GEMINI_MODEL = "gemini-2.5-flash"
MAX_CONCURRENT = 5
RATE_LIMIT_DELAY = 1.0


# ---------- Pydantic schemas ----------

class ConsistencyCheck(BaseModel):
    """Result of a single consistency check."""
    observation: str = Field(
        description="Brief description of what was observed comparing the two images"
    )
    score: int = Field(
        ge=1, le=5,
        description="Consistency score: 1=completely different, 3=acceptable, 5=perfect match"
    )
    passed: bool = Field(
        description="Whether this check passes (score >= 3)"
    )


class ConsistencyResult(BaseModel):
    """Complete consistency QA result for a start/end image pair."""
    exercise_name: str = Field(description="Name of the exercise")
    filename: str = Field(description="Base filename (without _end suffix)")

    # Consistency checks
    camera_angle: ConsistencyCheck = Field(
        description="CAMERA_ANGLE: Are both images shot from the same camera angle and distance?"
    )
    character_identity: ConsistencyCheck = Field(
        description="CHARACTER_IDENTITY: Is it the same person? Same face, hair, body build?"
    )
    clothing: ConsistencyCheck = Field(
        description="CLOTHING: Same clothing in both images? Same colors, fit, style?"
    )
    art_style: ConsistencyCheck = Field(
        description="ART_STYLE: Same rendering style? Same level of detail, shading, line work?"
    )
    scene_setup: ConsistencyCheck = Field(
        description="SCENE_SETUP: Same environment and props? Equipment in same position/configuration?"
    )
    body_anchoring: ConsistencyCheck = Field(
        description="BODY_ANCHORING: Are the non-moving body parts in the same position? Only the exercised limb/region should change."
    )

    # Movement correctness
    movement_logic: ConsistencyCheck = Field(
        description="MOVEMENT_LOGIC: Does the end position look like a natural progression from the start? Could a user understand the movement by comparing these two images?"
    )

    # Aggregates (recomputed server-side)
    overall_consistency_score: float = Field(
        description="Average of all consistency scores (1-5)"
    )
    overall_pass: bool = Field(
        description="True if no check scored below 3 AND average score >= 3.5"
    )
    critical_failures: list[str] = Field(
        description="Check names that scored below 3"
    )


# ---------- Prompt ----------

CONSISTENCY_PROMPT_TEMPLATE = """You are a quality assurance inspector comparing START and END exercise illustration images for visual consistency.

## Exercise Context
- Exercise Name: {exercise_name}
- Start Position: {start_description}
- End Position: {end_description}

## Images
- Image 1 (LEFT): The START position
- Image 2 (RIGHT): The END position

## Instructions
Compare these two images as a PAIR. The goal is that a user looking at both side-by-side can clearly understand the exercise movement. Only the exercised body part should change between frames — everything else should look identical.

Rate each check on a 1-5 scale:
- 1: Completely different / unacceptable
- 2: Major inconsistency that confuses the user
- 3: Minor inconsistency but user can still understand the exercise (PASS threshold)
- 4: Good consistency with only subtle differences
- 5: Perfect match (except for the intended movement)

### Checks

1. **CAMERA_ANGLE**: Same viewpoint, distance, and framing? Both should look like photos taken from the same position. Fail if one is front-facing and other is side profile, or if zoom level is very different.

2. **CHARACTER_IDENTITY**: Same person in both? Check face shape, hair style/color, skin tone, body proportions. Minor rendering differences are OK (score 4). Completely different face/build fails.

3. **CLOTHING**: Identical outfit? Same shirt color, shorts color, shoe style. Even slight color shifts (light gray vs white) should score no higher than 4.

4. **ART_STYLE**: Same artistic rendering? Check line weight, shading technique, level of detail, color palette. One image looking photorealistic while the other looks cartoony is a major fail.

5. **SCENE_SETUP**: Same background and props? If there's a wall, bench, band, or ball, it should be in the same position and look the same. Equipment appearing or disappearing between frames is a fail.

6. **BODY_ANCHORING**: Are the parts of the body that SHOULD NOT MOVE actually in the same position? For example, in a leg raise, the arms, torso, and supporting leg should be identical. Only the moving limb should change. This is the most important consistency check.

7. **MOVEMENT_LOGIC**: Does the transition make sense? Could someone look at these two images and understand what movement to perform? The end position should be a natural continuation of the start position for this specific exercise.

Return your analysis as structured JSON matching the required schema. Set overall_pass to true ONLY if no check scored below 3 AND the average score is >= 3.5."""


# ---------- Core functions ----------

def build_consistency_prompt(exercise: dict) -> str:
    """Build the consistency QA prompt for an exercise pair."""
    start_desc = exercise.get("pose_description", "Standard starting position")
    end_desc = exercise.get("end_pose_description", "End/peak position of the movement")

    return CONSISTENCY_PROMPT_TEMPLATE.format(
        exercise_name=exercise["name"],
        start_description=start_desc,
        end_description=end_desc,
    )


def _recompute_consistency(result: ConsistencyResult, exercise: dict) -> ConsistencyResult:
    """Recompute aggregates server-side."""
    checks = {
        "CAMERA_ANGLE": result.camera_angle,
        "CHARACTER_IDENTITY": result.character_identity,
        "CLOTHING": result.clothing,
        "ART_STYLE": result.art_style,
        "SCENE_SETUP": result.scene_setup,
        "BODY_ANCHORING": result.body_anchoring,
        "MOVEMENT_LOGIC": result.movement_logic,
    }

    scores = [c.score for c in checks.values()]
    avg_score = sum(scores) / len(scores) if scores else 0

    failures = [name for name, check in checks.items() if check.score < 3]

    # Recompute pass/fail on individual checks too
    for check in checks.values():
        check.passed = check.score >= 3

    result.overall_consistency_score = round(avg_score, 2)
    result.critical_failures = failures
    result.overall_pass = len(failures) == 0 and avg_score >= 3.5
    result.exercise_name = exercise["name"]
    result.filename = exercise.get("normalized_filename", "")

    return result


def _make_error_result(exercise: dict, error_msg: str, error_type: str) -> ConsistencyResult:
    """Create a synthetic failure result."""
    fail_check = ConsistencyCheck(observation=error_msg, score=1, passed=False)
    return ConsistencyResult(
        exercise_name=exercise.get("name", "unknown"),
        filename=exercise.get("normalized_filename", "unknown"),
        camera_angle=fail_check,
        character_identity=fail_check,
        clothing=fail_check,
        art_style=fail_check,
        scene_setup=fail_check,
        body_anchoring=fail_check,
        movement_logic=fail_check,
        overall_consistency_score=1.0,
        overall_pass=False,
        critical_failures=[error_type],
    )


def analyze_consistency(
    client: genai.Client,
    start_path: Path,
    end_path: Path,
    exercise: dict,
) -> ConsistencyResult:
    """Run consistency analysis on a start/end image pair."""
    if not start_path.exists():
        return _make_error_result(exercise, f"Start image not found: {start_path}", "START_NOT_FOUND")
    if not end_path.exists():
        return _make_error_result(exercise, f"End image not found: {end_path}", "END_NOT_FOUND")

    try:
        start_img = Image.open(start_path)
        end_img = Image.open(end_path)
        prompt = build_consistency_prompt(exercise)

        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[start_img, end_img, prompt],
            config={
                "response_mime_type": "application/json",
                "response_schema": ConsistencyResult,
            },
        )

        result = ConsistencyResult.model_validate_json(response.text)
        return _recompute_consistency(result, exercise)

    except Exception as e:
        return _make_error_result(exercise, f"API error: {e}", "API_ERROR")


async def analyze_consistency_async(
    client: genai.Client,
    start_path: Path,
    end_path: Path,
    exercise: dict,
) -> ConsistencyResult:
    """Async wrapper."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(
        None, analyze_consistency, client, start_path, end_path, exercise
    )


# ---------- Batch processing ----------

async def run_batch_consistency(
    client: genai.Client,
    exercises: list[dict],
    *,
    max_concurrent: int = MAX_CONCURRENT,
    verbose: bool = False,
) -> dict[str, ConsistencyResult]:
    """Run consistency QA on all exercise pairs."""
    semaphore = asyncio.Semaphore(max_concurrent)
    results: dict[str, ConsistencyResult] = {}

    async def process_one(exercise: dict) -> tuple[str, ConsistencyResult]:
        filename = exercise["normalized_filename"]
        start_path = OUTPUT_DIR / f"{filename}.png"
        end_path = OUTPUT_DIR / f"{filename}_end.png"

        async with semaphore:
            await asyncio.sleep(RATE_LIMIT_DELAY)
            result = await analyze_consistency_async(client, start_path, end_path, exercise)

            if verbose:
                score = result.overall_consistency_score
                status = f"PASS (avg={score})" if result.overall_pass else f"FAIL (avg={score}, {', '.join(result.critical_failures)})"
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
        print()

    return results


# ---------- Report ----------

def build_consistency_report(results: dict[str, ConsistencyResult]) -> dict:
    """Aggregate consistency results."""
    passed = sum(1 for r in results.values() if r.overall_pass)
    failed = sum(1 for r in results.values() if not r.overall_pass)

    all_scores = [r.overall_consistency_score for r in results.values()]
    avg_score = sum(all_scores) / len(all_scores) if all_scores else 0

    # Per-check average scores
    check_names = ["camera_angle", "character_identity", "clothing",
                   "art_style", "scene_setup", "body_anchoring", "movement_logic"]
    check_averages = {}
    check_failures = {}
    for name in check_names:
        scores = [getattr(r, name).score for r in results.values()]
        check_averages[name] = round(sum(scores) / len(scores), 2) if scores else 0
        check_failures[name] = sum(1 for s in scores if s < 3)

    return {
        "total_pairs": len(results),
        "passed": passed,
        "failed": failed,
        "average_consistency_score": round(avg_score, 2),
        "check_averages": check_averages,
        "check_failures": dict(sorted(check_failures.items(), key=lambda x: -x[1])),
        "results": {k: v.model_dump() for k, v in results.items()},
    }


def print_consistency_summary(report: dict) -> None:
    """Print human-readable summary."""
    total = report["total_pairs"]
    passed = report["passed"]
    failed = report["failed"]

    print(f"\n{'=' * 60}")
    print("  CONSISTENCY QA SUMMARY")
    print(f"{'=' * 60}")
    print(f"  Total pairs:    {total}")
    print(f"  Consistent:     {passed} ({passed / max(total, 1) * 100:.0f}%)")
    print(f"  Inconsistent:   {failed}")
    print(f"  Average score:  {report['average_consistency_score']}/5.0")

    print(f"\n  Per-check averages:")
    for check, avg in report["check_averages"].items():
        failures = report["check_failures"].get(check, 0)
        bar = "█" * int(avg) + "░" * (5 - int(avg))
        fail_str = f"  ({failures} failures)" if failures > 0 else ""
        print(f"    {check:<22} {bar} {avg}/5{fail_str}")

    # Show worst pairs
    results = report["results"]
    worst = sorted(
        [(k, v) for k, v in results.items() if not v.get("overall_pass", True)],
        key=lambda x: x[1].get("overall_consistency_score", 5),
    )
    if worst:
        print(f"\n  Worst inconsistencies:")
        for filename, result in worst[:10]:
            score = result.get("overall_consistency_score", 0)
            failures = result.get("critical_failures", [])
            print(f"    {filename}: score={score}, failures={', '.join(failures)}")


# ---------- Main ----------

def main():
    parser = argparse.ArgumentParser(
        description="Consistency QA for start/end exercise image pairs"
    )
    parser.add_argument("--api-key", required=True, help="Google AI / Gemini API key")
    parser.add_argument("--filter-name", type=str, default="", help="Comma-separated filenames")
    parser.add_argument("--output", type=str, default=str(DEFAULT_REPORT_PATH))
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--recheck", action="store_true", help="Re-check previously failed pairs")
    parser.add_argument("--max-concurrent", type=int, default=MAX_CONCURRENT)
    # Allow checking images from stockpile (not just exercise_list.json)
    parser.add_argument("--scan-output", action="store_true",
                        help="Scan output dir for all *_end.png pairs instead of using exercise_list.json")
    args = parser.parse_args()

    # Find exercise pairs
    if args.scan_output:
        # Scan for all start/end pairs in output directory
        end_images = sorted(OUTPUT_DIR.glob("*_end.png"))
        exercises = []
        for end_path in end_images:
            filename = end_path.stem.replace("_end", "")
            start_path = OUTPUT_DIR / f"{filename}.png"
            if start_path.exists():
                exercises.append({
                    "name": filename.replace("-", " ").title(),
                    "normalized_filename": filename,
                    "pose_description": "",
                    "end_pose_description": "",
                })
        print(f"Found {len(exercises)} start/end pairs in {OUTPUT_DIR}")
    else:
        from generate_exercise_images import load_exercise_list
        all_exercises = load_exercise_list()
        # Only check exercises that have both start and end images
        exercises = []
        for ex in all_exercises:
            filename = ex["normalized_filename"]
            if (OUTPUT_DIR / f"{filename}.png").exists() and (OUTPUT_DIR / f"{filename}_end.png").exists():
                exercises.append(ex)
        print(f"Found {len(exercises)} exercises with start/end pairs (out of {len(all_exercises)} total)")

    # Apply filters
    if args.filter_name:
        names = set(n.strip() for n in args.filter_name.split(","))
        exercises = [e for e in exercises if e["normalized_filename"] in names]
        print(f"Filtered to {len(exercises)} exercises")

    report_path = Path(args.output)

    if args.recheck:
        if report_path.exists():
            with open(report_path) as f:
                prev = json.load(f)
            failed_names = {
                k for k, v in prev.get("results", {}).items()
                if not v.get("overall_pass", True)
            }
            exercises = [e for e in exercises if e["normalized_filename"] in failed_names]
            print(f"Rechecking {len(exercises)} previously failed pairs")

    if not exercises:
        print("No exercise pairs to check.")
        return

    print(f"\nRunning consistency QA on {len(exercises)} pairs using {GEMINI_MODEL}...")

    client = genai.Client(api_key=args.api_key)

    start_time = time.time()
    results = asyncio.run(
        run_batch_consistency(
            client, exercises,
            max_concurrent=args.max_concurrent,
            verbose=args.verbose,
        )
    )
    elapsed = time.time() - start_time

    report = build_consistency_report(results)

    report_path.parent.mkdir(parents=True, exist_ok=True)
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2)
    print(f"\nReport saved: {report_path}")

    print_consistency_summary(report)
    print(f"\n  Time: {elapsed:.1f}s ({elapsed / max(len(results), 1):.1f}s per pair)")

    sys.exit(1 if report["failed"] > 0 else 0)


if __name__ == "__main__":
    main()
