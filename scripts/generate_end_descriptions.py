#!/usr/bin/env python3
"""
Generate end-position descriptions for exercises that only have start descriptions.

Uses Claude Haiku to generate end-pose descriptions based on the exercise name
and existing start pose_description. Updates exercise_list.json in place.

Seeds from the animation-pilot's END_POSITION_DESCRIPTIONS for exercises that
already have manually written end descriptions.

Usage:
  python generate_end_descriptions.py --api-key <anthropic_key>
  python generate_end_descriptions.py --api-key <key> --limit 10 --dry-run
"""

import argparse
import json
import sys
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
EXERCISE_LIST_PATH = SCRIPT_DIR / "exercise_list.json"

# Pre-written end descriptions from animation-pilot (manually verified)
PILOT_END_DESCRIPTIONS = {
    "wall-slides": {
        "end_pose_description": (
            "Standing with back flat against a wall. Both arms are raised fully "
            "overhead with elbows straight, hands and forearms still touching the "
            "wall. Arms in a Y position above the head. Shoulders fully flexed."
        ),
        "end_viewing_angle": "side profile",
    },
    "standing-hip-abduction": {
        "end_pose_description": (
            "Standing upright on the left leg. The right leg is lifted straight "
            "out to the side at approximately 45 degrees from the body. The right "
            "knee is straight and locked. Torso remains upright, not leaning."
        ),
        "end_viewing_angle": "front-facing",
    },
    "pendulum-swings": {
        "end_pose_description": (
            "Standing next to a table with the left hand resting on it for support. "
            "The upper body is bent forward at the hips at about 45 degrees. "
            "The right arm hangs freely and has swung forward to the front of "
            "its arc, extended in front of the body."
        ),
        "end_viewing_angle": "side profile",
    },
    "bird-dog": {
        "end_pose_description": (
            "On all fours in a tabletop position on the ground. The right arm "
            "is extended fully forward, parallel to the ground. The left leg is "
            "extended fully backward, parallel to the ground. The back is flat "
            "and level. Only the left hand and right knee remain on the ground."
        ),
        "end_viewing_angle": "side profile",
    },
    "clamshells": {
        "end_pose_description": (
            "Lying on the left side on the ground. Both knees are bent at about "
            "45 degrees. Feet are stacked together and remain touching. The top "
            "(right) knee is lifted and opened up toward the ceiling at maximum "
            "abduction, like a clamshell opening."
        ),
        "end_viewing_angle": "front-facing",
    },
    "straight-leg-raises": {
        "end_pose_description": (
            "Lying flat on the back on the ground, face up. The left knee is bent "
            "with foot flat on the floor. The right leg is raised straight up to "
            "approximately 45 degrees from the floor with the knee fully locked."
        ),
        "end_viewing_angle": "side profile",
    },
    "seated-knee-extension": {
        "end_pose_description": (
            "Seated on a chair or bench. The right leg is extended fully forward, "
            "straight and parallel to the floor. The knee is locked. The quadriceps "
            "muscle is visibly engaged. The left foot remains flat on the ground."
        ),
        "end_viewing_angle": "side profile",
    },
    "seated-calf-raises": {
        "end_pose_description": (
            "Seated on a chair with feet on the ground. Both heels are lifted high "
            "off the ground, rising up onto the balls of the feet. The calf muscles "
            "are visibly contracted. Knees are bent at 90 degrees."
        ),
        "end_viewing_angle": "side profile",
    },
    "chin-tucks": {
        "end_pose_description": (
            "Standing upright facing forward. The chin is drawn fully backward "
            "and downward, creating a pronounced double chin. The head is retracted "
            "straight back, not tilted up or down. The neck is elongated at the back."
        ),
        "end_viewing_angle": "side profile",
    },
    "scapular-squeezes": {
        "end_pose_description": (
            "Standing upright. The shoulder blades are squeezed maximally together "
            "behind the back. The chest is pushed forward and open. The shoulders "
            "are pulled back. Both arms are at the sides with elbows slightly bent."
        ),
        "end_viewing_angle": "three-quarter (45-degree)",
    },
}


def generate_end_description(
    exercise: dict, api_key: str
) -> dict | None:
    """Use Claude Haiku to generate an end-pose description for an exercise."""
    import anthropic

    client = anthropic.Anthropic(api_key=api_key)

    name = exercise["name"]
    start_desc = exercise.get("pose_description", "")
    body_pos = exercise.get("body_position", "standing")
    category = exercise.get("category", "general")

    prompt = f"""You are a fitness illustration director. Given an exercise, describe the END position (the peak of the movement) for a fitness illustration.

Exercise: {name}
Category: {category}
Body Position: {body_pos}
Start Position: {start_desc}

Describe EXACTLY what a camera would see at the END/PEAK of this exercise movement. Be specific about:
- Limb positions (angles, straight vs bent)
- Body orientation (relative to ground)
- Which muscles appear engaged
- What direction the person faces

Keep it to 2-3 sentences. Describe visual appearance only — no exercise instructions.

Also specify the best camera angle: "side profile", "front-facing", or "three-quarter (45-degree)".

Return JSON: {{"end_pose_description": "...", "end_viewing_angle": "..."}}"""

    try:
        response = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=300,
            messages=[{"role": "user", "content": prompt}],
        )

        text = response.content[0].text.strip()
        # Extract JSON from response (handle markdown code blocks)
        if "```" in text:
            text = text.split("```")[1]
            if text.startswith("json"):
                text = text[4:]
            text = text.strip()

        return json.loads(text)
    except Exception as e:
        print(f"  Error generating end description for {name}: {e}")
        return None


def main():
    parser = argparse.ArgumentParser(description="Generate end-pose descriptions for exercises")
    parser.add_argument("--api-key", required=True, help="Anthropic API key")
    parser.add_argument("--dry-run", action="store_true", help="Print without saving")
    parser.add_argument("--limit", type=int, help="Max exercises to process")
    parser.add_argument("--filter-name", help="Comma-separated exercise names to process")
    args = parser.parse_args()

    # Load exercise list
    with open(EXERCISE_LIST_PATH) as f:
        data = json.load(f)
    exercises = data["exercises"]

    print(f"Loaded {len(exercises)} exercises from exercise_list.json")

    # Apply pilot descriptions first
    pilot_applied = 0
    for ex in exercises:
        filename = ex.get("normalized_filename", "")
        if filename in PILOT_END_DESCRIPTIONS and not ex.get("end_pose_description"):
            pilot = PILOT_END_DESCRIPTIONS[filename]
            ex["end_pose_description"] = pilot["end_pose_description"]
            ex["end_viewing_angle"] = pilot["end_viewing_angle"]
            pilot_applied += 1

    print(f"Applied {pilot_applied} pilot end descriptions")

    # Filter exercises needing end descriptions
    needs_end = [
        ex for ex in exercises
        if not ex.get("end_pose_description")
    ]

    if args.filter_name:
        names = set(args.filter_name.split(","))
        needs_end = [ex for ex in needs_end if ex.get("normalized_filename") in names]

    if args.limit:
        needs_end = needs_end[:args.limit]

    print(f"{len(needs_end)} exercises need end-pose descriptions")

    if not needs_end:
        if pilot_applied > 0 and not args.dry_run:
            # Save pilot descriptions even if nothing else to generate
            with open(EXERCISE_LIST_PATH, "w") as f:
                json.dump(data, f, indent=2)
            print("Saved pilot descriptions to exercise_list.json")
        return

    # Generate end descriptions
    generated = 0
    for i, ex in enumerate(needs_end):
        name = ex["name"]
        filename = ex.get("normalized_filename", "")
        print(f"  [{i+1}/{len(needs_end)}] {name}...", end=" ", flush=True)

        if args.dry_run:
            print("(dry run)")
            continue

        result = generate_end_description(ex, args.api_key)
        if result and "end_pose_description" in result:
            ex["end_pose_description"] = result["end_pose_description"]
            ex["end_viewing_angle"] = result.get("end_viewing_angle", "side profile")
            generated += 1
            print(f"✓ ({result.get('end_viewing_angle', 'N/A')})")
        else:
            print("✗ (failed)")

        # Rate limit: 1 call per 2 seconds
        time.sleep(2)

    print(f"\nGenerated {generated} end-pose descriptions")

    if not args.dry_run:
        with open(EXERCISE_LIST_PATH, "w") as f:
            json.dump(data, f, indent=2)
        print(f"Saved to {EXERCISE_LIST_PATH}")


if __name__ == "__main__":
    main()
