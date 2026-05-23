# Exercise Image Pipeline

This directory contains the tools for generating, validating, and managing the 1364 canonical exercises (start+end frame pairs, as of 2026-04-30) used in PT Helper.

> **Primary pipeline (current):** Nano Banana Pro (`gemini-3-pro-image-preview`) via
> `generate_missing_images.py` + `regen_with_auto_prompts.py`.
> See `project_image_provider_decision.md` for rationale.
>
> **Legacy pipeline:** FLUX 2 Pro via BFL API (`generate_exercise_images.py`) — deprecated
> for new image work. Still referenced by the on-demand `generateExerciseImage` Cloud
> Function (migration is an open item).

## Overview

```
all_exercises_metadata.json  →  generate_missing_images.py   →  output/*.png
(exercises + pose descs)        (Nano Banana Pro / Gemini)
                                          ↑                          │
                                          │                          ▼
                                regen_with_auto_prompts.py    qa_exercise_images.py
                                (auto-prompt correction)       (Gemini 2.5 Flash QA)
                                                                     │
                                                                     ▼
                                                             output/qa_all_starts_report.json
                                                             (pose score 1-5 per image)
```

## Files

### Primary pipeline (Nano Banana Pro)

| File | Purpose |
|------|---------|
| `output/all_exercises_metadata.json` | Unified metadata for all 1364 exercises (name, pose_description, equipment, etc.) |
| `generate_missing_images.py` | Generates missing start images with Nano Banana Pro + inline QA |
| `regen_with_auto_prompts.py` | Auto-prompt correction loop: Gemini observes failure → writes anti-error prompt → regenerates |
| `rebuild_image_mapping.py` | Reconciles `exercise_image_mapping.json` from PNGs on disk + syncs to iOS Resources |
| `qa_exercise_images.py` | Automated QA using Gemini 2.5 Flash vision model (with no-schema fallback) |
| `qa_sweep_robust.py` | Serial QA with per-image SIGALRM timeout + checkpointing |
| `stockpile_exercise_images.py` | Stockpile agent that discovered the additional ~717 exercises |
| `triage_failures.py` | Classifies failures + auto-rewrites bad pose descriptions |
| `output/qa_all_starts_report.json` | Canonical QA report across all 1364 start images |

### Legacy pipeline (FLUX 2 Pro — deprecated)

| File | Purpose |
|------|---------|
| `exercise_list.json` | Original 190-exercise curated metadata list |
| `generate_exercise_images.py` | Legacy FLUX 2 Pro generator (BFL API) — still used by on-demand Cloud Function |
| `process_missing_images.py` | Legacy re-processing for FLUX pipeline |
| `generate_reference.py` | Reference character generation (deprecated) |

### Shared

| File | Purpose |
|------|---------|
| `upload_to_firebase.sh` | Uploads images to Firebase Storage (needs `gcloud auth login`) |
| `requirements.txt` | Python dependencies |
| `output/` | Generated PNG images and QA reports |
| `output/exercise_image_mapping.json` | Maps exercise names to image filenames |

## Setup

```bash
pip install -r requirements.txt
```

Required API keys:
- **Gemini API key** — For Nano Banana Pro generation and automated QA ([ai.google.dev](https://ai.google.dev))
- **BFL API key** (legacy only) — For FLUX 2 Pro generation via the legacy script ([blackforestlabs.ai](https://blackforestlabs.ai))

## Generating Images

### Generate all missing start images (current pipeline)
```bash
python generate_missing_images.py --api-key YOUR_GEMINI_KEY
```

### Generate a subset
```bash
python generate_missing_images.py --api-key YOUR_GEMINI_KEY --only "quad-sets,glute-bridge"
python generate_missing_images.py --api-key YOUR_GEMINI_KEY --limit 50
```

### Regenerate failures with auto-prompt correction
```bash
python regen_with_auto_prompts.py --api-key YOUR_GEMINI_KEY
```

### Legacy: generate with FLUX 2 Pro
```bash
python generate_exercise_images.py --api-key YOUR_BFL_KEY --exercise "quad-sets"
```

### Key parameters
- Style: Clean white background, anatomical mannequin figure
- Rate limits use Gemini's per-model quotas: ~250 generations/day (`gemini-3-pro-image-preview`)
  and ~1500 QA calls/day (`gemini-2.5-flash`). The scripts do not insert sleeps — they rely on
  the daily quota plus per-call SIGALRM timeouts (60–90s) to catch hung requests.
- Some exercises use custom visual prompts (`_CUSTOM_VISUAL_PROMPTS` in
  `generate_exercise_images.py`) for poses hard to describe by name. The current Nano
  Banana Pro pipeline uses pose descriptions from `output/all_exercises_metadata.json`
  plus the auto-prompt correction loop instead.

## Running QA

```bash
python qa_exercise_images.py --api-key YOUR_GEMINI_KEY
```

The QA script:
1. Loads each generated image
2. Sends it to Gemini 2.5 Flash with the exercise metadata
3. Checks: correct body position, correct pose, correct equipment, visual quality
4. Outputs `output/qa_report.json` with pass/fail per exercise

### Current Results (as of 2026-04-19, Nano Banana Pro pipeline)
- **Coverage**: 1364/1364 start images generated (effectively complete)
- **Pass rate**: ~98% at QA score 5 (806 at score 5, 25 at 4, 2 at 3, zero at ≤2)
- **Gemini safety blocks**: Occasional false positives on fitness poses — handled by manual review
- **Known QA limitation**: Gemini QA does NOT reliably validate variant compliance
  (single-leg / alternating / single-arm). Visual review is mandatory for variant exercises.

## Adding a New Exercise

1. Add entry to `exercise_list.json`:
   ```json
   {
     "name": "Exercise Name",
     "slug": "exercise-name",
     "body_position": "standing",
     "pose_description": "Description of the pose",
     "equipment": "none",
     "primary_muscles": ["quadriceps"]
   }
   ```

2. Generate the image:
   ```bash
   python generate_exercise_images.py --api-key KEY --exercise "exercise-name"
   ```

3. Run QA:
   ```bash
   python qa_exercise_images.py --api-key KEY
   ```

4. If the pose is hard to generate accurately, add a custom visual prompt to `_CUSTOM_VISUAL_PROMPTS` in `generate_exercise_images.py`.

5. Copy the image to `ios/PT-Helper/PT-Helper/Resources/` and update `exercise_image_mapping.json`.

## Deploying to iOS

Images in `output/` need to be copied to the iOS app's Resources directory:

```bash
cp output/*.png ../ios/PT-Helper/PT-Helper/Resources/
cp output/exercise_image_mapping.json ../ios/PT-Helper/PT-Helper/Resources/
```

The `ExerciseImageService` in the iOS app loads images by filename from this mapping.

## Troubleshooting

- **Nano Banana Pro misses a pose**: Run `regen_with_auto_prompts.py` — Gemini observes the
  failure and rewrites the prompt with anti-cues. Near-100% effective for fixable poses.
- **Gemini blocks an image**: Usually a false positive on fitness poses. Check the image
  manually — if it's fine, ignore the block.
- **Gemini API hangs**: All scripts use SIGALRM (60–90s timeout) to catch hung calls.
- **Gemini QA returns None / blank result**: Known structured-output bug. `qa_exercise_images.py`
  has a no-schema fallback (`_normalize_qa_keys()`) — re-run failed items.
- **Hit daily quota**: Free tier is ~250 generations/day on `gemini-3-pro-image-preview` and
  ~1500 QA calls/day on `gemini-2.5-flash`. Resume tomorrow.
- **Legacy FLUX 2 Pro can't do a pose**: Add a custom visual-only prompt to
  `_CUSTOM_VISUAL_PROMPTS` in `generate_exercise_images.py`.
