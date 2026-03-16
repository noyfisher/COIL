#!/usr/bin/env python3
"""
Generate PT exercise illustration images using FLUX Kontext Pro.

Single-step text-to-image pipeline that generates clean fitness illustrations
of a consistent human figure performing each exercise with correct form.

Usage:
    python generate_exercise_images.py --api-key YOUR_BFL_API_KEY
    python generate_exercise_images.py --api-key YOUR_KEY --dry-run
    python generate_exercise_images.py --api-key YOUR_KEY --skip-existing
    python generate_exercise_images.py --api-key YOUR_KEY --start-from 50
    python generate_exercise_images.py --api-key YOUR_KEY --filter-position supine,prone
    python generate_exercise_images.py --api-key YOUR_KEY --filter-name quad-sets,bird-dog

Prerequisites:
    pip install requests Pillow
"""

import argparse
import json
import sys
import time
from io import BytesIO
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: requests package not installed.")
    print("Run: pip install requests Pillow")
    sys.exit(1)

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow package not installed.")
    print("Run: pip install Pillow")
    sys.exit(1)

# ---------- Constants ----------

SCRIPT_DIR = Path(__file__).parent
EXERCISE_LIST_PATH = SCRIPT_DIR / "exercise_list.json"
OUTPUT_DIR = SCRIPT_DIR / "output"
MAPPING_FILE = OUTPUT_DIR / "exercise_image_mapping.json"

# BFL API
BFL_API_URLS = {
    "kontext-pro": "https://api.bfl.ai/v1/flux-kontext-pro",
    "flux2-pro": "https://api.bfl.ai/v1/flux-2-pro",
}
BFL_POLL_INTERVAL = 1.5  # seconds between status polls

# BFL allows 24 concurrent requests -- keep a small delay between submissions
RATE_LIMIT_DELAY = 8  # seconds between requests

# Image output
OUTPUT_SIZE = 1024  # 1024x1024 pixels

# ---------------------------------------------------------------------------
# Character description -- consistent human figure across all images
# ---------------------------------------------------------------------------
CHARACTER_DESC = (
    "an athletic young man in his late 20s with short dark hair and a lean, "
    "fit build. He is wearing a fitted light gray athletic t-shirt, dark navy "
    "compression shorts, white ankle socks, and gray athletic sneakers"
)

# ---------------------------------------------------------------------------
# Viewing angle heuristics
# ---------------------------------------------------------------------------
_SIDE_KEYWORDS = [
    "squat", "lunge", "deadlift", "plank", "push-up", "pushup",
    "bird dog", "cat-cow", "bridge", "superman", "step-up",
    "heel slide", "leg raise", "hamstring curl", "calf raise",
    "wall sit", "prone", "quadruped", "child", "cobra", "pike",
    "mountain climber", "burpee", "hip hinge", "good morning",
]
_THREE_QUARTER_KEYWORDS = [
    "row", "press", "curl", "extension", "rotation",
    "fly", "raise", "pull", "swing", "chop", "kickback",
    "woodchop", "farmer", "carry", "snatch", "clean",
]
_FRONT_KEYWORDS = [
    "stretch", "standing", "balance", "abduction", "adduction",
    "clamshell", "fire hydrant", "monster walk", "band walk",
    "shoulder shrug", "neck", "wrist", "hand", "finger",
    "ankle alphabet", "ankle circle", "jumping jack",
]


def _get_viewing_angle(name: str) -> str:
    """Pick the camera angle that best shows the exercise form."""
    lower = name.lower()
    if any(kw in lower for kw in _SIDE_KEYWORDS):
        return "side profile"
    if any(kw in lower for kw in _THREE_QUARTER_KEYWORDS):
        return "three-quarter (45-degree)"
    if any(kw in lower for kw in _FRONT_KEYWORDS):
        return "front-facing"
    return "three-quarter (45-degree)"


# ---------------------------------------------------------------------------
# Exercise list helpers
# ---------------------------------------------------------------------------
def load_exercise_list() -> list[dict]:
    """Load the exercise list JSON file."""
    with open(EXERCISE_LIST_PATH, "r") as f:
        return json.load(f)["exercises"]


# ---------------------------------------------------------------------------
# Body position primers -- tell FLUX the fundamental orientation FIRST
# so it doesn't default to standing for everything.
# ---------------------------------------------------------------------------
_BODY_POSITION_PRIMERS = {
    "supine": "He is lying flat on his back on the ground. He is NOT standing.",
    "prone": "His stomach and chest are flat on the floor. His back faces the ceiling. The camera sees his back, not his face. He is in a belly-down position on the ground. Do NOT show him on his back. Do NOT show him standing.",
    "side_lying": "He is lying on his side on the ground. He is NOT standing.",
    "quadruped": "He is down on the ground on all fours — both hands and both knees touching the floor in a tabletop position. He is NOT standing.",
    "standing": "He is standing upright.",
    "seated": "He is seated, sitting down. He is NOT standing.",
    "kneeling": "He is down on the ground, kneeling. He is NOT standing.",
    "foam_roller": "He is down on the ground with a cylindrical foam roller. He is NOT standing.",
    "wall_sit": "He is in a wall sit — back flat against a wall, knees bent at 90 degrees, thighs parallel to the floor. He is NOT standing upright.",
}


# ---------------------------------------------------------------------------
# Prompt builder
# ---------------------------------------------------------------------------
def _build_prompt(exercise: dict) -> str:
    """
    Build the generation prompt for a single exercise illustration.
    Produces a consistent human figure performing the exercise with correct form.

    Prompt structure (order matters for FLUX attention):
    1. Body position context FIRST (most important for non-standing)
    2. Character description
    3. Pose details
    4. Camera angle + style
    """
    name = exercise["name"]
    angle = _get_viewing_angle(name)
    body_pos = exercise.get("body_position", "")

    # Body position primer — sets the fundamental orientation before details
    primer = _BODY_POSITION_PRIMERS.get(body_pos, "")

    # Use pose_description if available, otherwise fall back to generic
    pose_desc = exercise.get("pose_description", "")
    if pose_desc:
        pose_line = pose_desc
    else:
        category = exercise.get("category", "general")
        target_area = exercise.get("target_area", "General")
        pose_line = (
            f"This is a {category} exercise targeting the {target_area}. "
            f"Show the primary position with proper form and controlled positioning."
        )

    # For non-standing positions, lead with body position context
    # so FLUX prioritizes the orientation over the character description
    if body_pos and body_pos != "standing":
        return (
            f"{primer} "
            f"A clean, professional fitness illustration of {CHARACTER_DESC} "
            f"doing the exercise '{name}'. "
            f"{pose_line} "
            f"Camera angle: {angle}. "
            f"Simple clean digital illustration style with soft even lighting, "
            f"plain white background, full body visible from head to toe. "
            f"No text, no labels, no watermarks, no background elements."
        )

    return (
        f"A clean, professional fitness illustration showing {CHARACTER_DESC} "
        f"doing the exercise '{name}'. "
        f"{primer} "
        f"{pose_line} "
        f"Camera angle: {angle}. "
        f"Simple clean digital illustration style with soft even lighting, "
        f"plain white background, full body visible from head to toe. "
        f"No text, no labels, no watermarks, no background elements."
    )


# ---------------------------------------------------------------------------
# FLUX 2 Pro structured JSON prompt builder
# ---------------------------------------------------------------------------
_FLUX2_BODY_POSITIONS = {
    "supine": "lying flat on his back on the ground, face up, back touching the floor",
    "prone": "lying flat on his stomach on the ground, face down, chest and belly pressing into the floor, back facing up toward camera",
    "side_lying": "lying on his side on the ground",
    "quadruped": "on all fours with both hands and both knees on the floor in a tabletop position",
    "standing": "standing upright",
    "seated": "seated, sitting down",
    "kneeling": "kneeling on the ground",
    "foam_roller": "on the ground with a cylindrical foam roller",
    "wall_sit": "in a wall sit with back flat against a wall, knees bent at 90 degrees",
}


# ---------------------------------------------------------------------------
# Custom visual-only prompt overrides for exercises that FLUX misinterprets.
# These describe ONLY what the camera sees — no exercise names.
# ---------------------------------------------------------------------------
_CUSTOM_VISUAL_PROMPTS = {
    "resistance-band-ankle-inversion": {
        "description": (
            "Standing upright on his left foot. A resistance band is looped "
            "around the inside of his right forefoot and anchored to a fixed point "
            "on his right side at floor level. His right foot turns inward toward "
            "the midline of his body against the band resistance. His right lower "
            "leg is stationary, only the foot rotates inward at the ankle."
        ),
        "angle": "front-facing",
    },
    "standing-hip-abduction": {
        "description": (
            "Standing upright on both feet. His left hand lightly touches a wall "
            "for balance. He is lifting his right leg straight out to the side, "
            "about 35 degrees from the ground, with his right knee completely "
            "straight and toes pointing forward. His left standing leg is locked "
            "straight. His torso is completely vertical. He is standing, NOT "
            "sitting. Both feet were on the ground, now the right foot is in the air."
        ),
        "angle": "front-facing",
    },
    "standing-hip-adduction": {
        "description": (
            "Standing upright on his left leg. His left hand touches a wall for "
            "balance. His right leg is straight and swinging across the front of "
            "his body, crossing past his left standing leg toward the left side. "
            "His torso is upright and vertical. He is standing, NOT sitting."
        ),
        "angle": "front-facing",
    },
    "piriformis-stretch": {
        "description": (
            "Sitting on the floor. His left leg is extended straight forward. "
            "His right ankle rests on top of his left knee, creating a figure-four "
            "shape with his legs. His torso leans forward over the crossed right "
            "leg, with both hands on the floor for support. A deep seated hip "
            "stretch position, NOT a hamstring stretch."
        ),
        "angle": "three-quarter (45-degree)",
    },
    "fire-hydrants": {
        "description": (
            "On hands and knees in a tabletop position on the floor. His hands "
            "are directly under his shoulders and his knees under his hips. His "
            "right knee is bent at 90 degrees and lifted out to the side, opening "
            "the hip, raised to approximately hip height. His spine is neutral and "
            "flat like a table."
        ),
        "angle": "three-quarter (45-degree)",
    },
    "prone-knee-flexion": {
        "description": (
            "Lying face down flat on the floor with his chest and hips pressed "
            "against the ground. His arms are folded under his forehead. His left "
            "leg is straight. His right knee is bending, bringing his right heel "
            "up toward his buttock. His right thigh stays flat on the floor."
        ),
        "angle": "side profile",
    },
    "neck-rotations": {
        "description": (
            "Standing upright with relaxed shoulders. His head is turned to the "
            "right, with his chin approaching his right shoulder. His shoulders "
            "remain still and level. A smooth rotation of just the head and neck."
        ),
        "angle": "front-facing",
    },
    "toe-raises": {
        "description": (
            "Standing upright with feet hip-width apart, lightly touching a wall "
            "with one hand for balance. The front half of both feet — his toes "
            "and forefoot — are lifted UP off the ground, pointing upward. ONLY "
            "his heels remain on the floor. This is the OPPOSITE of a calf raise. "
            "His toes point toward the ceiling, heels stay down."
        ),
        "angle": "side profile",
    },
    "soleus-stretch": {
        "description": (
            "Standing facing a wall with both hands placed flat on the wall at "
            "shoulder height. His feet are in a staggered stance — left foot "
            "forward, right foot about two feet behind. Both knees are bent, "
            "especially the back right knee, while the right heel stays on the "
            "floor. His torso leans slightly forward toward the wall."
        ),
        "angle": "side profile",
    },
    "reverse-wrist-curls": {
        "description": (
            "Seated on a chair with his right forearm resting flat on his right "
            "thigh. His palm faces DOWN toward the floor, gripping a small light "
            "dumbbell. His wrist bends upward, lifting the BACK of his hand "
            "toward the ceiling. His forearm does NOT move — it stays flat on "
            "his thigh. This is NOT a bicep curl. The arm does not bend at the "
            "elbow. Only the wrist moves."
        ),
        "angle": "three-quarter (45-degree)",
    },
    "resisted-ankle-plantarflexion": {
        "description": (
            "Standing upright. A resistance band is looped around the ball of "
            "his right foot and held taut in both hands in front of him. His "
            "right foot pushes downward against the band, pointing his toes "
            "toward the floor. His right lower leg stays straight. The movement "
            "is only at the ankle joint — the foot points down against resistance."
        ),
        "angle": "side profile",
    },
    "standing-chest-fly-with-band": {
        "description": (
            "Standing upright. A resistance band is anchored to a door or post "
            "behind him at chest height. He holds one end of the band in each "
            "hand. His arms are extended out to the sides at shoulder height with "
            "a slight bend in the elbows, and are sweeping forward in an arc, "
            "bringing his hands together in front of his chest."
        ),
        "angle": "front-facing",
    },
    "lying-hip-flexor-stretch": {
        "description": (
            "Lying on his back on the floor. His left knee is pulled up to his "
            "chest and held with both hands. His right leg extends straight down "
            "along the floor with the thigh resting on the ground, stretching "
            "the front of his right hip. His lower back is flat on the floor. "
            "No furniture, no bench, no table — just the floor."
        ),
        "angle": "side profile",
    },
    "supine-iliopsoas-stretch": {
        "description": (
            "Lying flat on his back on the floor, face up. His left knee is "
            "pulled up to his chest and held tightly with both hands clasped "
            "around the shin. His right leg is completely straight and resting "
            "flat on the floor, extended out. His lower back is pressed flat "
            "against the floor. He is on the floor, NOT on a table or bench."
        ),
        "angle": "side profile",
    },
}


def _build_flux2_prompt(exercise: dict) -> str:
    """
    Build a JSON-structured prompt for FLUX 2 Pro.
    Uses structured fields for precise pose and camera control.
    For stubborn exercises, uses custom visual-only prompts that describe
    exactly what the camera sees without mentioning exercise names.
    """
    import json as _json

    name = exercise["name"]
    filename = exercise.get("normalized_filename", "")
    body_pos = exercise.get("body_position", "standing")
    position_desc = _FLUX2_BODY_POSITIONS.get(body_pos, "standing upright")

    # Check for custom visual-only prompt override
    custom = _CUSTOM_VISUAL_PROMPTS.get(filename)
    if custom:
        angle = custom.get("angle", _get_viewing_angle(name))
        subject_desc = (
            f"Short dark hair, lean fit build, wearing fitted light gray "
            f"athletic t-shirt, dark navy compression shorts, white ankle "
            f"socks, and gray athletic sneakers. "
            f"{custom['description']}"
        )
    else:
        angle = _get_viewing_angle(name)
        pose_desc = exercise.get("pose_description", "")
        if not pose_desc:
            category = exercise.get("category", "general")
            target_area = exercise.get("target_area", "General")
            pose_desc = (
                f"Performing a {category} exercise targeting the {target_area} "
                f"with proper form and controlled positioning."
            )
        subject_desc = (
            f"Short dark hair, lean fit build, wearing fitted light gray "
            f"athletic t-shirt, dark navy compression shorts, white ankle "
            f"socks, and gray athletic sneakers. "
            f"Body position: {position_desc}. "
            f"Exercise: {name}. {pose_desc}"
        )

    prompt_obj = {
        "scene": "Clean fitness studio with plain white background, no furniture, no equipment except what is described",
        "subjects": [
            {
                "type": "athletic young man",
                "description": subject_desc,
                "position": "centered, full body visible from head to toe",
            }
        ],
        "style": "Clean professional fitness illustration, digital art, soft even lighting",
        "lighting": "Soft, even studio lighting, no harsh shadows",
        "camera": {
            "angle": angle,
            "lens": "50mm",
            "f-number": "f/5.6",
        },
        "composition": "Single figure centered, full body visible, no text, no labels, no watermarks, no arrows, no annotations",
    }

    return _json.dumps(prompt_obj)


# ---------------------------------------------------------------------------
# Core API call with retries and polling
# ---------------------------------------------------------------------------
def _call_bfl_api(
    prompt: str,
    api_key: str,
    *,
    seed: int | None = None,
    prompt_upsampling: bool = False,
    label: str = "",
    model: str = "kontext-pro",
) -> bytes | None:
    """
    Submit a text-to-image generation request to BFL and poll for the result.

    Parameters
    ----------
    prompt : The generation prompt.
    api_key : BFL API key.
    seed : Optional seed for reproducibility.
    prompt_upsampling : If False, prevent BFL from auto-expanding the prompt.
    label : Human-readable label for log messages.
    model : "kontext-pro" or "flux2-pro".

    Returns
    -------
    Raw image bytes on success, None on failure.
    """
    api_url = BFL_API_URLS.get(model, BFL_API_URLS["kontext-pro"])

    if model == "flux2-pro":
        payload = {
            "prompt": prompt,
            "width": OUTPUT_SIZE,
            "height": OUTPUT_SIZE,
            "output_format": "png",
            "safety_tolerance": 5,
        }
        if not prompt_upsampling:
            payload["disable_pup"] = True
    else:
        payload = {
            "prompt": prompt,
            "aspect_ratio": "1:1",
            "output_format": "png",
            "safety_tolerance": 6,
            "prompt_upsampling": prompt_upsampling,
        }
    if seed is not None:
        payload["seed"] = seed

    headers = {
        "accept": "application/json",
        "x-key": api_key,
        "Content-Type": "application/json",
    }

    max_retries = 3
    for attempt in range(max_retries):
        try:
            resp = requests.post(
                api_url, headers=headers, json=payload, timeout=30,
            )

            if resp.status_code == 402:
                print(f"  ERROR: Insufficient BFL credits -- add funds at https://dashboard.bfl.ai")
                return None

            if resp.status_code == 429:
                wait = 30 * (attempt + 1)
                print(f"  RATE LIMITED, waiting {wait}s... (retry {attempt + 1}/{max_retries})")
                time.sleep(wait)
                continue

            resp.raise_for_status()
            data = resp.json()

            polling_url = data.get("polling_url")
            if not polling_url:
                rid = data.get("id")
                if rid:
                    polling_url = f"https://api.bfl.ai/v1/get_result?id={rid}"
                else:
                    print(f"  ERROR: No polling URL in API response")
                    continue

            # Poll for completion (max ~3 min)
            for _ in range(120):
                time.sleep(BFL_POLL_INTERVAL)
                poll = requests.get(polling_url, headers=headers, timeout=30).json()
                status = poll.get("status", "Unknown")

                if status == "Ready":
                    img_url = poll.get("result", {}).get("sample")
                    if not img_url:
                        print(f"  ERROR: Ready but no image URL")
                        break
                    img_resp = requests.get(img_url, timeout=60)
                    img_resp.raise_for_status()
                    return img_resp.content

                if status in ("Error", "Failed"):
                    print(f"  ERROR from API: {poll.get('error', status)}")
                    break
            else:
                print(f"  TIMEOUT waiting for {label}")

        except requests.exceptions.RequestException as e:
            print(f"  ERROR: {e}")

        # Retry delay
        if attempt < max_retries - 1:
            time.sleep(5)

    print(f"  FAILED after {max_retries} retries for {label}")
    return None


# ---------------------------------------------------------------------------
# Image generation
# ---------------------------------------------------------------------------
def generate_image(
    _client,
    exercise: dict,
    dry_run: bool = False,
    *,
    api_key: str | None = None,
    reference_base64: str | None = None,
    step: str = "generate",
    seed_offset: int = 0,
    model: str = "kontext-pro",
) -> bytes | None:
    """
    Generate an illustration for one exercise.

    This function is the main public API, also called by process_missing_images.py.

    Parameters
    ----------
    _client : ignored (kept for backward-compat)
    exercise : dict with at least name, normalized_filename, category, target_area
    dry_run : if True, skip the API call
    api_key : BFL API key (keyword-only)
    reference_base64 : ignored (kept for backward-compat signature)
    step : ignored (kept for backward-compat; single-step pipeline)
    seed_offset : added to the deterministic seed to produce different results
    model : "kontext-pro" or "flux2-pro"
    """
    name = exercise["name"]

    # Choose prompt builder based on model
    if model == "flux2-pro":
        prompt = _build_flux2_prompt(exercise)
    else:
        prompt = _build_prompt(exercise)

    if dry_run:
        print(f"  [DRY RUN] Would generate image for: {name} (model={model})")
        print(f"    Prompt: {prompt[:120]}...")
        return None

    if not api_key:
        print("  ERROR: No API key provided")
        return None

    seed = (hash(name) + seed_offset) % (2**32)

    print(f" generating ({model})...", end="", flush=True)
    return _call_bfl_api(
        prompt, api_key,
        seed=seed,
        prompt_upsampling=False,
        label=name,
        model=model,
    )


# ---------------------------------------------------------------------------
# Image saving
# ---------------------------------------------------------------------------
def save_image(image_data: bytes, filepath: Path) -> bool:
    """Save image data as a 1024x1024 optimized PNG."""
    try:
        filepath.parent.mkdir(parents=True, exist_ok=True)
        img = Image.open(BytesIO(image_data))
        img = img.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.Resampling.LANCZOS)
        if img.mode == "RGBA":
            bg = Image.new("RGB", img.size, (255, 255, 255))
            bg.paste(img, mask=img.split()[3])
            img = bg
        elif img.mode != "RGB":
            img = img.convert("RGB")
        img.save(filepath, "PNG", optimize=True)
        return True
    except Exception as e:
        print(f"  ERROR saving image: {e}")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(
        description="Generate PT exercise illustrations using FLUX Kontext Pro"
    )
    parser.add_argument(
        "--api-key", required=True,
        help="BFL (Black Forest Labs) API key -- get one at https://dashboard.bfl.ai",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Print what would be generated without making API calls",
    )
    parser.add_argument(
        "--skip-existing", action="store_true",
        help="Skip exercises that already have generated images on disk",
    )
    parser.add_argument(
        "--start-from", type=int, default=0,
        help="Start from exercise index N (0-based)",
    )
    parser.add_argument(
        "--limit", type=int, default=0,
        help="Max images to generate (0 = no limit)",
    )
    parser.add_argument(
        "--filter-position", type=str, default="",
        help=(
            "Comma-separated list of body_position values to include "
            "(e.g., 'supine,prone,quadruped'). If omitted, all exercises are processed."
        ),
    )
    parser.add_argument(
        "--filter-name", type=str, default="",
        help=(
            "Comma-separated list of normalized filenames to include "
            "(e.g., 'quad-sets,bird-dog'). If omitted, all exercises are processed."
        ),
    )
    parser.add_argument(
        "--seed-offset", type=int, default=0,
        help=(
            "Offset added to each exercise's deterministic seed. Use to regenerate "
            "exercises that produced bad results with a different seed (e.g., --seed-offset 1000)"
        ),
    )
    parser.add_argument(
        "--model", type=str, default="kontext-pro",
        choices=["kontext-pro", "flux2-pro"],
        help=(
            "BFL model to use. 'kontext-pro' (default) uses FLUX Kontext Pro. "
            "'flux2-pro' uses FLUX 2 Pro with structured JSON prompts (better for prone)."
        ),
    )
    # Legacy flag kept for backward compat with process_missing_images.py
    parser.add_argument(
        "--step", default="generate",
        help=argparse.SUPPRESS,
    )
    args = parser.parse_args()

    # --- Exercises ---
    exercises = load_exercise_list()
    print(f"Loaded {len(exercises)} exercises from {EXERCISE_LIST_PATH}")

    # --- Filters ---
    if args.filter_position:
        allowed = set(p.strip() for p in args.filter_position.split(","))
        exercises = [e for e in exercises if e.get("body_position", "") in allowed]
        print(f"Filtered to {len(exercises)} exercises with body_position in: {allowed}")

    if args.filter_name:
        names = set(n.strip() for n in args.filter_name.split(","))
        exercises = [e for e in exercises if e["normalized_filename"] in names]
        print(f"Filtered to {len(exercises)} exercises by name")

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    mapping: dict = {}
    if MAPPING_FILE.exists():
        with open(MAPPING_FILE, "r") as f:
            mapping = json.load(f)

    generated = skipped = errors = 0
    batch = exercises[args.start_from:]
    total = len(batch)

    print(f"\nProcessing {total} exercises (starting from index {args.start_from})...")
    if args.limit > 0:
        print(f"Limiting to {args.limit} images")
    model_label = "FLUX 2 Pro (structured)" if args.model == "flux2-pro" else "FLUX Kontext Pro"
    print(f"Using {model_label}  |  Output: {OUTPUT_SIZE}x{OUTPUT_SIZE}")
    print(f"Output dir: {OUTPUT_DIR}/\n")

    for i, exercise in enumerate(batch):
        if args.limit > 0 and generated >= args.limit:
            print(f"\nReached limit of {args.limit}. Resume with: --start-from {args.start_from + i}")
            break

        name = exercise["name"]
        filename = exercise["normalized_filename"]
        filepath = OUTPUT_DIR / f"{filename}.png"

        print(f"[{i + 1}/{total}] {name}", end="")

        if args.skip_existing and filepath.exists():
            print(" -- SKIPPED (exists)")
            skipped += 1
            mapping[filename] = {
                "name": name,
                "filename": f"{filename}.png",
                "category": exercise.get("category", "general"),
                "target_area": exercise.get("target_area", "General"),
            }
            continue

        image_data = generate_image(
            None, exercise, dry_run=args.dry_run,
            api_key=args.api_key,
            seed_offset=args.seed_offset,
            model=args.model,
        )

        if args.dry_run:
            mapping[filename] = {
                "name": name,
                "filename": f"{filename}.png",
                "category": exercise.get("category", "general"),
                "target_area": exercise.get("target_area", "General"),
            }
            generated += 1
            print()
            continue

        if image_data and save_image(image_data, filepath):
            kb = filepath.stat().st_size / 1024
            print(f" -- OK ({kb:.0f} KB)")
            mapping[filename] = {
                "name": name,
                "filename": f"{filename}.png",
                "category": exercise.get("category", "general"),
                "target_area": exercise.get("target_area", "General"),
            }
            generated += 1
        else:
            print(" -- GENERATION ERROR")
            errors += 1

        # Crash-safe mapping save
        with open(MAPPING_FILE, "w") as f:
            json.dump(mapping, f, indent=2)

        if i < total - 1:
            time.sleep(RATE_LIMIT_DELAY)

    # Final save
    with open(MAPPING_FILE, "w") as f:
        json.dump(mapping, f, indent=2)

    print(f"\n{'=' * 60}")
    print("SUMMARY")
    print(f"{'=' * 60}")
    print(f"Generated: {generated}")
    print(f"Skipped:   {skipped}")
    print(f"Errors:    {errors}")
    print(f"Total in mapping: {len(mapping)}")
    print(f"\nImages: {OUTPUT_DIR}/")
    print(f"Mapping: {MAPPING_FILE}")

    if generated > 0 and not args.dry_run:
        print("\nNext steps:")
        print(f"  1. Review generated images in {OUTPUT_DIR}/")
        print(f"  2. Run upload_to_firebase.sh to upload to Firebase Storage")
        print(f"  3. Copy {MAPPING_FILE.name} to ios/PT-Helper/PT-Helper/Resources/")


if __name__ == "__main__":
    main()
