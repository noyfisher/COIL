# Exercise Image Pipeline

This directory contains the tools for generating, validating, and managing the 178 AI-generated exercise illustrations used in PT Helper.

## Overview

```
exercise_list.json          →  generate_exercise_images.py  →  output/*.png
(178 exercises + metadata)     (FLUX 2 Pro via BFL API)        (512x512 images)
                                                                    │
                                                                    ▼
                                                            qa_exercise_images.py
                                                            (Gemini 2.5 Flash QA)
                                                                    │
                                                                    ▼
                                                            output/qa_report.json
                                                            (pass/fail per image)
```

## Files

| File | Purpose |
|------|---------|
| `exercise_list.json` | Master list of 178 exercises with metadata (name, body_position, pose_description, equipment, etc.) |
| `generate_exercise_images.py` | Generates exercise images using FLUX 2 Pro (BFL API) |
| `qa_exercise_images.py` | Automated QA using Gemini 2.5 Flash vision model |
| `process_missing_images.py` | Re-processes failed or missing images |
| `generate_reference.py` | Reference character generation (deprecated) |
| `upload_to_firebase.sh` | Uploads images to Firebase Storage |
| `requirements.txt` | Python dependencies |
| `output/` | Generated PNG images and QA reports |
| `output/exercise_image_mapping.json` | Maps exercise names to image filenames |

## Setup

```bash
pip install -r requirements.txt
```

Required API keys:
- **BFL API key** — For FLUX 2 Pro image generation ([blackforestlabs.ai](https://blackforestlabs.ai))
- **Gemini API key** — For automated QA ([ai.google.dev](https://ai.google.dev))

## Generating Images

### Generate all missing images
```bash
python generate_exercise_images.py --api-key YOUR_BFL_KEY
```

### Generate a specific exercise
```bash
python generate_exercise_images.py --api-key YOUR_BFL_KEY --exercise "quad-sets"
```

### Key parameters
- Images are 512x512 PNG
- Rate limit delay: 8 seconds between API requests
- Style: Clean white background, anatomical mannequin figure
- 14 exercises use custom visual prompts (`_CUSTOM_VISUAL_PROMPTS`) for poses that are hard to describe by name

## Running QA

```bash
python qa_exercise_images.py --api-key YOUR_GEMINI_KEY
```

The QA script:
1. Loads each generated image
2. Sends it to Gemini 2.5 Flash with the exercise metadata
3. Checks: correct body position, correct pose, correct equipment, visual quality
4. Outputs `output/qa_report.json` with pass/fail per exercise

### Current Results
- **Pass rate**: 92% (163/178)
- **4 Gemini safety blocks**: False positives on fitness poses (glute-bridges, childs-pose, standing-quad-stretch, childs-pose-with-side-reach) — images are fine
- **11 pose accuracy failures**: Exercises too subtle for AI vision QA (wrist curls, chin tucks, etc.)

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

- **FLUX 2 Pro can't do a pose**: Add a custom visual-only prompt to `_CUSTOM_VISUAL_PROMPTS` that describes what the camera sees without using the exercise name
- **Gemini blocks an image**: Usually a false positive on fitness poses. Check the image manually — if it's fine, ignore the block
- **Rate limiting**: The BFL API has rate limits. The script uses an 8-second delay between requests
- **Prone positions**: FLUX 2 Pro handles face-down poses well (earlier Kontext Pro couldn't)
