"""
Local review UI for START images.

Shows every start image alongside:
  - pose_description (what the image SHOULD depict as the start position)
  - Gemini POSE_ACCURACY score (1-5) + observation
  - All other QA check results
  - Pass / Needs-regen / Fix-description / Notes controls

Sorted by POSE_ACCURACY score ascending (worst first) so problems surface
immediately. Live-reloads the QA report so you can review as the sweep runs.

Reviews saved to scripts/output/start_image_reviews.json.

Usage:
  python scripts/review_starts_server.py
  python scripts/review_starts_server.py --port 5300
"""
from __future__ import annotations

import argparse
import json
from http.server import HTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import urlparse

SCRIPT_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = SCRIPT_DIR / "output"
METADATA = OUTPUT_DIR / "all_exercises_metadata.json"
QA_REPORT = OUTPUT_DIR / "qa_all_starts_report.json"
REVIEW_LOG = OUTPUT_DIR / "start_image_reviews.json"


def load_json(path: Path, default):
    if not path.exists():
        return default
    try:
        with path.open() as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return default


def save_reviews(reviews: dict):
    REVIEW_LOG.write_text(json.dumps(reviews, indent=2))


def build_entries() -> list[dict]:
    meta = load_json(METADATA, {"exercises": []}).get("exercises", [])
    qa_report = load_json(QA_REPORT, {}).get("results", {})
    reviews = load_json(REVIEW_LOG, {})

    CHECK_NAMES = [
        "anatomy", "subject", "full_body", "clothing", "background",
        "no_text", "art_style", "body_orientation", "pose_accuracy",
    ]

    entries = []
    for ex in meta:
        name = ex["normalized_filename"]
        qa = qa_report.get(name) or {}
        # Collect check results: each is {"observation", "passed"}
        checks = {}
        for c in CHECK_NAMES:
            cv = qa.get(c)
            if isinstance(cv, dict):
                checks[c] = {
                    "passed": bool(cv.get("passed", False)),
                    "observation": cv.get("observation", ""),
                }

        pose_score = qa.get("pose_score")
        overall_pass = qa.get("overall_pass")
        failures = qa.get("critical_failures", [])

        review = reviews.get(name, {})

        entries.append({
            "name": name,
            "display_name": ex.get("name") or name.replace("-", " ").title(),
            "image": f"{name}.png",
            "source": ex.get("source", ""),
            "body_position": ex.get("body_position", ""),
            "pose_description": ex.get("pose_description", ""),
            "end_pose_description": ex.get("end_pose_description", ""),
            "pose_score": pose_score,
            "overall_pass": overall_pass,
            "critical_failures": failures,
            "checks": checks,
            "review_status": review.get("status", "unreviewed"),
            "review_notes": review.get("notes", ""),
            "has_qa": bool(qa),
        })

    # Sort: worst pose_score first; unrated (no QA yet) at end
    def sort_key(e):
        if e["pose_score"] is None:
            return (2, 0, e["name"])
        return (0, e["pose_score"], e["name"])

    entries.sort(key=sort_key)
    return entries


HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Start Image Review</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
         background: #0b0b0d; color: #e6e6e6; }
  .header { position: sticky; top: 0; z-index: 10;
            background: #111; border-bottom: 1px solid #2a2a2a;
            padding: 12px 20px; display: flex; gap: 18px; align-items: center;
            flex-wrap: wrap; }
  .header h1 { font-size: 16px; font-weight: 600; }
  .stats { font-size: 13px; color: #aaa; }
  .stats span { margin-right: 14px; }
  .filters label { margin-right: 12px; font-size: 13px; color: #ccc; cursor: pointer; }
  .filters input { margin-right: 4px; }
  .container { padding: 20px; display: grid; gap: 16px;
               grid-template-columns: repeat(auto-fill, minmax(560px, 1fr)); }
  .card { background: #15161a; border: 1px solid #27292f;
          border-radius: 10px; overflow: hidden; display: flex; flex-direction: column; }
  .card.reviewed-pass { border-color: #2d6a3d; }
  .card.reviewed-regen { border-color: #8a3a2e; }
  .card.reviewed-fixdesc { border-color: #a07500; }
  .card.reviewed-skip { border-color: #555; opacity: 0.6; }
  .card-body { display: flex; gap: 14px; padding: 14px; }
  .card-img { flex: 0 0 220px; }
  .card-img img { width: 220px; height: 220px; object-fit: contain;
                  background: #fff; border-radius: 6px; }
  .card-content { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 6px; }
  .card h2 { font-size: 15px; font-weight: 600; }
  .meta { font-size: 11px; color: #888; }
  .desc { font-size: 12px; color: #bcbcbc; line-height: 1.4;
          background: #0e0f12; padding: 8px; border-radius: 4px;
          max-height: 110px; overflow: auto; }
  .score-row { display: flex; align-items: center; gap: 10px; margin-top: 4px; }
  .score-pill { padding: 3px 10px; border-radius: 20px;
                font-size: 12px; font-weight: 700; }
  .s1 { background: #5a1d1d; color: #ffb7b7; }
  .s2 { background: #6e3817; color: #ffd3a1; }
  .s3 { background: #665a18; color: #fff2a1; }
  .s4 { background: #22532f; color: #b8f2c7; }
  .s5 { background: #185a45; color: #a1f2d3; }
  .s-na { background: #333; color: #aaa; }
  .obs { font-size: 11px; color: #9ba3ad; line-height: 1.4;
         background: #0e0f12; padding: 6px 8px; border-radius: 4px; }
  .checks { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 2px; }
  .chip { font-size: 10px; padding: 2px 7px; border-radius: 3px; font-weight: 600; }
  .chip.pass { background: #1f3d28; color: #83e0a2; }
  .chip.fail { background: #4d1f1f; color: #ff9b9b; }
  .actions { display: flex; gap: 6px; margin-top: 8px; flex-wrap: wrap; }
  .actions button { font-size: 12px; padding: 6px 10px; border-radius: 5px;
                    border: 1px solid #333; background: #1a1b20; color: #ddd;
                    cursor: pointer; }
  .actions button:hover { background: #242630; }
  .actions button.active.pass { background: #2d6a3d; border-color: #2d6a3d; color: #fff; }
  .actions button.active.regen { background: #8a3a2e; border-color: #8a3a2e; color: #fff; }
  .actions button.active.fixdesc { background: #a07500; border-color: #a07500; color: #fff; }
  .actions button.active.skip { background: #555; border-color: #555; color: #fff; }
  .notes { width: 100%; margin-top: 6px; padding: 5px 7px; font-size: 12px;
           background: #0e0f12; border: 1px solid #27292f; color: #ccc;
           border-radius: 4px; resize: vertical; min-height: 32px; font-family: inherit; }
  .status-tag { font-size: 11px; padding: 2px 8px; border-radius: 10px; font-weight: 700; }
  .status-pass { background: #2d6a3d; color: #fff; }
  .status-regen { background: #8a3a2e; color: #fff; }
  .status-fixdesc { background: #a07500; color: #fff; }
  .status-skip { background: #555; color: #fff; }
  .loading { padding: 40px; text-align: center; color: #888; }
</style>
</head>
<body>
<div class="header">
  <h1>Start Image Review</h1>
  <div class="stats" id="stats">Loading...</div>
  <div class="filters">
    <label><input type="checkbox" id="f-unrev" checked>Unreviewed</label>
    <label><input type="checkbox" id="f-pass" checked>Pass</label>
    <label><input type="checkbox" id="f-regen" checked>Regen</label>
    <label><input type="checkbox" id="f-fixdesc" checked>Fix desc</label>
    <label><input type="checkbox" id="f-skip">Skip</label>
    <label><input type="checkbox" id="f-lowscore">Only score ≤3</label>
  </div>
  <button onclick="refresh()" style="margin-left:auto;padding:6px 12px;background:#252833;border:1px solid #333;color:#ddd;border-radius:5px;cursor:pointer;">Refresh</button>
</div>
<div class="container" id="container"><div class="loading">Loading entries...</div></div>

<script>
let ALL = [];

async function refresh() {
  const r = await fetch('/api/entries');
  ALL = await r.json();
  render();
}

function filterEntries() {
  const fu = document.getElementById('f-unrev').checked;
  const fp = document.getElementById('f-pass').checked;
  const fr = document.getElementById('f-regen').checked;
  const ff = document.getElementById('f-fixdesc').checked;
  const fs = document.getElementById('f-skip').checked;
  const fl = document.getElementById('f-lowscore').checked;

  return ALL.filter(e => {
    const s = e.review_status;
    if (s === 'unreviewed' && !fu) return false;
    if (s === 'pass' && !fp) return false;
    if (s === 'regen' && !fr) return false;
    if (s === 'fixdesc' && !ff) return false;
    if (s === 'skip' && !fs) return false;
    if (fl && e.pose_score !== null && e.pose_score > 3) return false;
    return true;
  });
}

function scoreClass(s) {
  if (s === null || s === undefined) return 's-na';
  return 's' + s;
}

function render() {
  const entries = filterEntries();

  const total = ALL.length;
  const withQA = ALL.filter(e => e.has_qa).length;
  const reviewed = ALL.filter(e => e.review_status !== 'unreviewed').length;
  const regenCount = ALL.filter(e => e.review_status === 'regen').length;
  const fixdescCount = ALL.filter(e => e.review_status === 'fixdesc').length;
  document.getElementById('stats').innerHTML =
    `<span>${total} images</span>` +
    `<span>QA'd: ${withQA}</span>` +
    `<span>Reviewed: ${reviewed}</span>` +
    `<span>Marked regen: ${regenCount}</span>` +
    `<span>Marked fix-desc: ${fixdescCount}</span>` +
    `<span>Showing: ${entries.length}</span>`;

  const container = document.getElementById('container');
  if (entries.length === 0) {
    container.innerHTML = '<div class="loading">No entries match filters.</div>';
    return;
  }

  container.innerHTML = entries.map(renderCard).join('');
}

function renderCard(e) {
  const status = e.review_status;
  const reviewedClass = status === 'pass' ? 'reviewed-pass'
                      : status === 'regen' ? 'reviewed-regen'
                      : status === 'fixdesc' ? 'reviewed-fixdesc'
                      : status === 'skip' ? 'reviewed-skip' : '';
  const scoreDisplay = e.pose_score === null ? 'pending' : e.pose_score + '/5';
  const scoreCls = scoreClass(e.pose_score);
  const poseObs = e.checks.pose_accuracy ? e.checks.pose_accuracy.observation : '';

  const checkChips = Object.entries(e.checks)
    .filter(([k]) => k !== 'pose_accuracy')
    .map(([k, v]) => `<span class="chip ${v.passed ? 'pass' : 'fail'}">${k}</span>`)
    .join('');

  const statusTag = status !== 'unreviewed'
    ? `<span class="status-tag status-${status}">${status}</span>`
    : '';

  return `
  <div class="card ${reviewedClass}" id="card-${e.name}">
    <div class="card-body">
      <div class="card-img"><img src="/images/${e.image}" loading="lazy"></div>
      <div class="card-content">
        <h2>${escapeHtml(e.display_name)} ${statusTag}</h2>
        <div class="meta">${e.name} · ${e.source} · ${e.body_position || 'pos?'}</div>
        <div class="score-row">
          <span class="score-pill ${scoreCls}">POSE ${scoreDisplay}</span>
          ${e.overall_pass === true ? '<span class="chip pass">overall pass</span>' : ''}
          ${e.overall_pass === false ? '<span class="chip fail">overall fail</span>' : ''}
        </div>
        <div class="desc"><b>Description:</b> ${escapeHtml(e.pose_description || '(no description)')}</div>
        ${poseObs ? `<div class="obs"><b>Gemini saw:</b> ${escapeHtml(poseObs)}</div>` : ''}
        <div class="checks">${checkChips}</div>
        <div class="actions">
          <button class="${status==='pass'?'active pass':''}" onclick="mark('${e.name}','pass')">Pass</button>
          <button class="${status==='regen'?'active regen':''}" onclick="mark('${e.name}','regen')">Regen image</button>
          <button class="${status==='fixdesc'?'active fixdesc':''}" onclick="mark('${e.name}','fixdesc')">Fix description</button>
          <button class="${status==='skip'?'active skip':''}" onclick="mark('${e.name}','skip')">Skip</button>
        </div>
        <textarea class="notes" placeholder="Notes..."
          onchange="saveNotes('${e.name}', this.value)">${escapeHtml(e.review_notes || '')}</textarea>
      </div>
    </div>
  </div>`;
}

function escapeHtml(s) {
  return (s || '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
}

async function mark(name, status) {
  const entry = ALL.find(x => x.name === name);
  const notes = entry ? entry.review_notes : '';
  await fetch('/api/review', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({name, status, notes})
  });
  if (entry) entry.review_status = status;
  render();
}

async function saveNotes(name, notes) {
  const entry = ALL.find(x => x.name === name);
  const status = entry ? entry.review_status : 'unreviewed';
  if (entry) entry.review_notes = notes;
  await fetch('/api/review', {
    method: 'POST',
    headers: {'Content-Type':'application/json'},
    body: JSON.stringify({name, status: status === 'unreviewed' ? null : status, notes})
  });
}

['f-unrev','f-pass','f-regen','f-fixdesc','f-skip','f-lowscore']
  .forEach(id => document.getElementById(id).addEventListener('change', render));

// Auto-refresh every 10 s so QA sweep progress is visible
setInterval(refresh, 10000);
refresh();
</script>
</body>
</html>
"""


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        p = urlparse(self.path).path
        if p == "/":
            self._send(200, "text/html", HTML.encode())
        elif p == "/api/entries":
            self._send(200, "application/json", json.dumps(build_entries()).encode())
        elif p.startswith("/images/"):
            fname = p.replace("/images/", "")
            fp = OUTPUT_DIR / fname
            if fp.exists() and fp.suffix == ".png":
                self._send(200, "image/png", fp.read_bytes())
            else:
                self.send_error(404)
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path == "/api/review":
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length))
            name = body.get("name")
            status = body.get("status")
            notes = body.get("notes", "")
            if not name:
                self.send_error(400, "name required")
                return
            reviews = load_json(REVIEW_LOG, {})
            cur = reviews.get(name, {})
            if status is not None:
                cur["status"] = status
            cur["notes"] = notes
            reviews[name] = cur
            save_reviews(reviews)
            self._send(200, "application/json", b'{"ok":true}')
        else:
            self.send_error(404)

    def _send(self, code, ctype, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=5300)
    args = ap.parse_args()

    server = HTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://localhost:{args.port}"
    print(f"\n  Start Image Review UI running at {url}")
    print(f"  Reviews saved to: {REVIEW_LOG}\n")
    print(f"  Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")


if __name__ == "__main__":
    main()
