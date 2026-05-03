"""
Generate end-frame exercise images by conditioning Nano Banana Pro on the
already-passing start image. The model receives the start PNG as a reference
and rewrites only the body posture; character, clothing, camera, lighting,
background, and art style are anchored to the reference.

This supersedes the FLUX-Fill inpainting approach (manual masks). NB Pro
understands "edit this image to match new pose" natively, so no masks needed.

Output: scripts/output/{normalized_filename}_end.png
Progress: scripts/output/end_gen_progress.json (resumable)

Usage:
  python scripts/generate_end_frames_nb.py --api-key KEY
  python scripts/generate_end_frames_nb.py --api-key KEY --only quad-sets,clamshells
  python scripts/generate_end_frames_nb.py --api-key KEY --limit 10  # pilot
  python scripts/generate_end_frames_nb.py --api-key KEY --overwrite
"""
import argparse
import json
import signal
import sys
import time
from pathlib import Path

from google import genai
from google.genai import types

OUT = Path(__file__).resolve().parent / "output"
META = OUT / "all_exercises_metadata.json"
PROGRESS = OUT / "end_gen_progress.json"

GEN_MODEL = "gemini-3-pro-image-preview"
GEN_TIMEOUT_SEC = 90
SLEEP_BETWEEN = 1.0

CHARACTER_NOTE = (
    "An athletic young man with short dark hair, lean fit build, wearing a "
    "fitted light gray athletic t-shirt, dark navy compression shorts, white "
    "ankle socks, and gray athletic sneakers."
)


def build_prompt(ex: dict) -> str:
    name = ex.get("name", ex["normalized_filename"])
    body_pos = ex.get("body_position", "?")
    end_desc = (ex.get("end_pose_description") or "").strip()
    return (
        f"Reference image: the START position of the physical therapy exercise '{name}'.\n\n"
        f"Generate the END position of the same exercise (peak of one rep). Output a single "
        f"clean fitness illustration that EXACTLY MATCHES THE REFERENCE IMAGE in:\n"
        f"  - character (same person, identical clothing, hair, build, skin tone)\n"
        f"  - camera angle and framing (same viewpoint, same distance, same crop)\n"
        f"  - background (same plain backdrop)\n"
        f"  - lighting (same direction, same softness)\n"
        f"  - art style (same illustration style as the reference)\n\n"
        f"The ONLY thing that changes is the body posture. New posture (END position):\n"
        f"{end_desc}\n\n"
        f"Body position context: {body_pos}.\n"
        f"Subject reference: {CHARACTER_NOTE}\n\n"
        f"Single static still — no motion blur, arrows, text, labels, watermarks, or "
        f"annotations anywhere in the image. Full body visible, head to toe. "
        f"Do NOT change the camera angle. Do NOT redesign the character. "
        f"Do NOT change the clothing. ONLY change the body posture."
    )


class _Timeout(Exception): pass

def _alarm(signum, frame): raise _Timeout()


def generate_end_frame(client: genai.Client, start_bytes: bytes, prompt: str) -> bytes | None:
    img_part = types.Part.from_bytes(data=start_bytes, mime_type="image/png")
    signal.alarm(GEN_TIMEOUT_SEC)
    try:
        resp = client.models.generate_content(
            model=GEN_MODEL,
            contents=[img_part, prompt],
            config=types.GenerateContentConfig(response_modalities=["IMAGE"]),
        )
    except _Timeout:
        print("    TIMEOUT")
        return None
    except Exception as e:
        print(f"    GEN ERROR: {e}")
        return None
    finally:
        signal.alarm(0)
    for cand in (resp.candidates or []):
        if cand.content and cand.content.parts:
            for p in cand.content.parts:
                d = getattr(p, "inline_data", None)
                if d and d.data:
                    return d.data
    feedback = getattr(resp, "prompt_feedback", None)
    print(f"    no image bytes (feedback={feedback})")
    return None


def load_progress() -> dict:
    if PROGRESS.exists():
        return json.loads(PROGRESS.read_text())
    return {"generated": [], "failed": [], "skipped_no_desc": []}


def save_progress(p: dict) -> None:
    PROGRESS.write_text(json.dumps(p, indent=2))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--api-key", required=True)
    ap.add_argument("--only", help="Comma-separated normalized_filenames")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--overwrite", action="store_true",
                    help="Regenerate even if {name}_end.png already exists")
    args = ap.parse_args()

    signal.signal(signal.SIGALRM, _alarm)
    meta = json.loads(META.read_text())
    by_name = {e["normalized_filename"]: e for e in meta["exercises"]}

    if args.only:
        names = [n.strip() for n in args.only.split(",") if n.strip()]
    else:
        names = sorted(by_name.keys())

    progress = load_progress()
    generated_set = set(progress["generated"])

    todo = []
    for n in names:
        ex = by_name.get(n)
        if not ex:
            print(f"SKIP {n}: not in metadata")
            continue
        if not (ex.get("end_pose_description") or "").strip():
            if n not in progress["skipped_no_desc"]:
                progress["skipped_no_desc"].append(n)
            continue
        end_path = OUT / f"{n}_end.png"
        if end_path.exists() and not args.overwrite:
            generated_set.add(n)
            continue
        start_path = OUT / f"{n}.png"
        if not start_path.exists():
            print(f"SKIP {n}: no start image")
            continue
        if n in generated_set and not args.overwrite:
            continue
        todo.append((n, ex, start_path, end_path))

    if args.limit > 0:
        todo = todo[: args.limit]
    print(f"to generate: {len(todo)}  (overwrite={args.overwrite})")

    client = genai.Client(api_key=args.api_key)
    t0 = time.time()
    ok = fail = 0

    for idx, (name, ex, start_path, end_path) in enumerate(todo, 1):
        prompt = build_prompt(ex)
        start_bytes = start_path.read_bytes()
        img_bytes = generate_end_frame(client, start_bytes, prompt)
        if img_bytes:
            end_path.write_bytes(img_bytes)
            ok += 1
            generated_set.add(name)
            if name not in progress["generated"]:
                progress["generated"].append(name)
            print(f"[{idx}/{len(todo)}] {name}  OK")
        else:
            fail += 1
            if name not in progress["failed"]:
                progress["failed"].append(name)
            print(f"[{idx}/{len(todo)}] {name}  FAIL")

        if idx % 10 == 0:
            save_progress(progress)
            elapsed = time.time() - t0
            print(f"  checkpoint: ok={ok} fail={fail} {elapsed:.0f}s")

        time.sleep(SLEEP_BETWEEN)

    save_progress(progress)
    elapsed = time.time() - t0
    print(f"\nDone. ok={ok} fail={fail} total_time={elapsed:.0f}s "
          f"avg={elapsed/max(len(todo),1):.1f}s/img")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
