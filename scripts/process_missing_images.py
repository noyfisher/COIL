#!/usr/bin/env python3
"""
Automated pipeline: Fetch missing exercise images from Firestore,
generate them via FLUX Kontext Pro, upload to Firebase Storage,
and update mappings.

Usage:
    python scripts/process_missing_images.py --keychain --dry-run
    python scripts/process_missing_images.py --keychain --limit 5 --min-count 2
    python scripts/process_missing_images.py --keychain --cleanup-resolved
    python scripts/process_missing_images.py --api-key YOUR_BFL_KEY --dry-run

Prerequisites:
    pip install -r scripts/requirements.txt
    gcloud auth application-default login   (for Firestore + Storage access)

Keychain setup (one-time):
    security add-generic-password -s "BFL_API_KEY" -a "bfl" -w "YOUR_KEY"
"""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = Path(__file__).parent
OUTPUT_DIR = SCRIPT_DIR / "output"
MAPPING_FILE = OUTPUT_DIR / "exercise_image_mapping.json"
IOS_MAPPING_FILE = (
    SCRIPT_DIR.parent
    / "ios"
    / "PT-Helper"
    / "PT-Helper"
    / "Resources"
    / "exercise_image_mapping.json"
)
MASTER_EXERCISE_LIST = SCRIPT_DIR / "exercise_list.json"

# Firebase Storage
BUCKET = "gs://pt-helper-dev.firebasestorage.app"
STORAGE_PATH = "exercise-images"

# ---------------------------------------------------------------------------
# Import generation functions from the main script
# ---------------------------------------------------------------------------
sys.path.insert(0, str(SCRIPT_DIR))
from generate_exercise_images import (
    generate_image,
    save_image,
    RATE_LIMIT_DELAY,
)


# ---------------------------------------------------------------------------
# Firebase Admin SDK
# ---------------------------------------------------------------------------
def init_firebase(service_account_path: str | None = None):
    """
    Initialize Firebase Admin SDK and return a Firestore client.

    Auth strategy (in order):
    1. Explicit service account JSON file
    2. GOOGLE_APPLICATION_CREDENTIALS env var
    3. Application Default Credentials (gcloud auth)
    """
    try:
        import firebase_admin
        from firebase_admin import credentials, firestore
    except ImportError:
        print("ERROR: firebase-admin package not installed.")
        print("Run: pip install firebase-admin")
        sys.exit(1)

    if service_account_path:
        cred = credentials.Certificate(service_account_path)
    else:
        try:
            cred = credentials.ApplicationDefault()
        except Exception:
            print("ERROR: No Application Default Credentials found.")
            print("Run one of the following:")
            print("  gcloud auth application-default login")
            print("  OR pass --service-account path/to/key.json")
            sys.exit(1)

    try:
        firebase_admin.initialize_app(cred, {"projectId": "pt-helper-dev"})
    except ValueError:
        # App already initialized
        pass

    try:
        return firestore.client()
    except Exception as e:
        print(f"ERROR: Could not connect to Firestore: {e}")
        print("Run: gcloud auth application-default login")
        sys.exit(1)


# ---------------------------------------------------------------------------
# Fetch missing exercises from Firestore
# ---------------------------------------------------------------------------
def fetch_missing_exercises(
    db, min_count: int = 1, existing_mapping: dict = None, match_type_filter: str = None
) -> list[dict]:
    """
    Query Firestore 'missingExerciseImages' collection.

    Filters out:
    - Documents where status == "generated"
    - Documents whose normalizedKey already exists in the mapping
    - Documents with count < min_count
    - Documents not matching match_type_filter (if specified)

    Parameters
    ----------
    match_type_filter : str, optional
        Filter by matchType field. Values: "none" (truly missing), "prefix",
        "suffix", "pluralToggle", "synonymExpansion". If None, includes all.

    Returns list of exercise dicts compatible with generate_exercise_images.py.
    """
    if existing_mapping is None:
        existing_mapping = {}

    collection = db.collection("missingExerciseImages")
    docs = collection.stream()

    exercises = []
    skipped_generated = 0
    skipped_in_mapping = 0
    skipped_low_count = 0
    skipped_match_type = 0

    for doc in docs:
        data = doc.to_dict()

        # Skip already processed
        if data.get("status") == "generated":
            skipped_generated += 1
            continue

        normalized_key = data.get("normalizedKey", doc.id)

        # Skip if already in mapping
        if normalized_key in existing_mapping:
            skipped_in_mapping += 1
            continue

        # Skip if below minimum count threshold
        count = data.get("count", 1)
        if count < min_count:
            skipped_low_count += 1
            continue

        # Skip if match type doesn't match filter
        doc_match_type = data.get("matchType", "none")
        if match_type_filter and doc_match_type != match_type_filter:
            skipped_match_type += 1
            continue

        exercises.append(
            {
                "name": data.get("exerciseName", doc.id),
                "normalized_filename": normalized_key,
                "category": data.get("exerciseCategory", "general"),
                "target_area": data.get("targetArea", "General"),
                "pose_description": data.get("poseDescription", ""),
                "body_position": data.get("bodyPosition", ""),
                "count": count,
                "match_type": doc_match_type,
                "matched_to": data.get("matchedTo"),
                "firestore_doc_id": doc.id,
            }
        )

    # Sort by count descending -- most requested exercises first
    exercises.sort(key=lambda x: x["count"], reverse=True)

    print(f"Firestore query results:")
    print(f"  Found:              {len(exercises)} exercises to generate")
    print(f"  Skipped (generated): {skipped_generated}")
    print(f"  Skipped (in mapping): {skipped_in_mapping}")
    print(f"  Skipped (count < {min_count}): {skipped_low_count}")
    if match_type_filter:
        print(f"  Skipped (matchType != {match_type_filter}): {skipped_match_type}")

    return exercises


# ---------------------------------------------------------------------------
# Generate images using FLUX Kontext Pro
# ---------------------------------------------------------------------------
def generate_missing_images(
    exercises: list[dict],
    api_key: str,
    dry_run: bool = False,
    limit: int = 0,
) -> tuple[list[dict], list[dict]]:
    """
    Generate images for the given exercises.

    Parameters
    ----------
    exercises : list of exercise dicts
    api_key : BFL API key
    dry_run : skip API calls if True
    limit : max images to generate (0 = no limit)

    Returns (succeeded, failed) lists.
    """
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    succeeded = []
    failed = []
    total = len(exercises)

    if limit > 0:
        total = min(total, limit)
        print(f"\nGenerating up to {total} images (--limit {limit})...\n")
    else:
        print(f"\nGenerating {total} images...\n")

    for i, exercise in enumerate(exercises[:total]):
        name = exercise["name"]
        filename = exercise["normalized_filename"]
        filepath = OUTPUT_DIR / f"{filename}.png"

        print(f"[{i + 1}/{total}] {name} (requested {exercise.get('count', 'N/A')}x)", end="")

        # Skip if image already exists on disk
        if filepath.exists():
            print(" -- SKIPPED (exists)")
            succeeded.append(exercise)
            continue

        # Generate image
        image_data = generate_image(
            None, exercise, dry_run=dry_run,
            api_key=api_key,
        )

        if dry_run:
            print(f"  [DRY RUN] Would generate: {name}")
            succeeded.append(exercise)
            continue

        if image_data and save_image(image_data, filepath):
            file_size = filepath.stat().st_size / 1024
            print(f" -- OK ({file_size:.0f} KB)")
            succeeded.append(exercise)
        else:
            print(" -- FAILED")
            failed.append(exercise)

        # Rate limiting between requests
        if i < total - 1:
            time.sleep(RATE_LIMIT_DELAY)

    return succeeded, failed


# ---------------------------------------------------------------------------
# Update mapping JSON files
# ---------------------------------------------------------------------------
def update_mapping(mapping: dict, succeeded: list[dict]) -> dict:
    """
    Add new entries to the mapping and write to both locations:
    - scripts/output/exercise_image_mapping.json
    - ios/PT-Helper/PT-Helper/Resources/exercise_image_mapping.json

    Returns the updated mapping.
    """
    for exercise in succeeded:
        key = exercise["normalized_filename"]
        mapping[key] = {
            "name": exercise["name"],
            "filename": f"{key}.png",
            "category": exercise.get("category", "general"),
            "target_area": exercise.get("target_area", "General"),
        }

    # Write to scripts/output/
    with open(MAPPING_FILE, "w") as f:
        json.dump(mapping, f, indent=2)
    print(f"  Updated: {MAPPING_FILE}")

    # Copy to iOS app bundle
    if IOS_MAPPING_FILE.parent.exists():
        shutil.copy2(MAPPING_FILE, IOS_MAPPING_FILE)
        print(f"  Updated: {IOS_MAPPING_FILE}")
    else:
        print(f"  WARNING: iOS Resources directory not found, skipping copy")

    return mapping


def update_master_exercise_list(succeeded: list[dict]):
    """
    Add newly generated exercises to the master exercise_list.json
    so they are part of the curated list going forward.
    """
    if not MASTER_EXERCISE_LIST.exists():
        return

    with open(MASTER_EXERCISE_LIST, "r") as f:
        data = json.load(f)

    existing_keys = {ex["normalized_filename"] for ex in data["exercises"]}

    added = 0
    for exercise in succeeded:
        if exercise["normalized_filename"] not in existing_keys:
            new_entry = {
                "name": exercise["name"],
                "normalized_filename": exercise["normalized_filename"],
                "category": exercise.get("category", "general"),
                "target_area": exercise.get("target_area", "General"),
            }
            # Include optional fields if present
            if exercise.get("pose_description"):
                new_entry["pose_description"] = exercise["pose_description"]
            if exercise.get("body_position"):
                new_entry["body_position"] = exercise["body_position"]

            data["exercises"].append(new_entry)
            added += 1

    if added > 0:
        with open(MASTER_EXERCISE_LIST, "w") as f:
            json.dump(data, f, indent=2)
        print(f"  Added {added} new exercises to {MASTER_EXERCISE_LIST}")


# ---------------------------------------------------------------------------
# Upload to Firebase Storage
# ---------------------------------------------------------------------------
def upload_to_storage(succeeded: list[dict], dry_run: bool = False):
    """
    Upload newly generated images and updated mapping to Firebase Storage.
    """
    if not succeeded:
        return

    # Collect files to upload
    files_to_upload = []
    for exercise in succeeded:
        png_path = OUTPUT_DIR / f"{exercise['normalized_filename']}.png"
        if png_path.exists():
            files_to_upload.append(str(png_path))

    if not files_to_upload:
        print("  No new image files to upload.")
        return

    dest = f"{BUCKET}/{STORAGE_PATH}/"

    if dry_run:
        print(f"  [DRY RUN] Would upload {len(files_to_upload)} images to {dest}")
        return

    print(f"\nUploading {len(files_to_upload)} images to Firebase Storage...")

    # Upload images (parallel)
    cmd = ["gsutil", "-m", "cp"] + files_to_upload + [dest]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ERROR uploading images: {result.stderr}")
        return
    print(f"  Uploaded {len(files_to_upload)} images.")

    # Upload updated mapping
    mapping_dest = f"{BUCKET}/{STORAGE_PATH}/exercise_image_mapping.json"
    cmd = ["gsutil", "cp", str(MAPPING_FILE), mapping_dest]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"  ERROR uploading mapping: {result.stderr}")
        return
    print(f"  Uploaded updated mapping.")


# ---------------------------------------------------------------------------
# Mark Firestore documents as processed
# ---------------------------------------------------------------------------
def mark_as_generated(db, succeeded: list[dict]):
    """
    Update Firestore documents with status = "generated" so they are
    skipped on future runs.
    """
    from google.cloud.firestore import SERVER_TIMESTAMP

    print(f"\nMarking {len(succeeded)} Firestore documents as generated...")

    for exercise in succeeded:
        doc_id = exercise.get("firestore_doc_id", exercise["normalized_filename"])
        doc_ref = db.collection("missingExerciseImages").document(doc_id)
        doc_ref.update(
            {
                "status": "generated",
                "generatedAt": SERVER_TIMESTAMP,
                "imageFileName": exercise["normalized_filename"],
            }
        )

    print(f"  Done -- {len(succeeded)} documents updated.")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def read_api_key_from_keychain() -> str:
    """Read BFL API key from macOS Keychain."""
    result = subprocess.run(
        ["security", "find-generic-password", "-s", "BFL_API_KEY", "-w"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print("ERROR: Could not read BFL_API_KEY from keychain.")
        print("Store it with:")
        print('  security add-generic-password -s "BFL_API_KEY" -a "bfl" -w "YOUR_KEY"')
        sys.exit(1)
    return result.stdout.strip()


def cleanup_resolved_exercises(db, mapping: dict, dry_run: bool = False) -> int:
    """
    Find Firestore docs in missingExerciseImages where the exercise is already
    in the mapping but status != 'generated', and mark them as generated.

    Returns the number of documents updated.
    """
    from google.cloud.firestore import SERVER_TIMESTAMP

    collection = db.collection("missingExerciseImages")
    docs = list(collection.stream())

    to_resolve = []
    for doc in docs:
        data = doc.to_dict()
        if data.get("status") == "generated":
            continue
        normalized_key = data.get("normalizedKey", doc.id)
        if normalized_key in mapping:
            to_resolve.append((doc.id, normalized_key))

    if not to_resolve:
        print("  No resolved exercises to clean up.")
        return 0

    print(f"  Found {len(to_resolve)} already-resolved exercises in Firestore:")
    for doc_id, key in to_resolve:
        print(f"    - {key} (doc: {doc_id})")

    if dry_run:
        print(f"  [DRY RUN] Would mark {len(to_resolve)} documents as generated.")
        return len(to_resolve)

    for doc_id, key in to_resolve:
        db.collection("missingExerciseImages").document(doc_id).update(
            {
                "status": "generated",
                "generatedAt": SERVER_TIMESTAMP,
                "imageFileName": key,
            }
        )
    print(f"  Marked {len(to_resolve)} documents as generated.")
    return len(to_resolve)


def main():
    parser = argparse.ArgumentParser(
        description="Fetch missing exercise images from Firestore, generate via FLUX Kontext Pro, and upload to Firebase Storage"
    )
    key_group = parser.add_mutually_exclusive_group(required=True)
    key_group.add_argument(
        "--api-key",
        help="BFL (Black Forest Labs) API key for FLUX Kontext Pro image generation",
    )
    key_group.add_argument(
        "--keychain",
        action="store_true",
        help="Read BFL API key from macOS Keychain (service: BFL_API_KEY)",
    )
    parser.add_argument(
        "--service-account",
        default=None,
        help="Path to Firebase service account JSON (optional -- falls back to gcloud ADC)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview what would happen without making API calls",
    )
    parser.add_argument(
        "--cleanup-resolved",
        action="store_true",
        help="Mark Firestore docs as generated for exercises already in the mapping, then exit",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Max images to generate per run (0 = no limit)",
    )
    parser.add_argument(
        "--min-count",
        type=int,
        default=1,
        help="Only generate for exercises requested at least N times (default: 1)",
    )
    parser.add_argument(
        "--match-type",
        choices=["none", "prefix", "suffix", "pluralToggle", "synonymExpansion"],
        default=None,
        help="Only process exercises with this matchType (e.g., 'none' for truly missing, 'prefix' for fuzzy prefix matches)",
    )
    parser.add_argument(
        "--skip-upload",
        action="store_true",
        help="Skip uploading to Firebase Storage",
    )
    parser.add_argument(
        "--skip-cleanup",
        action="store_true",
        help="Skip marking Firestore documents as processed",
    )
    args = parser.parse_args()

    if args.keychain:
        args.api_key = read_api_key_from_keychain()

    print("=" * 60)
    print("  Missing Exercise Image Pipeline (FLUX Kontext Pro)")
    print("=" * 60)

    # Step 1: Initialize Firebase
    print("\n[1/6] Connecting to Firestore...")
    db = init_firebase(args.service_account)
    print("  Connected.")

    # Step 2: Load existing mapping
    print("\n[2/6] Loading existing image mapping...")

    mapping = {}
    if MAPPING_FILE.exists():
        with open(MAPPING_FILE, "r") as f:
            mapping = json.load(f)
    print(f"  {len(mapping)} exercises currently in mapping.")

    # Optional early-exit: cleanup already-resolved Firestore docs
    if args.cleanup_resolved:
        print("\n[CLEANUP] Marking already-resolved exercises in Firestore...")
        resolved = cleanup_resolved_exercises(db, mapping, dry_run=args.dry_run)
        print(f"\nCleanup complete. {resolved} documents {'would be ' if args.dry_run else ''}updated.")
        return

    # Step 3: Fetch missing exercises
    print("\n[3/6] Fetching missing exercises from Firestore...")
    missing = fetch_missing_exercises(
        db, min_count=args.min_count, existing_mapping=mapping,
        match_type_filter=args.match_type,
    )

    if not missing:
        print("\nNo new missing exercises found. Nothing to do!")
        return

    print(f"\nExercises to generate:")
    for ex in missing:
        match_info = f" [matchType={ex.get('match_type', 'none')}"
        if ex.get("matched_to"):
            match_info += f", matchedTo={ex['matched_to']}"
        match_info += "]"
        print(f"  - {ex['name']} ({ex['normalized_filename']}) -- {ex.get('count', 'N/A')}x requests{match_info}")

    # Step 4: Generate images
    print(f"\n[4/6] Generating images via FLUX Kontext Pro...")
    succeeded, failed = generate_missing_images(
        missing, args.api_key,
        dry_run=args.dry_run, limit=args.limit,
    )

    if not succeeded:
        print("\nNo images were generated successfully. Exiting.")
        return

    # Step 5: Update mapping
    if args.dry_run:
        print("\n[5/6] Skipping mapping update (dry run).")
    else:
        print("\n[5/6] Updating mapping files...")
        mapping = update_mapping(mapping, succeeded)
        update_master_exercise_list(succeeded)

    # Step 6: Upload to Firebase Storage
    if args.skip_upload or args.dry_run:
        print("\n[6/6] Skipping Firebase Storage upload.")
    else:
        print("\n[6/6] Uploading to Firebase Storage...")
        upload_to_storage(succeeded, dry_run=args.dry_run)

    # Mark Firestore docs as processed
    if not args.skip_cleanup and not args.dry_run:
        print("\nUpdating Firestore documents...")
        mark_as_generated(db, succeeded)

    # Summary
    print("\n" + "=" * 60)
    print("  SUMMARY")
    print("=" * 60)
    print(f"  Generated:  {len(succeeded)}")
    print(f"  Failed:     {len(failed)}")
    print(f"  Total in mapping: {len(mapping)}")

    if failed:
        print(f"\n  Failed exercises:")
        for ex in failed:
            print(f"    - {ex['name']}")

    if succeeded and not args.dry_run:
        print(f"\n  Next steps:")
        print(f"    1. Rebuild the iOS app in Xcode to bundle the updated mapping")
        print(f"    2. New images will auto-download from Firebase Storage on next app launch")


if __name__ == "__main__":
    main()
