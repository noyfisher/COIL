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
            "Standing upright on his left leg with his left hand touching a wall "
            "or post for balance. His right leg is completely straight with the "
            "knee locked, and it is crossing ACROSS the front of his left standing "
            "leg toward the left side of his body. His right foot is off the ground, "
            "hovering about 6 inches in the air. His torso is completely vertical "
            "and upright. He is STANDING on one leg, NOT sitting on a chair. "
            "NO chair, NO stool. Just a man standing on one leg with the other "
            "leg crossing in front."
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
            "Standing upright with feet hip-width apart, one hand lightly touching "
            "a wall for balance. His HEELS are flat on the ground. The FRONT of "
            "both feet — all ten toes and the balls of his feet — are lifted UP "
            "off the ground, curling upward toward the ceiling. There is a visible "
            "gap between the front of his feet and the floor. His weight is entirely "
            "on his heels. This is the OPPOSITE of a calf raise — heels DOWN, "
            "toes UP. Think of pulling your toes toward your shins."
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
            "Seated on a bench or chair. His right forearm rests flat along the "
            "top of his right thigh with the wrist hanging just past the kneecap. "
            "He grips a small light dumbbell with his palm facing DOWN (overhand "
            "grip, knuckles on top). His wrist bends upward, raising the back of "
            "his hand toward the ceiling while the forearm stays pinned to the "
            "thigh. His left hand rests on his left knee. This is a WRIST exercise "
            "— the elbow does NOT bend, the arm does NOT lift. Only the wrist "
            "hinges up and down. He is a real human, not a cartoon."
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
    "downward-facing-dog": {
        "description": (
            "His body forms an inverted V shape, like an upside-down letter V. "
            "His hands are flat on the floor shoulder-width apart, arms straight. "
            "His hips are pushed high up toward the ceiling, the highest point of "
            "his body. His legs are straight with heels pressing toward the floor. "
            "His head hangs between his upper arms, looking back toward his feet. "
            "His back is flat and straight from hands to hips. He is NOT on his "
            "knees — his knees are straight and locked. Only his hands and feet "
            "touch the ground."
        ),
        "angle": "side profile",
    },
    "glute-bridges": {
        "description": (
            "Lying flat on his back on the floor, face up. His knees are bent "
            "and his feet are flat on the floor, hip-width apart, about 12 inches "
            "from his buttocks. His arms rest at his sides with palms flat on the "
            "floor. His hips are pushed UP toward the ceiling, lifting his pelvis "
            "off the ground so his body forms a straight line from his shoulders "
            "to his knees. His shoulders and upper back remain on the floor. "
            "His core is tight. This is a glute bridge — a simple floor exercise."
        ),
        "angle": "side profile",
    },
    "childs-pose": {
        "description": (
            "Kneeling on the floor with his knees spread apart and his big toes "
            "touching behind him. He is sitting his hips BACK onto his heels. "
            "His torso folds forward and down, draping over his thighs. His "
            "forehead rests on the floor. Both arms are extended straight forward "
            "on the floor in front of him, palms down, reaching as far ahead as "
            "possible. His back is gently rounded. This is a resting yoga pose, "
            "NOT a quadruped or all-fours position — his hips are back on his heels."
        ),
        "angle": "side profile",
    },
    "standing-quad-stretch": {
        "description": (
            "Standing upright on his left leg. His left hand touches a wall for "
            "balance. His right knee is bent behind him, bringing his right foot "
            "up toward his buttock. He reaches back with his right hand and grabs "
            "his right ankle or foot, pulling it closer to his glute. His right "
            "knee points straight down toward the floor, parallel to his left leg. "
            "His torso is upright and vertical. This is a classic standing "
            "quadricep stretch."
        ),
        "angle": "side profile",
    },
    "childs-pose-with-side-reach": {
        "description": (
            "Kneeling on the floor with his hips sitting BACK on his heels. His "
            "torso folds forward and down over his thighs with his forehead near "
            "the floor. Both arms are extended forward on the floor, but both "
            "hands walk over to the RIGHT side, creating a lateral stretch along "
            "the left side of his torso. His body curves in a gentle C-shape to "
            "the right. His hips stay back on his heels — this is a child's pose "
            "variation, NOT an all-fours position."
        ),
        "angle": "three-quarter (45-degree)",
    },
    "wrist-curls": {
        "description": (
            "Seated on a bench or chair. His right forearm rests flat along the "
            "top of his right thigh with the wrist hanging just past the kneecap. "
            "He grips a small light dumbbell with his palm facing UP (underhand "
            "grip, palm toward the ceiling). His wrist curls upward, bringing "
            "the dumbbell toward his forearm. His left hand rests on his left "
            "knee. This is a WRIST exercise — the elbow does NOT bend, the arm "
            "does NOT lift. Only the wrist hinges up and down. Photo-realistic "
            "style, NOT a cartoon."
        ),
        "angle": "three-quarter (45-degree)",
    },
    "lateral-lunge-with-reach": {
        "description": (
            "Standing with feet wide apart in a lateral side lunge. His right "
            "foot is planted and his right knee is deeply bent, sitting his hips "
            "back over the right foot. His left leg is completely straight, "
            "extended out to his left side with the foot flat on the ground. "
            "His torso leans forward and his left hand reaches down toward his "
            "right foot. This is a SIDE lunge — his feet are spread to the "
            "LEFT and RIGHT, not forward and backward."
        ),
        "angle": "front-facing",
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
    input_image_base64: str | None = None,
) -> bytes | None:
    """
    Submit a generation request to BFL and poll for the result.

    Parameters
    ----------
    prompt : The generation prompt.
    api_key : BFL API key.
    seed : Optional seed for reproducibility.
    prompt_upsampling : If False, prevent BFL from auto-expanding the prompt.
    label : Human-readable label for log messages.
    model : "kontext-pro" or "flux2-pro".
    input_image_base64 : Base64-encoded reference image for image-to-image editing
                         (Kontext Pro only). When provided, the prompt describes
                         edits to apply to this image.

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
        # Image-to-image: pass start frame as reference for Kontext Pro
        if input_image_base64:
            payload["input_image"] = input_image_base64
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


def generate_end_frame(
    exercise: dict,
    start_image_path: Path,
    *,
    api_key: str,
    end_pose_description: str,
    dry_run: bool = False,
    seed_offset: int = 0,
) -> bytes | None:
    """
    Generate an end-position image using matched-template FLUX 2 Pro.

    Uses the SAME structured JSON prompt template as the start frame,
    only changing the pose_description. This guarantees visual consistency
    (same character, camera angle, style, scene) because both frames are
    generated from identical templates.

    This is Tier 1 of the generation strategy.

    Parameters
    ----------
    exercise : dict with name, normalized_filename, etc.
    start_image_path : Path to the start-position PNG (unused in Tier 1,
                       kept for API compat with Tier 2 fallback)
    api_key : BFL API key
    end_pose_description : Text describing the end/peak position
    dry_run : if True, skip the API call
    seed_offset : added to the deterministic seed
    """
    name = exercise["name"]

    if dry_run:
        print(f"  [DRY RUN] Would generate end frame for: {name}")
        return None

    # Build the SAME structured prompt as the start frame,
    # but swap pose_description → end_pose_description
    end_exercise = {**exercise, "pose_description": end_pose_description}
    prompt = _build_flux2_prompt(end_exercise)

    # Use a related but different seed so the character looks similar
    # but the pose actually changes
    seed = (hash(name) + 500 + seed_offset) % (2**32)

    print(f" end-frame (matched-template)...", end="", flush=True)
    return _call_bfl_api(
        prompt, api_key,
        seed=seed,
        prompt_upsampling=False,
        label=f"{name} (end)",
        model="flux2-pro",
    )


def generate_end_frame_kontext(
    exercise: dict,
    start_image_path: Path,
    *,
    api_key: str,
    end_pose_description: str,
    failed_checks: list[str] | None = None,
    moving_part: str = "",
    anchored_parts: str = "",
    equipment: str = "",
    seed_offset: int = 0,
) -> bytes | None:
    """
    Tier 2 fallback: Generate end frame using Kontext Pro image-to-image
    with failure-specific prompts based on which consistency checks failed.

    Only called when Tier 1 (matched-template FLUX 2 Pro) fails QA.

    Parameters
    ----------
    exercise : dict with name, normalized_filename, etc.
    start_image_path : Path to the start-position PNG (used as reference)
    api_key : BFL API key
    end_pose_description : Text describing the end/peak position
    failed_checks : list of consistency check names that failed (e.g., ["BODY_ANCHORING", "MOVEMENT_LOGIC"])
    moving_part : what body part moves (e.g., "right leg")
    anchored_parts : what must NOT move (e.g., "left leg, torso, head")
    equipment : props that must persist (e.g., "resistance band")
    seed_offset : added to the deterministic seed
    """
    import base64

    name = exercise["name"]

    if not start_image_path.exists():
        print(f"  ERROR: Start image not found: {start_image_path}")
        return None

    with open(start_image_path, "rb") as f:
        start_base64 = base64.b64encode(f.read()).decode("utf-8")

    # Build failure-specific prompt
    failed = set(failed_checks or [])

    if "BODY_ANCHORING" in failed and moving_part:
        prompt = (
            f"In this image, ONLY move the {moving_part}. "
            f"The {anchored_parts or 'rest of the body'} must remain in EXACTLY the same position. "
            f"Target pose for {moving_part}: {end_pose_description}"
        )
    elif "SCENE_SETUP" in failed and equipment:
        prompt = (
            f"Keep the exact same scene, background, and equipment. "
            f"The {equipment} must remain visible in the same position. "
            f"Only change the person's pose to: {end_pose_description}"
        )
    elif "MOVEMENT_LOGIC" in failed and moving_part:
        prompt = (
            f"Change ONLY the {moving_part} in this image. "
            f"Move it to: {end_pose_description}. "
            f"Everything else must stay EXACTLY the same — "
            f"same camera angle, same background, same clothing."
        )
    else:
        # Generic fallback
        prompt = (
            f"Change the pose of the person in this image. "
            f"Keep the exact same person, clothing, camera angle, background, and scene. "
            f"Only change the body position to: {end_pose_description} "
            f"This is the end position of the exercise: {name}."
        )

    seed = (hash(name) + 500 + seed_offset) % (2**32)

    print(f" end-frame (kontext-pro tier2)...", end="", flush=True)
    return _call_bfl_api(
        prompt, api_key,
        seed=seed,
        prompt_upsampling=False,
        label=f"{name} (end-t2)",
        model="kontext-pro",
        input_image_base64=start_base64,
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
    parser.add_argument(
        "--generate-end-frames", action="store_true",
        help=(
            "Generate end-position images for exercises that have an "
            "'end_pose_description' field. Saves as {name}_end.png and "
            "adds end_filename to the mapping."
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
            mapping_entry = {
                "name": name,
                "filename": f"{filename}.png",
                "category": exercise.get("category", "general"),
                "target_area": exercise.get("target_area", "General"),
            }

            # Generate end-position frame if requested and description available
            # Uses Kontext Pro image-to-image for visual consistency with start frame
            if args.generate_end_frames and exercise.get("end_pose_description"):
                end_filepath = OUTPUT_DIR / f"{filename}_end.png"
                if not (args.skip_existing and end_filepath.exists()):
                    time.sleep(RATE_LIMIT_DELAY)
                    print(f"     ", end="", flush=True)
                    end_data = generate_end_frame(
                        exercise,
                        filepath,
                        api_key=args.api_key,
                        end_pose_description=exercise["end_pose_description"],
                        seed_offset=args.seed_offset,
                    )
                    if end_data and save_image(end_data, end_filepath):
                        end_kb = end_filepath.stat().st_size / 1024
                        print(f" -- OK ({end_kb:.0f} KB)")
                        mapping_entry["end_filename"] = f"{filename}_end.png"
                    else:
                        print(" -- END FRAME ERROR")
                elif end_filepath.exists():
                    mapping_entry["end_filename"] = f"{filename}_end.png"

            mapping[filename] = mapping_entry
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
        print(f"  3. Copy {MAPPING_FILE.name} to ios/PT-Helper/COIL/Resources/")


if __name__ == "__main__":
    main()
