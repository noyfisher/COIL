---
name: exercise-pipeline
description: Generate, QA, diagnose missing images, or manage exercise images using FLUX 2 Pro and Gemini. Use when working with exercise illustrations or missing image issues.
argument-hint: [diagnose|generate|qa|status|sync]
disable-model-invocation: true
---

# Exercise Image Pipeline

Manage the full lifecycle of AI-generated exercise illustration images.

Parse `$ARGUMENTS` to determine the subcommand. Default to `status` if no argument given.

## Status Protocol

Emit a single status line before and after each step within the active subcommand:
- Format: `[Step N/M] <step> — starting` and `[Step N/M] <step> — done (<metric>)`
- Step counts by subcommand: `diagnose`=4, `generate`=3, `qa`=3, `sync`=2, `status`=skip (too short)
- Example (diagnose): `[Step 1/4] Gather missing exercises — starting` → `[Step 1/4] Gather missing exercises — done (12 missing found)`
- Example (generate): `[Step 2/3] Call FLUX API — starting` → `[Step 2/3] Call FLUX API — done (5/5 images generated)`

---

## `diagnose` — Smart Missing Image Triage

Determine whether missing exercises need new image generation or just a mapping/alias fix.

### Step 1: Gather missing exercises

**Try Firestore first:**
Run `scripts/process_missing_images.py` with `--dry-run` to fetch the `missingExerciseImages` collection. This requires Firebase auth — if it fails with an auth error, fall back to local-only mode.

**Local-only fallback:**
- Read `scripts/output/exercise_image_mapping.json` to get all currently mapped exercise keys
- List all PNGs in `scripts/output/` directory
- Compare: any PNG that exists on disk but isn't in the mapping is a potential gap

### Step 2: For each missing exercise, classify it

For each exercise name from the missing log:

1. **Normalize the name** — match `ExerciseImageService.normalizeName()` logic at `ios/PT-Helper/PT-Helper/Services/ExerciseImageService.swift:474`:
   - Lowercase
   - Replace spaces and underscores with hyphens
   - Strip content in parentheses
   - Remove trailing hyphens

2. **Check if a PNG exists** — search `scripts/output/` for files matching or containing the normalized name

3. **Classify:**
   - **Truly missing**: No matching PNG found anywhere in `scripts/output/` → needs FLUX generation
   - **Mapping issue**: A PNG with a similar/matching name exists in `scripts/output/` but the exercise name from the AI doesn't resolve through the 7-layer matching → needs an alias in `ExerciseImageService.aliasMap`

### Step 3: Act on classification

**For truly missing images:**
- List them in a table with exercise name, category, and target area
- Ask the user if they want to generate them (requires BFL API key)

**For mapping issues:**
- Identify the closest existing mapping key (the PNG that matches)
- Suggest the exact alias to add to `ExerciseImageService.aliasMap` at `ios/PT-Helper/PT-Helper/Services/ExerciseImageService.swift:128`
- Follow the existing alias pattern, e.g.:
  ```swift
  "ai-generated-exercise-name": "existing-mapping-key",
  ```
- Group aliases by exercise family (calf raises, glute bridges, etc.) matching the comment style in the existing alias map
- Offer to add the aliases after showing them to the user

### Step 4: Report summary

Show a table:
| Exercise Name | Classification | Action |
|---|---|---|
| quad-sets-isometric | Mapping issue | Add alias → `quad-sets` |
| single-leg-rdl-with-band | Truly missing | Generate with FLUX |

---

## `generate` — Image Generation

Generate exercise images using FLUX 2 Pro (BFL API).

```bash
cd scripts
python3 generate_exercise_images.py --api-key <BFL_KEY> [options]
```

**Options:**
- `--exercise "Exercise Name"` — generate a single exercise
- `--limit N` — generate only N exercises
- `--skip-existing` — skip exercises that already have images
- `--step pose-only` — generate pose reference only

Remind the user they need their BFL API key. Rate limit: 8 seconds between requests.

---

## `qa` — Quality Assurance

Run automated QA on generated images using Gemini 2.5 Flash vision.

```bash
cd scripts
python3 qa_exercise_images.py --api-key <GEMINI_KEY>
```

After completion, read `scripts/output/qa_report.json` and report:
- Total exercises checked
- Pass rate (target: >90%)
- Failures by category: pose accuracy, API safety blocks, other
- List specific failures with exercise names

**Known issues:** Gemini falsely blocks some fitness poses (glute-bridges, childs-pose, standing-quad-stretch, childs-pose-with-side-reach) — these images are fine.

---

## `status` — Overview

Read these files and summarize the current state:

1. `scripts/output/exercise_image_mapping.json` — count of mapped exercises
2. `scripts/exercise_list.json` — total exercise count (should be 178)
3. `scripts/output/qa_report.json` — QA pass rate and failure breakdown
4. List any PNGs in `scripts/output/` that are NOT in the mapping (orphaned images)
5. If Firestore is accessible, count pending entries in `missingExerciseImages`

Present as a dashboard:
```
Exercise Images Status:
  Total exercises:    178
  Mapped:             178 (100%)
  QA passed:          163 (92%)
  QA failures:        15 (11 pose accuracy, 4 safety blocks)
  Orphaned PNGs:      0
  Firestore missing:  N/A (not connected)
```

---

## `sync` — Deploy Images to iOS Bundle

Copy generated and approved images to the iOS app resources:

1. Copy `scripts/output/exercise_image_mapping.json` → `ios/PT-Helper/PT-Helper/Resources/exercise_image_mapping.json`
2. Copy all PNGs from `scripts/output/poses/` → `ios/PT-Helper/PT-Helper/Resources/` (only those in the mapping)
3. Report how many files were copied/updated

---

## Key Files

| File | Purpose |
|------|---------|
| `ios/PT-Helper/PT-Helper/Services/ExerciseImageService.swift` | 7-layer image resolution + `aliasMap` (line ~128) + `normalizeName()` (line ~474) |
| `ios/PT-Helper/PT-Helper/ViewModels/RehabPlanViewModel.swift` | `logMissingImages()` (line ~664) |
| `scripts/process_missing_images.py` | Firestore fetch → generate → map → upload |
| `scripts/generate_exercise_images.py` | FLUX 2 Pro image generation |
| `scripts/qa_exercise_images.py` | Gemini 2.5 Flash vision QA |
| `scripts/output/exercise_image_mapping.json` | Source of truth mapping |
| `ios/PT-Helper/PT-Helper/Resources/exercise_image_mapping.json` | Bundled app copy |
| `scripts/exercise_list.json` | Master exercise metadata (178 exercises) |
