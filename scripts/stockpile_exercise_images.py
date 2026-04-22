#!/usr/bin/env python3
"""
Exercise image stockpiling agent.

Generates rehab plans for hundreds of conditions via Claude Haiku,
collects all unique exercise names, identifies gaps in the image library,
and batch-generates images via FLUX 2 Pro with Gemini QA.

Designed to be left running for hours. Resumable via progress file.

Usage:
  python stockpile_exercise_images.py \
    --anthropic-key <key> --bfl-key <key> --gemini-key <key>

  # Dry run (plan generation only, no images)
  python stockpile_exercise_images.py --anthropic-key <key> --dry-run

  # Resume from previous run
  python stockpile_exercise_images.py \
    --anthropic-key <key> --bfl-key <key> --gemini-key <key> --resume

  # Generate plans only (skip image generation)
  python stockpile_exercise_images.py --anthropic-key <key> --plans-only

  # Generate images only (from existing progress file)
  python stockpile_exercise_images.py \
    --bfl-key <key> --gemini-key <key> --images-only
"""

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output"
PROGRESS_FILE = OUTPUT_DIR / "stockpile_progress.json"
MAPPING_FILE = OUTPUT_DIR / "exercise_image_mapping.json"
IOS_MAPPING_FILE = (
    SCRIPT_DIR.parent
    / "ios"
    / "PT-Helper"
    / "PT-Helper"
    / "Resources"
    / "exercise_image_mapping.json"
)

# ---------------------------------------------------------------------------
# Condition database: organized by category with demographic variations
# ---------------------------------------------------------------------------

CONDITIONS = {
    "orthopedic_knee": [
        "ACL reconstruction recovery",
        "meniscus tear conservative management",
        "patellofemoral pain syndrome",
        "IT band syndrome in runners",
        "patellar tendinitis (jumper's knee)",
        "knee osteoarthritis grade 2",
        "PCL sprain grade 1",
        "MCL sprain recovery",
        "Baker's cyst management",
        "chondromalacia patella",
    ],
    "orthopedic_shoulder": [
        "rotator cuff tendinopathy",
        "post rotator cuff repair (6 weeks post-op)",
        "frozen shoulder (adhesive capsulitis)",
        "shoulder impingement syndrome",
        "SLAP tear conservative treatment",
        "shoulder instability (recurrent anterior dislocation)",
        "AC joint separation grade 2",
        "biceps tendinitis",
        "thoracic outlet syndrome",
        "scapular dyskinesia",
    ],
    "orthopedic_spine": [
        "lumbar disc herniation L4-L5",
        "cervical radiculopathy C5-C6",
        "spinal stenosis conservative management",
        "SI joint dysfunction",
        "spondylolisthesis grade 1",
        "degenerative disc disease lumbar",
        "thoracic spine stiffness",
        "facet joint syndrome",
        "cervicogenic headache",
        "scoliosis postural management",
    ],
    "orthopedic_hip": [
        "hip labral tear conservative management",
        "hip bursitis (trochanteric)",
        "piriformis syndrome",
        "hip flexor strain recovery",
        "hip osteoarthritis early stage",
        "post total hip replacement (8 weeks)",
        "FAI (femoroacetabular impingement)",
        "adductor strain recovery",
        "snapping hip syndrome",
        "ischial bursitis (weaver's bottom)",
    ],
    "orthopedic_ankle_foot": [
        "lateral ankle sprain grade 2 recovery",
        "plantar fasciitis chronic",
        "Achilles tendinopathy",
        "posterior tibial tendon dysfunction stage 1",
        "ankle impingement (anterior)",
        "peroneal tendinopathy",
        "high ankle sprain recovery",
        "metatarsalgia management",
        "tarsal tunnel syndrome",
        "chronic ankle instability",
    ],
    "orthopedic_elbow_wrist": [
        "lateral epicondylitis (tennis elbow)",
        "medial epicondylitis (golfer's elbow)",
        "carpal tunnel syndrome conservative",
        "de Quervain's tenosynovitis",
        "trigger finger non-surgical",
        "ulnar nerve entrapment at elbow",
        "wrist sprain recovery",
        "distal radius fracture post-cast",
        "forearm tendinitis",
        "elbow stiffness post-immobilization",
    ],
    "post_surgical": [
        "post ACL reconstruction (12 weeks)",
        "post meniscectomy (4 weeks)",
        "post rotator cuff repair (12 weeks)",
        "post lumbar microdiscectomy (6 weeks)",
        "post total knee replacement (8 weeks)",
        "post hip arthroscopy (6 weeks)",
        "post shoulder arthroscopy (4 weeks)",
        "post cervical fusion (12 weeks)",
        "post carpal tunnel release (3 weeks)",
        "post Achilles tendon repair (8 weeks)",
    ],
    "sports_injuries": [
        "hamstring strain grade 2 (sprinter)",
        "shin splints (medial tibial stress syndrome)",
        "runner's knee return to running",
        "tennis shoulder overuse",
        "swimmer's shoulder",
        "golfer's lower back pain",
        "basketball ankle sprain recovery",
        "soccer groin strain",
        "climber's finger pulley injury",
        "cyclist's knee tracking issues",
    ],
    "wellness_posture": [
        "desk worker upper back and neck pain",
        "forward head posture correction",
        "rounded shoulders from computer work",
        "text neck syndrome",
        "lower crossed syndrome",
        "upper crossed syndrome",
        "postural kyphosis improvement",
        "workstation ergonomic adaptation exercises",
    ],
    "wellness_mobility": [
        "general flexibility improvement for sedentary adult",
        "hip mobility for desk workers",
        "thoracic spine mobility improvement",
        "ankle mobility for squatting",
        "shoulder mobility overhead athletes",
        "full body morning mobility routine",
        "pre-workout dynamic warm-up routine",
        "post-workout cool-down stretching",
    ],
    "wellness_strength": [
        "core strengthening for lower back prevention",
        "senior fall prevention balance program",
        "pregnancy-safe exercise program (second trimester)",
        "postpartum recovery exercise program",
        "osteoporosis prevention weight-bearing exercises",
        "sarcopenia prevention for elderly",
        "rotator cuff prehab for overhead athletes",
        "ACL injury prevention program for female athletes",
    ],
    "wellness_other": [
        "sleep improvement exercise routine",
        "stress reduction movement practice",
        "chronic pain management gentle exercise",
        "fibromyalgia low-impact exercise program",
        "rheumatoid arthritis joint protection exercises",
        "diabetes management aerobic and resistance program",
        "hypertension exercise prescription",
        "COPD pulmonary rehab exercises",
    ],
    "geriatric": [
        "balance and fall prevention for 75 year old",
        "hip fracture prevention exercises for elderly",
        "gentle mobility for severe osteoarthritis",
        "chair-based exercises for limited mobility elderly",
        "Parkinson's disease balance exercises",
        "post-stroke upper extremity rehab",
        "osteoporosis safe exercise program for 70 year old",
        "gentle strengthening for frail elderly",
    ],
    "pediatric_young_adult": [
        "Osgood-Schlatter disease management (14 year old)",
        "adolescent scoliosis exercise program",
        "growing pains management exercises",
        "young athlete ACL prevention program",
        "Little League shoulder rehab",
        "youth sports overuse injury prevention",
    ],
    "pelvic_health": [
        "pelvic floor dysfunction (hypertonic)",
        "pelvic floor weakness post-vaginal delivery",
        "diastasis recti postpartum 12 weeks",
        "stress urinary incontinence in women",
        "pelvic organ prolapse stage 2",
        "post C-section core recovery (8 weeks)",
        "coccydynia (tailbone pain)",
        "male chronic pelvic pain syndrome",
        "post prostatectomy continence rehab",
        "dyspareunia pelvic floor therapy",
    ],
    "vestibular_neuro": [
        "BPPV post-Epley residual imbalance",
        "vestibular migraine management",
        "post-concussion vestibular rehab (4 weeks)",
        "cervicogenic dizziness",
        "unilateral vestibular hypofunction",
        "gaze stabilization training program",
        "mild traumatic brain injury return to activity",
        "persistent postural-perceptual dizziness (PPPD)",
    ],
    "tmj_head_face": [
        "TMJ dysfunction with jaw clicking",
        "bruxism-related jaw pain",
        "Bell's palsy facial re-education",
        "tension-type headache management",
        "post whiplash cervical-TMJ pain",
    ],
    "neurological_rehab": [
        "multiple sclerosis fatigue management program",
        "Parkinson's disease early stage (Hoehn-Yahr 1-2)",
        "Parkinson's LSVT BIG program exercises",
        "post-stroke lower extremity gait training (6 months)",
        "incomplete spinal cord injury (T10) ambulation",
        "peripheral neuropathy diabetic balance program",
        "Guillain-Barre recovery conditioning",
        "ALS early stage energy conservation",
    ],
    "sport_specific": [
        "pickleball elbow management",
        "marathon runner IT band recovery",
        "volleyball jumper's patellar tendinopathy",
        "CrossFit shoulder impingement",
        "Olympic lifter wrist pain",
        "yoga-induced SI joint irritation",
        "rock climber finger A2 pulley strain",
        "hockey goalie hip labral care",
        "baseball pitcher UCL prehab",
        "dancer hip flexor tendinopathy",
    ],
    "occupational": [
        "construction worker chronic low back pain",
        "nurse thoracic and lumbar pain from patient lifting",
        "dentist upper back and neck strain",
        "musician violinist neck and shoulder pain",
        "long-haul truck driver hip and back tightness",
        "warehouse worker shoulder overuse",
        "hairstylist forearm and wrist pain",
        "chef lower back and plantar fascia pain",
    ],
    "pediatric_extended": [
        "infant congenital muscular torticollis",
        "pediatric flexible flatfoot exercises",
        "Sever's disease (calcaneal apophysitis) in young athlete",
        "adolescent sports hernia management",
        "juvenile idiopathic arthritis knee program",
        "pediatric hypermobility joint stability",
    ],
    "chronic_systemic": [
        "Ehlers-Danlos hypermobility spectrum stability",
        "fibromyalgia graded exercise program",
        "ankylosing spondylitis spinal mobility",
        "psoriatic arthritis joint protection",
        "lupus fatigue-adapted exercise program",
        "CRPS (complex regional pain syndrome) upper limb desensitization",
        "chronic fatigue syndrome pacing-based exercise",
    ],
    "oncology_rehab": [
        "post-mastectomy shoulder mobility (6 weeks)",
        "upper extremity lymphedema management",
        "radiation fibrosis neck and shoulder",
        "cancer survivor deconditioning reconditioning program",
        "chemotherapy-induced peripheral neuropathy balance",
    ],
    "cardiopulmonary": [
        "post-MI phase 2 cardiac rehab",
        "post-CABG sternal precaution exercises (6 weeks)",
        "heart failure NYHA class 2 exercise program",
        "pulmonary rehab for COPD GOLD 2",
        "long COVID exertion intolerance program",
        "dysfunctional breathing pattern retraining",
    ],
    "hand_therapy": [
        "Dupuytren's contracture post-needle aponeurotomy",
        "mallet finger splint-plus-exercise protocol",
        "skier's thumb (UCL) conservative management",
        "boutonniere deformity rehab",
        "flexor tendon repair zone 2 (8 weeks post-op)",
        "thumb CMC osteoarthritis conservative",
    ],
    "foot_specialty": [
        "hallux rigidus conservative management",
        "hallux valgus (bunion) non-surgical exercises",
        "Morton's neuroma load management",
        "sesamoiditis off-loading exercises",
        "turf toe grade 1 return to sport",
        "tibial stress fracture return to running",
        "cuboid syndrome stabilization",
    ],
    "return_to_sport": [
        "ACL post-op return to running (16 weeks)",
        "hamstring strain return to sprinting",
        "rotator cuff repair return to overhead sport (6 months)",
        "ankle sprain return to cutting sports",
        "lumbar disc herniation return to golf",
        "shoulder labral repair return to throwing",
    ],
}

# Demographics to vary plans with
DEMOGRAPHICS = [
    {"age": 25, "activity_level": "active", "equipment": "gym"},
    {"age": 45, "activity_level": "moderate", "equipment": "bands"},
    {"age": 65, "activity_level": "sedentary", "equipment": "none"},
    {"age": 35, "activity_level": "active", "equipment": "dumbbells"},
]


def generate_plan(
    condition: str,
    demographic: dict,
    api_key: str,
) -> list[dict] | None:
    """Generate a rehab plan via Claude Haiku and extract exercise metadata."""
    import anthropic

    client = anthropic.Anthropic(api_key=api_key)

    age = demographic["age"]
    activity = demographic["activity_level"]
    equipment = demographic["equipment"]

    prompt = f"""Generate a physical therapy/rehab exercise plan for:
- Condition: {condition}
- Patient: {age} year old, {activity} activity level
- Available equipment: {equipment}

Return ONLY a JSON array of 6-10 exercises. Each exercise must have:
- name: Exercise display name
- imageFileName: normalized kebab-case filename (e.g., "quad-sets", "bird-dog")
- exerciseCategory: one of "strength", "stretch", "mobility", "balance", "core", "cardio"
- targetArea: primary body region (e.g., "Knee", "Shoulder", "Back", "Hip")
- bodyPosition: one of "standing", "supine", "prone", "seated", "quadruped", "side_lying", "kneeling"
- startPoseDescription: 2-sentence description of the START position for illustration
- endPoseDescription: 2-sentence description of the END/PEAK position for illustration

Return ONLY the JSON array, no other text."""

    try:
        response = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=2000,
            messages=[{"role": "user", "content": prompt}],
        )

        text = response.content[0].text.strip()
        # Extract JSON array
        if "```" in text:
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip()

        exercises = json.loads(text)

        # Validate schema
        if not isinstance(exercises, list):
            print(f"    Warning: response is not a list")
            return None

        valid = []
        for ex in exercises:
            if isinstance(ex, dict) and "name" in ex and "imageFileName" in ex:
                valid.append(ex)

        return valid if valid else None

    except json.JSONDecodeError as e:
        print(f"    JSON parse error: {e}")
        return None
    except Exception as e:
        print(f"    API error: {e}")
        return None


def load_progress() -> dict:
    """Load progress from previous run."""
    if PROGRESS_FILE.exists():
        with open(PROGRESS_FILE) as f:
            return json.load(f)
    return {
        "completed_conditions": [],
        "all_exercises": {},  # normalized_key → exercise metadata
        "gap_analysis": {},   # normalized_key → "has_image" | "alias_found" | "needs_image"
        "generated_images": [],
        "failed_images": [],
        "started_at": datetime.now().isoformat(),
        "last_updated": datetime.now().isoformat(),
    }


def save_progress(progress: dict):
    """Save progress for resume capability."""
    progress["last_updated"] = datetime.now().isoformat()
    with open(PROGRESS_FILE, "w") as f:
        json.dump(progress, f, indent=2)


def phase1_generate_plans(progress: dict, api_key: str, dry_run: bool = False):
    """Phase 1: Generate plans for all conditions and collect unique exercises."""
    from fuzzy_match import normalize_name

    total_conditions = sum(len(v) for v in CONDITIONS.values())
    print(f"\n{'='*60}")
    print(f"Phase 1: Generating plans for {total_conditions} conditions")
    print(f"{'='*60}")

    condition_count = 0
    for category, conditions in CONDITIONS.items():
        print(f"\n--- Category: {category} ({len(conditions)} conditions) ---")

        for condition in conditions:
            condition_key = f"{category}:{condition}"

            if condition_key in progress["completed_conditions"]:
                condition_count += 1
                continue

            # Pick a demographic variation
            demo = DEMOGRAPHICS[condition_count % len(DEMOGRAPHICS)]
            condition_count += 1

            print(f"  [{condition_count}/{total_conditions}] {condition} (age={demo['age']}, equip={demo['equipment']})")

            if dry_run:
                progress["completed_conditions"].append(condition_key)
                continue

            exercises = generate_plan(condition, demo, api_key)
            if not exercises:
                print(f"    ⚠ Failed to generate plan")
                progress["completed_conditions"].append(condition_key)
                save_progress(progress)
                time.sleep(2)
                continue

            # Collect unique exercises
            new_count = 0
            for ex in exercises:
                normalized = normalize_name(ex.get("imageFileName") or ex["name"])
                if normalized not in progress["all_exercises"]:
                    progress["all_exercises"][normalized] = {
                        "name": ex["name"],
                        "imageFileName": ex.get("imageFileName", normalized),
                        "category": ex.get("exerciseCategory", "general"),
                        "targetArea": ex.get("targetArea", "General"),
                        "bodyPosition": ex.get("bodyPosition", "standing"),
                        "startPoseDescription": ex.get("startPoseDescription", ""),
                        "endPoseDescription": ex.get("endPoseDescription", ""),
                        "conditions_seen_in": [condition],
                    }
                    new_count += 1
                else:
                    # Track which conditions use this exercise
                    seen = progress["all_exercises"][normalized].get("conditions_seen_in", [])
                    if condition not in seen:
                        seen.append(condition)
                    # Update descriptions if better ones available
                    if ex.get("startPoseDescription") and not progress["all_exercises"][normalized].get("startPoseDescription"):
                        progress["all_exercises"][normalized]["startPoseDescription"] = ex["startPoseDescription"]
                    if ex.get("endPoseDescription") and not progress["all_exercises"][normalized].get("endPoseDescription"):
                        progress["all_exercises"][normalized]["endPoseDescription"] = ex["endPoseDescription"]

            print(f"    ✓ {len(exercises)} exercises ({new_count} new, {len(progress['all_exercises'])} total unique)")
            progress["completed_conditions"].append(condition_key)
            save_progress(progress)
            time.sleep(2)  # Rate limit

    print(f"\nPhase 1 complete: {len(progress['all_exercises'])} unique exercises found")


def phase2_gap_analysis(progress: dict):
    """Phase 2: Check each exercise against the mapping + alias system."""
    from fuzzy_match import FuzzyMatcher, normalize_name

    print(f"\n{'='*60}")
    print(f"Phase 2: Gap analysis for {len(progress['all_exercises'])} exercises")
    print(f"{'='*60}")

    matcher = FuzzyMatcher.from_mapping_file()

    has_image = 0
    alias_found = 0
    needs_image = 0

    for normalized, ex_data in progress["all_exercises"].items():
        result = matcher.resolve(ex_data["name"], ex_data.get("imageFileName"))

        if result:
            if result.match_type.value == "exact":
                progress["gap_analysis"][normalized] = "has_image"
                has_image += 1
            else:
                progress["gap_analysis"][normalized] = "alias_found"
                alias_found += 1
        else:
            progress["gap_analysis"][normalized] = "needs_image"
            needs_image += 1

    save_progress(progress)

    print(f"  Has image:     {has_image}")
    print(f"  Alias found:   {alias_found} (fuzzy match, will auto-alias)")
    print(f"  Needs image:   {needs_image}")


def phase3_generate_images(
    progress: dict,
    bfl_key: str,
    gemini_key: str | None = None,
    dry_run: bool = False,
    limit: int | None = None,
):
    """Phase 3: Generate images for exercises that need them."""
    from generate_exercise_images import generate_image, generate_end_frame, generate_end_frame_kontext, save_image, RATE_LIMIT_DELAY

    # Set up Gemini QA if key available
    qa_client = None
    if gemini_key:
        try:
            from google import genai
            from qa_exercise_images import analyze_image
            qa_client = genai.Client(api_key=gemini_key)
            print("  Gemini QA enabled")
        except ImportError:
            print("  Warning: google-genai not installed, skipping QA")
    else:
        print("  Gemini QA disabled (no --gemini-key)")

    needs_image = [
        (k, v) for k, v in progress["all_exercises"].items()
        if progress["gap_analysis"].get(k) == "needs_image"
        and k not in progress["generated_images"]
        and k not in progress["failed_images"]
    ]

    if limit:
        needs_image = needs_image[:limit]

    print(f"\n{'='*60}")
    print(f"Phase 3: Generating {len(needs_image)} images")
    print(f"{'='*60}")

    if not needs_image:
        print("  Nothing to generate!")
        return

    # Load existing mapping
    with open(MAPPING_FILE) as f:
        mapping = json.load(f)

    generated = 0
    failed = 0

    for i, (normalized, ex_data) in enumerate(needs_image):
        name = ex_data["name"]
        print(f"  [{i+1}/{len(needs_image)}] {name}...", end=" ", flush=True)

        if dry_run:
            print("(dry run)")
            continue

        # Build exercise dict for generate_image()
        exercise = {
            "name": name,
            "normalized_filename": normalized,
            "category": ex_data.get("category", "general"),
            "target_area": ex_data.get("targetArea", "General"),
            "body_position": ex_data.get("bodyPosition", "standing"),
            "pose_description": ex_data.get("startPoseDescription", ""),
        }

        # Generate start image
        try:
            image_bytes = generate_image(None, exercise, api_key=bfl_key, model="flux2-pro")
            if image_bytes:
                output_path = OUTPUT_DIR / f"{normalized}.png"
                save_image(image_bytes, output_path)

                # QA check on start image
                if qa_client and output_path.exists():
                    qa_result = analyze_image(qa_client, output_path, exercise)
                    if not qa_result.overall_pass:
                        print(f"QA failed ({', '.join(qa_result.critical_failures)}), retrying...", end=" ", flush=True)
                        time.sleep(8)
                        retry_bytes = generate_image(None, exercise, api_key=bfl_key, model="flux2-pro", seed_offset=1000)
                        if retry_bytes:
                            save_image(retry_bytes, output_path)
                            qa_retry = analyze_image(qa_client, output_path, exercise)
                            if not qa_retry.overall_pass:
                                print(f"QA retry failed, keeping anyway.", end=" ", flush=True)

                # Update mapping
                mapping[normalized] = {
                    "name": name,
                    "filename": f"{normalized}.png",
                    "category": ex_data.get("category", "general"),
                    "target_area": ex_data.get("targetArea", "General"),
                }

                # Generate end image using tiered approach:
                # Tier 1: Matched-template FLUX 2 Pro
                # Tier 2: Kontext Pro with failure-specific prompts (if Tier 1 fails QA)
                end_desc = ex_data.get("endPoseDescription")
                if end_desc and output_path.exists():
                    time.sleep(RATE_LIMIT_DELAY)
                    end_path = OUTPUT_DIR / f"{normalized}_end.png"

                    # Tier 1: Matched-template
                    end_bytes = generate_end_frame(
                        exercise, output_path,
                        api_key=bfl_key,
                        end_pose_description=end_desc,
                    )
                    end_ok = False
                    if end_bytes:
                        save_image(end_bytes, end_path)

                        # Inline consistency QA if Gemini key available
                        if gemini_key and end_path.exists():
                            from qa_consistency import analyze_consistency_quick
                            cqa = analyze_consistency_quick(gemini_key, output_path, end_path, exercise)
                            if cqa.overall_pass:
                                end_ok = True
                                print(f"✓ QA pass (avg={cqa.overall_consistency_score})", end=" ", flush=True)
                            else:
                                # Tier 2: Kontext Pro with failure context
                                print(f"QA fail ({', '.join(cqa.critical_failures)}), tier2...", end=" ", flush=True)
                                time.sleep(RATE_LIMIT_DELAY)
                                t2_bytes = generate_end_frame_kontext(
                                    exercise, output_path,
                                    api_key=bfl_key,
                                    end_pose_description=end_desc,
                                    failed_checks=cqa.critical_failures,
                                    moving_part=ex_data.get("movingPart", ""),
                                    anchored_parts=ex_data.get("anchoredParts", ""),
                                    equipment=ex_data.get("equipment", ""),
                                )
                                if t2_bytes:
                                    save_image(t2_bytes, end_path)
                                    cqa2 = analyze_consistency_quick(gemini_key, output_path, end_path, exercise)
                                    if cqa2.overall_pass:
                                        end_ok = True
                                        print(f"✓ tier2 pass (avg={cqa2.overall_consistency_score})", end=" ", flush=True)
                                    else:
                                        print(f"tier2 fail too", end=" ", flush=True)
                        else:
                            end_ok = True  # No QA available, assume OK

                    if end_ok:
                        mapping[normalized]["end_filename"] = f"{normalized}_end.png"
                        print(f"✓ (start + end)", flush=True)
                    else:
                        print(f"✓ (start only, end needs review)", flush=True)
                else:
                    print(f"✓ (start only)", flush=True)

                progress["generated_images"].append(normalized)
                generated += 1
            else:
                print("✗ (generation failed)")
                progress["failed_images"].append(normalized)
                failed += 1
        except Exception as e:
            print(f"✗ ({e})")
            progress["failed_images"].append(normalized)
            failed += 1

        save_progress(progress)

        # Save mapping periodically
        if generated % 10 == 0:
            with open(MAPPING_FILE, "w") as f:
                json.dump(mapping, f, indent=2)

    # Final save
    with open(MAPPING_FILE, "w") as f:
        json.dump(mapping, f, indent=2)

    # Copy to iOS bundle
    if IOS_MAPPING_FILE.parent.exists():
        with open(IOS_MAPPING_FILE, "w") as f:
            json.dump(mapping, f, indent=2)
        print(f"  Updated iOS mapping at {IOS_MAPPING_FILE}")

    print(f"\nPhase 3 complete: {generated} generated, {failed} failed")


def print_summary(progress: dict):
    """Print a summary of the stockpiling run."""
    print(f"\n{'='*60}")
    print(f"STOCKPILE SUMMARY")
    print(f"{'='*60}")
    print(f"  Conditions processed: {len(progress['completed_conditions'])}")
    print(f"  Unique exercises found: {len(progress['all_exercises'])}")

    gap = progress.get("gap_analysis", {})
    print(f"  Has image: {sum(1 for v in gap.values() if v == 'has_image')}")
    print(f"  Alias found: {sum(1 for v in gap.values() if v == 'alias_found')}")
    print(f"  Needs image: {sum(1 for v in gap.values() if v == 'needs_image')}")
    print(f"  Generated: {len(progress.get('generated_images', []))}")
    print(f"  Failed: {len(progress.get('failed_images', []))}")
    print(f"  Started: {progress.get('started_at', 'N/A')}")
    print(f"  Last updated: {progress.get('last_updated', 'N/A')}")


def main():
    parser = argparse.ArgumentParser(description="Stockpile exercise images")
    parser.add_argument("--anthropic-key", help="Anthropic API key (for plan generation)")
    parser.add_argument("--bfl-key", help="BFL API key (for image generation)")
    parser.add_argument("--gemini-key", help="Gemini API key (for QA)")
    parser.add_argument("--dry-run", action="store_true", help="Preview without API calls")
    parser.add_argument("--resume", action="store_true", help="Resume from previous progress")
    parser.add_argument("--plans-only", action="store_true", help="Only generate plans, skip images")
    parser.add_argument("--images-only", action="store_true", help="Only generate images from existing progress")
    parser.add_argument("--limit", type=int, help="Max images to generate")
    parser.add_argument("--summary", action="store_true", help="Print summary of progress file")
    args = parser.parse_args()

    OUTPUT_DIR.mkdir(exist_ok=True)

    # Load or create progress
    if args.resume or args.images_only or args.summary:
        progress = load_progress()
        if not progress.get("all_exercises"):
            print("No previous progress found. Run without --resume first.")
            if not args.summary:
                sys.exit(1)
    else:
        progress = load_progress() if PROGRESS_FILE.exists() and args.resume else {
            "completed_conditions": [],
            "all_exercises": {},
            "gap_analysis": {},
            "generated_images": [],
            "failed_images": [],
            "started_at": datetime.now().isoformat(),
            "last_updated": datetime.now().isoformat(),
        }

    if args.summary:
        print_summary(progress)
        return

    # Phase 1: Generate plans
    if not args.images_only:
        if not args.anthropic_key:
            print("Error: --anthropic-key required for plan generation")
            sys.exit(1)
        phase1_generate_plans(progress, args.anthropic_key, dry_run=args.dry_run)

    # Phase 2: Gap analysis
    if progress["all_exercises"]:
        phase2_gap_analysis(progress)

    # Phase 3: Generate images
    if not args.plans_only and not args.dry_run:
        if not args.bfl_key:
            print("Skipping image generation (no --bfl-key)")
        else:
            phase3_generate_images(
                progress,
                args.bfl_key,
                args.gemini_key,
                dry_run=args.dry_run,
                limit=args.limit,
            )

    print_summary(progress)


if __name__ == "__main__":
    main()
