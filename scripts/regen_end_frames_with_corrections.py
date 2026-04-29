"""
Regenerate end-frame images that failed pair-consistency QA, using auto-prompt
correction (the same loop that cracked start-image failures).

Workflow per failure:
  1. Read the pair QA observation for what failed (which dimension, why)
  2. Ask Gemini Flash to write a targeted regen prompt with anti-cues
     ("the previous attempt showed X — this attempt must NOT do that, instead Y")
  3. Generate a new end frame with NB Pro using the start image as reference
     + the corrected prompt
  4. Re-QA the new pair, keep best
  5. Update consistency_report.json with the new result

Pre-req: scripts/output/consistency_report.json exists (run qa_consistency.py first).

Usage:
  python scripts/regen_end_frames_with_corrections.py --api-key KEY
  python scripts/regen_end_frames_with_corrections.py --api-key KEY --threshold 4
  python scripts/regen_end_frames_with_corrections.py --api-key KEY --only chin-tucks --attempts 3
"""
import argparse
import json
import shutil
import signal
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
CONSIST = OUT / "consistency_report.json"
BACKUP_DIR = OUT / "_pre_end_regen_backup"

GEN_MODEL = "gemini-3-pro-image-preview"
PROMPT_MODEL = "gemini-2.5-flash"
QA_MODEL = "gemini-2.5-flash"
TIMEOUT_SEC = 90

CHARACTER_NOTE = (
    "An athletic young man with short dark hair, lean fit build, wearing a "
    "fitted light gray athletic t-shirt, dark navy compression shorts, white "
    "ankle socks, and gray athletic sneakers."
)

PROMPT_GEN_TEMPLATE = """You are a prompt engineer for a fitness illustration generator.

A previous attempt to generate the END position of "{name}" failed pair-consistency QA.

Exercise context:
- Body position: {body_position}
- Target area: {target_area}
- START pose: {start_desc}
- END pose (target): {end_desc}

The QA system flagged these problems with the previous end-frame:
{qa_observations}

Write a NEW image-generation prompt for the END position. The model receives the START image
as a reference. Your prompt must:
- Anchor character/clothing/camera/scene/lighting/style to the reference image (these MUST match exactly).
- Describe the END body posture with high anatomical specificity.
- Include explicit anti-cues for each QA failure ("Do NOT show [the problem]", "the [body part] must be at [angle]", etc.).
- Avoid motion words ("lifting", "rotating", "moving") — describe the static frame at the END of one rep.

Subject reference: {subject}

Respond with ONLY the prompt text (no JSON, no commentary, no markdown). Keep under 350 words."""


class _Timeout(Exception): pass

def _alarm(signum, frame): raise _Timeout()


def write_prompt(client: genai.Client, ex: dict, qa_obs: str) -> str | None:
    template = PROMPT_GEN_TEMPLATE.format(
        name=ex.get("name", ex["normalized_filename"]),
        body_position=ex.get("body_position", "?"),
        target_area=ex.get("target_area", "?"),
        start_desc=(ex.get("pose_description") or "").strip(),
        end_desc=(ex.get("end_pose_description") or "").strip(),
        qa_observations=qa_obs.strip(),
        subject=CHARACTER_NOTE,
    )
    signal.alarm(TIMEOUT_SEC)
    try:
        resp = client.models.generate_content(model=PROMPT_MODEL, contents=template)
    except _Timeout:
        print("    PROMPT TIMEOUT")
        return None
    except Exception as e:
        print(f"    PROMPT ERR: {e}")
        return None
    finally:
        signal.alarm(0)
    return (resp.text or "").strip() if resp else None


def generate_end_frame(client: genai.Client, start_bytes: bytes, prompt: str) -> bytes | None:
    img_part = types.Part.from_bytes(data=start_bytes, mime_type="image/png")
    signal.alarm(TIMEOUT_SEC)
    try:
        resp = client.models.generate_content(
            model=GEN_MODEL,
            contents=[img_part, prompt],
            config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
        )
    except _Timeout:
        print("    GEN TIMEOUT")
        return None
    except Exception as e:
        print(f"    GEN ERR: {e}")
        return None
    finally:
        signal.alarm(0)
    for cand in (resp.candidates or []):
        if cand.content and cand.content.parts:
            for p in cand.content.parts:
                d = getattr(p, "inline_data", None)
                if d and d.data:
                    return d.data
    return None


def qa_pair(client: genai.Client, start_path: Path, end_path: Path, ex: dict) -> dict | None:
    sys.path.insert(0, str(OUT.parent))
    from qa_consistency import analyze_consistency
    signal.alarm(TIMEOUT_SEC)
    try:
        result = analyze_consistency(client, start_path, end_path, ex)
        return json.loads(result.model_dump_json())
    except _Timeout:
        print("    QA TIMEOUT")
        return None
    except Exception as e:
        print(f"    QA ERR: {e}")
        return None
    finally:
        signal.alarm(0)


def collect_qa_observations(qa_row: dict) -> str:
    """Pull all observations from failed checks into one block."""
    obs_lines = []
    for check_key in (
        "camera_angle", "character_identity", "clothing", "art_style",
        "scene_setup", "body_anchoring", "movement_logic"
    ):
        check = qa_row.get(check_key, {})
        score = check.get("score", 5)
        if score < 4:
            obs = check.get("observation", "").strip()
            if obs:
                obs_lines.append(f"- [{check_key}] (score {score}/5): {obs}")
    return "\n".join(obs_lines) or "(no detailed observations available)"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--threshold", type=float, default=4.0,
                    help="Regen pairs below this overall_consistency_score")
    ap.add_argument("--only", help="Comma-separated normalized_filenames")
    ap.add_argument("--attempts", type=int, default=2)
    args = ap.parse_args()

    if not CONSIST.exists():
        print(f"ERROR: {CONSIST} not found. Run qa_consistency.py first.")
        return 2

    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    signal.signal(signal.SIGALRM, _alarm)
    meta = json.loads(META.read_text())
    by_name = {e["normalized_filename"]: e for e in meta["exercises"]}

    cr = json.loads(CONSIST.read_text())
    results = cr.get("results", {})

    if args.only:
        names = [n.strip() for n in args.only.split(",") if n.strip()]
    else:
        names = sorted(n for n, r in results.items()
                       if r.get("overall_consistency_score", 5) < args.threshold)

    client = genai.Client(api_key=args.api_key)
    rows = []

    for idx, name in enumerate(names, 1):
        ex = by_name.get(name)
        if not ex:
            print(f"[{idx}/{len(names)}] {name}: not in metadata")
            continue
        qa_row = results.get(name)
        if not qa_row:
            print(f"[{idx}/{len(names)}] {name}: no QA row")
            continue
        old_score = qa_row.get("overall_consistency_score", 0)
        obs = collect_qa_observations(qa_row)
        print(f"\n[{idx}/{len(names)}] {name}  (current: {old_score}/5)")

        start_path = OUT / f"{name}.png"
        end_path = OUT / f"{name}_end.png"
        if not start_path.exists() or not end_path.exists():
            print("  missing files, skip")
            continue

        # Backup current end frame
        bk = BACKUP_DIR / f"{name}_end.png"
        if not bk.exists():
            shutil.copy2(end_path, bk)

        prompt = write_prompt(client, ex, obs)
        if not prompt:
            print("  prompt-gen failed")
            rows.append((name, old_score, old_score, "prompt_fail"))
            continue
        print(f"  prompt ({len(prompt)} chars)")

        best_score = old_score
        best_bytes = None
        best_qa = None
        start_bytes = start_path.read_bytes()
        for attempt in range(args.attempts):
            img_bytes = generate_end_frame(client, start_bytes, prompt)
            if not img_bytes:
                time.sleep(2)
                continue
            tmp = OUT / f"_tmp_{name}_end.png"
            tmp.write_bytes(img_bytes)
            qa = qa_pair(client, start_path, tmp, ex)
            score = (qa or {}).get("overall_consistency_score", 0)
            print(f"  attempt {attempt+1}: score={score}/5")
            if score > best_score:
                best_score = score
                best_bytes = img_bytes
                best_qa = qa
            try: tmp.unlink()
            except OSError: pass
            time.sleep(2)

        if best_bytes is not None:
            end_path.write_bytes(best_bytes)
            results[name] = best_qa
            print(f"  INSTALLED score {best_score}")
            rows.append((name, old_score, best_score, "installed"))
        else:
            print(f"  kept current ({old_score})")
            rows.append((name, old_score, old_score, "kept"))

        # Save consistency_report.json after each — survive crashes
        cr["results"] = results
        # Recompute aggregates if present
        scores = [r.get("overall_consistency_score", 0) for r in results.values()]
        if "summary" in cr or scores:
            cr["summary"] = cr.get("summary", {})
            cr["summary"]["total_pairs"] = len(results)
            cr["summary"]["consistent_pairs"] = sum(1 for s in scores if s >= 4)
            cr["summary"]["average_score"] = round(sum(scores) / max(len(scores), 1), 2)
        CONSIST.write_text(json.dumps(cr, indent=2))
        time.sleep(1)

    print("\n" + "=" * 72)
    print("END-FRAME AUTO-PROMPT REGEN SUMMARY")
    print("=" * 72)
    improved = sum(1 for _, o, n, s in rows if n > o)
    unchanged = sum(1 for _, o, n, s in rows if n == o)
    print(f"  Attempted: {len(rows)}   Improved: {improved}   Unchanged: {unchanged}")
    for name, old, new, status in rows:
        arrow = "->" if new > old else "=="
        print(f"  {name:50}  {old:.2f} {arrow} {new:.2f}  {status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
