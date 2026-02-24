#!/usr/bin/env python3
"""
Generate PT exercise illustration images using Google Gemini (Nano Banana Pro).

Usage:
    python generate_exercise_images.py --api-key YOUR_GOOGLE_AI_STUDIO_KEY
    python generate_exercise_images.py --api-key YOUR_KEY --dry-run
    python generate_exercise_images.py --api-key YOUR_KEY --skip-existing
    python generate_exercise_images.py --api-key YOUR_KEY --start-from 50

Prerequisites:
    pip install google-genai Pillow
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

try:
    from google import genai
    from google.genai import types
except ImportError:
    print("ERROR: google-genai package not installed.")
    print("Run: pip install google-genai Pillow")
    sys.exit(1)

try:
    from PIL import Image
    import io
except ImportError:
    print("ERROR: Pillow package not installed.")
    print("Run: pip install Pillow")
    sys.exit(1)

# ---------- Constants ----------

SCRIPT_DIR = Path(__file__).parent
EXERCISE_LIST_PATH = SCRIPT_DIR / "exercise_list.json"
OUTPUT_DIR = SCRIPT_DIR / "output"
MAPPING_FILE = OUTPUT_DIR / "exercise_image_mapping.json"

# Gemini model that supports image generation
# Options: "gemini-2.5-flash-image" (free, fast) or "gemini-3-pro-image-preview" (Nano Banana Pro)
MODEL_NAME = "gemini-2.5-flash-image"

# Rate limit: Google AI Studio free tier allows ~15 RPM for image generation
RATE_LIMIT_DELAY = 5  # seconds between requests

STYLE_PROMPT = (
    "Create a clean, simple line drawing illustration suitable for a physical therapy "
    "instruction manual. The drawing should show a single person demonstrating the exercise "
    "on a plain white background. Use clean black outlines with minimal shading. "
    "The person should be shown in a neutral, anatomical style (not cartoon). "
    "Include subtle arrows or motion lines to indicate the direction of movement. "
    "The illustration should be clear enough that a beginner with no exercise experience "
    "can understand the body position and movement. "
    "Do NOT include any text, labels, or watermarks in the image."
)


def load_exercise_list() -> list[dict]:
    """Load the exercise list JSON file."""
    with open(EXERCISE_LIST_PATH, "r") as f:
        data = json.load(f)
    return data["exercises"]


def generate_image(client, exercise: dict, dry_run: bool = False) -> bytes | None:
    """Generate an illustration for one exercise using Gemini image generation."""
    name = exercise["name"]
    category = exercise["category"]
    target_area = exercise["target_area"]

    prompt = (
        f"{STYLE_PROMPT}\n\n"
        f"Exercise: {name}\n"
        f"Category: {category}\n"
        f"Target body area: {target_area}\n"
        f"Show the person in the primary position of this exercise."
    )

    if dry_run:
        print(f"  [DRY RUN] Would generate image for: {name}")
        return None

    max_retries = 3
    for attempt in range(max_retries):
        try:
            response = client.models.generate_content(
                model=MODEL_NAME,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_modalities=["TEXT", "IMAGE"],
                ),
            )

            # Check for empty/blocked response
            if not response.candidates:
                reason = getattr(response, 'prompt_feedback', 'unknown')
                print(f"  WARNING: No candidates for {name} (blocked? {reason}), retry {attempt + 1}/{max_retries}")
                time.sleep(5)
                continue

            candidate = response.candidates[0]
            if not candidate.content or not candidate.content.parts:
                finish = getattr(candidate, 'finish_reason', 'unknown')
                print(f"  WARNING: Empty content for {name} (finish_reason={finish}), retry {attempt + 1}/{max_retries}")
                time.sleep(5)
                continue

            # Extract image from response parts
            for part in candidate.content.parts:
                if part.inline_data and part.inline_data.mime_type.startswith("image/"):
                    return part.inline_data.data

            print(f"  WARNING: Response had no image data for {name}, retry {attempt + 1}/{max_retries}")
            time.sleep(5)
            continue

        except Exception as e:
            error_str = str(e)
            if "429" in error_str or "RESOURCE_EXHAUSTED" in error_str:
                wait = 60 if attempt < max_retries - 1 else 0
                if wait:
                    print(f"  RATE LIMITED on {name}, waiting {wait}s... (retry {attempt + 1}/{max_retries})")
                    time.sleep(wait)
                    continue
            print(f"  ERROR generating {name}: {e}")
            if attempt < max_retries - 1:
                time.sleep(5)
                continue
            return None

    print(f"  FAILED after {max_retries} retries for {name}")
    return None


def save_image(image_data: bytes, filepath: Path) -> bool:
    """Save image data as a PNG file, resizing to a consistent 512x512."""
    try:
        img = Image.open(io.BytesIO(image_data))
        # Resize to consistent dimensions
        img = img.resize((512, 512), Image.Resampling.LANCZOS)
        # Convert to RGB if needed (remove alpha channel for smaller PNGs)
        if img.mode == "RGBA":
            background = Image.new("RGB", img.size, (255, 255, 255))
            background.paste(img, mask=img.split()[3])
            img = background
        elif img.mode != "RGB":
            img = img.convert("RGB")
        img.save(filepath, "PNG", optimize=True)
        return True
    except Exception as e:
        print(f"  ERROR saving image: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Generate PT exercise illustrations using Google Gemini"
    )
    parser.add_argument(
        "--api-key",
        required=True,
        help="Google AI Studio API key",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be generated without making API calls",
    )
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip exercises that already have generated images",
    )
    parser.add_argument(
        "--start-from",
        type=int,
        default=0,
        help="Start from exercise index N (0-based)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Limit number of images to generate (0 = no limit, useful for daily quota)",
    )
    args = parser.parse_args()

    # Initialize Gemini client
    client = genai.Client(api_key=args.api_key)

    # Load exercises
    exercises = load_exercise_list()
    print(f"Loaded {len(exercises)} exercises from {EXERCISE_LIST_PATH}")

    # Ensure output directory exists
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Load existing mapping if present
    mapping = {}
    if MAPPING_FILE.exists():
        with open(MAPPING_FILE, "r") as f:
            mapping = json.load(f)

    # Process exercises
    generated_count = 0
    skipped_count = 0
    error_count = 0

    exercises_to_process = exercises[args.start_from:]
    total = len(exercises_to_process)

    print(f"\nProcessing {total} exercises (starting from index {args.start_from})...")
    if args.limit > 0:
        print(f"Limiting to {args.limit} images (daily quota management)")
    print()

    for i, exercise in enumerate(exercises_to_process):
        if args.limit > 0 and generated_count >= args.limit:
            print(f"\nReached limit of {args.limit} images. Run again tomorrow to continue.")
            print(f"Resume with: --start-from {args.start_from + i}")
            break

        name = exercise["name"]
        filename = exercise["normalized_filename"]
        filepath = OUTPUT_DIR / f"{filename}.png"

        print(f"[{i + 1}/{total}] {name}", end="")

        # Skip if already exists
        if args.skip_existing and filepath.exists():
            print(" — SKIPPED (already exists)")
            skipped_count += 1
            # Ensure it's in the mapping
            mapping[filename] = {
                "name": name,
                "filename": f"{filename}.png",
                "category": exercise["category"],
                "target_area": exercise["target_area"],
            }
            continue

        # Generate image
        image_data = generate_image(client, exercise, dry_run=args.dry_run)

        if args.dry_run:
            mapping[filename] = {
                "name": name,
                "filename": f"{filename}.png",
                "category": exercise["category"],
                "target_area": exercise["target_area"],
            }
            generated_count += 1
            continue

        if image_data:
            if save_image(image_data, filepath):
                file_size = filepath.stat().st_size / 1024
                print(f" — OK ({file_size:.0f} KB)")
                mapping[filename] = {
                    "name": name,
                    "filename": f"{filename}.png",
                    "category": exercise["category"],
                    "target_area": exercise["target_area"],
                }
                generated_count += 1
            else:
                print(" — SAVE ERROR")
                error_count += 1
        else:
            print(" — GENERATION ERROR")
            error_count += 1

        # Save mapping after each successful generation (crash-safe)
        with open(MAPPING_FILE, "w") as f:
            json.dump(mapping, f, indent=2)

        # Rate limiting
        if i < total - 1:
            time.sleep(RATE_LIMIT_DELAY)

    # Final mapping save
    with open(MAPPING_FILE, "w") as f:
        json.dump(mapping, f, indent=2)

    # Summary
    print(f"\n{'=' * 50}")
    print(f"SUMMARY")
    print(f"{'=' * 50}")
    print(f"Generated: {generated_count}")
    print(f"Skipped:   {skipped_count}")
    print(f"Errors:    {error_count}")
    print(f"Total in mapping: {len(mapping)}")
    print(f"\nMapping saved to: {MAPPING_FILE}")
    print(f"Images saved to:  {OUTPUT_DIR}/")

    if generated_count > 0 and not args.dry_run:
        print(f"\nNext steps:")
        print(f"  1. Review generated images in {OUTPUT_DIR}/")
        print(f"  2. Run upload_to_firebase.sh to upload to Firebase Storage")
        print(f"  3. Copy {MAPPING_FILE.name} to ios/PT-Helper/PT-Helper/Resources/")


if __name__ == "__main__":
    main()
