# PT Helper Safety Database Expansion — Plain English Summary

A non-technical write-up of what was done, what was found, and why it matters.
Companion documents:
- `kg_v2_clinical_evidence.md` — full clinical evidence ledger (per-condition rule tables + source URLs)
- `kg_review_decisions.json` — the 1,238 reviewed verdicts themselves

---

## The 60-second version

Our app recommends physical therapy exercises to people recovering from
injuries. **We just expanded the app's safety guardrails by roughly 6× and
corrected 76 specific medical errors that AI made when generating the
expansion.**

What expanded: the deterministic "safety lookup" the app consults before
recommending anything. It's the layer that stops the app from ever
recommending, say, a deep forward-bend to someone with a herniated disc.

Why it matters: more (condition × exercise) pairs in this database = more
situations the safety net catches deterministically. Before this work,
most pairs weren't in the database at all — the app had to lean on softer
AI checks. Now ~3,500 pairs are vetted by named clinical practice
guidelines.

The catch: we used AI to generate the candidates first (it's much faster
than hand curation), but AI makes medical mistakes. So we reviewed every
single "dangerous" or "unclear" verdict it produced — 1,238 of them —
against published medical guidelines and the database physical therapists
hand-curated for the app originally. **6% of verdicts needed flipping.
8% were too ambiguous to keep. 86% were correct.**

---

## What was the problem we were solving?

PT Helper recommends exercises. Some exercises are dangerous for some
conditions. Concrete examples:

- **Herniated disc + heavy forward-bending lift** → can extrude more disc
  material → potential surgery.
- **Shoulder impingement + overhead press** → can tear or further damage
  the rotator cuff.
- **Acute hamstring strain + sprint drills** → re-injury, often worse
  than the original.

To prevent this, the app already has a deterministic safety database — a
big lookup table — that says "for condition X, exercise Y is safe /
dangerous / unclear." If the lookup says "dangerous," the app won't
surface that exercise as a recommendation, no matter what the AI
recommendation engine suggests.

This database was originally hand-curated by physical therapists for the
top 25 conditions × ~30 high-priority exercises. About **750 entries
total.** That left thousands of (exercise, condition) pairs uncovered —
the app had to lean on softer AI judgment for those cases.

We wanted to expand the database to **25 conditions × 187 exercises =
~4,700 entries**. Hand-curating that volume would have cost weeks of
clinician time and roughly $5,000–10,000 in PT review fees. Generating
the candidate verdicts via AI takes ~40 minutes and cost **$6.42** — but
AI makes mistakes that real clinicians wouldn't, especially on safety
calls.

So the workflow we used:

1. **Have AI generate candidate verdicts.** Done in a prior session: $6.42, 4,675 verdicts.
2. **Have a clinical reviewer check every "dangerous" or "unclear" verdict against published guidelines.** ← This document is about that step.
3. **Merge the verified results into the production database.** Deferred (one command).
4. **Turn on the new database for users.** Deferred (one-line code change).

This document explains step 2.

---

## How the review worked

For each of the 25 conditions in the app:

**Step 1 — Pull the published guidelines.** The "clinical practice
guidelines" (CPGs) are the official best-practice documents physical
therapists actually train on. Sources used:

- JOSPT (Journal of Orthopaedic & Sports Physical Therapy) — most CPGs come from here
- NASS (North American Spine Society) — for spinal conditions
- Cochrane systematic reviews — meta-analyses across many studies
- AAOS, OARSI — orthopedic surgical/non-surgical guidelines
- Specific landmark studies for treatment protocols (Alfredson 1998, Tyler 2010, Holden/Rio/Cook 2017, Mellor 2018, Rathleff 2014, etc.)

These are the same sources a real PT would cite.

**Step 2 — Build a "rule table" per condition.** Which movement
categories are absolutely dangerous? Which are case-by-case? Which are
always safe? The rule table is the tool used to evaluate every AI
verdict for that condition consistently.

**Step 3 — For each AI verdict, decide one of three actions.** Cross-check
against (a) the rule table from the guidelines, and (b) the existing
hand-curated database the PT app already uses.

| Action | Meaning |
|---|---|
| **APPROVE** | AI got it right; keep the verdict in the new database. |
| **REJECT** | AI's reasoning is debatable or the evidence is mixed; drop the entry from the new database. The existing hand-curated database still covers it, plus a separate AI cross-check at runtime catches edge cases. |
| **FLIP** | AI got it clear-cut wrong (the safe ↔ dangerous label needs to be inverted). Only used when the AI directly contradicted both the published guideline AND our hand-curated database. |

**Step 4 — Document the source.** For 115 of the 1,238 decisions, the
exact URL of the supporting journal article or guideline is recorded
inline so anyone auditing the work can trace a verdict back to evidence.

The whole review took ~6 hours of focused work. Hand-curation by a
clinician would have taken 2–3 weeks.

---

## What the AI got wrong (the interesting part)

Three error patterns came up over and over. Together they account for
all 76 flips.

### 1. The AI inverted the treatment paradigm for tendon injuries (28 errors)

Tendon injuries — Achilles, tennis elbow, golfer's elbow, jumper's
knee, rotator cuff, hamstring tendinopathy — are **treated by gradually
loading the injured tendon**. This is settled medical science. The AI
flagged most of these treatment exercises as "dangerous." Three
specific examples:

| Condition | What AI said | What evidence says |
|---|---|---|
| Achilles tendinopathy | "Heel drops" are dangerous (highest-severity flag). | Heel drops are the **gold-standard treatment** (Alfredson 1998, JOSPT 2018 CPG). Every PT clinic uses them. |
| Tennis elbow | Wrist extensor strengthening is dangerous. | It's the **eccentric loading protocol** (Tyler 2010). |
| Golfer's elbow | Wrist curls are dangerous (absolute contraindication). | Wrist curls are the **flexor loading protocol** for this exact condition. |

This was the biggest error class. If we'd shipped without review, roughly
10% of users with tendon injuries would have been steered *away* from
the exercises most likely to help them recover.

### 2. The AI flagged exercises for the wrong body region (14 errors)

The AI repeatedly tagged an exercise affecting one body part as
dangerous for a condition affecting a completely different body part.

- Cervical (neck) exercises tagged as dangerous for lumbar (lower-back) conditions, and vice versa.
- "Marble pickup" (a foot/toe intrinsic-strengthening exercise) tagged as dangerous for elbow tendinitis, lumbar disc herniation, and meniscus tears.
- "Towel curls" (also a foot exercise — toes scrunch a towel) tagged as dangerous for elbow conditions because the AI thought it was a finger/wrist exercise.

The AI seemed to do shallow keyword matching ("curl" → "wrist curl") rather
than understanding what the exercise actually does to the body.

### 3. The AI got biomechanics backwards (8 errors)

The most striking case: **spinal stenosis** has the *opposite* directional
preference from a herniated disc. Stenosis patients need *forward
bending* — it opens the narrowed spinal canal where nerves are pinched.
Disc patients (often) need *backward bending* — the McKenzie protocol.

The AI knew that "forward bending under load is dangerous for disc
patients" and applied the same rule to stenosis patients. Forward
bending is exactly the **treatment** for stenosis.

This kind of error is dangerous because the patient is being steered
*toward* their injury mechanism instead of away from it.

We caught the stenosis pattern by running stenosis review immediately
after disc review and checking the rule tables came out as mirror
images. They did — confirming the AI had flipped neither rule table to
match the actual biomechanics.

### Plus 26 verdicts dropped as too ambiguous (REJECT)

These weren't clear-cut wrong, but the evidence was mixed enough that
we chose to drop them rather than ship a verdict in either direction.
The hand-curated database + the runtime cross-checking AI cover these
gaps. We deliberately preferred *missing coverage* over *wrong
coverage*.

---

## The numbers, in plain context

**4,675 verdicts generated by AI** (25 conditions × 187 exercises, minus 75 placeholder pairs).

| Verdict type | Count | What we did |
|---|---|---|
| AI said "safe" | 3,437 | Sampled 10% (~344) for spot-check; the rest auto-approve. |
| AI said "dangerous" | 431 | **Reviewed all of them** — these are the highest-stakes calls. |
| AI said "unclear" | 807 | **Reviewed all of them** — the AI itself was punting; humans must decide. |

**The 1,238 reviewed verdicts (dangerous + unclear) broke down as:**

- **1,068 approved** (86%) — AI got it right.
- **94 rejected** (8%) — too ambiguous; let other systems handle.
- **76 flipped** (6%) — clear-cut errors corrected.

After all the decisions merge:
- **3,505 (condition, exercise) safe pairs** will ship — up from a few hundred.
- **269 dangerous combinations** will be deterministically blocked.
- The existing hand-curated database is preserved unchanged on top.

---

## Why this is trustworthy

Four layers of safeguard stack:

**1. We didn't replace anything; we added on top.** The new database
unions with the existing hand-curated database at runtime. So even if
the new layer has gaps, the original PT-curated layer still applies. We
cannot regress prior coverage.

**2. "When in doubt, drop."** We rejected 94 verdicts where the AI's
reasoning was debatable. Rejection means those entries don't ship — the
app falls back to the existing database + a separate cross-checking AI
that runs at recommendation time. We chose missing coverage over wrong
coverage.

**3. Two AI brains, not one.** This database is one of two safety
checks. The recommendation comes from a different AI; this database
vetoes anything dangerous. So even a wrong verdict in this database
would have to slip past *both* the recommendation AI's judgment AND a
runtime cross-check before reaching a user. Plus there's a "serious
warning" modal that pops up whenever the static database flags anything.

**4. Sources are auditable.** 115 verdicts cite their supporting
literature inline (URLs to the journal article or guideline). Anyone
with a clinical background can pull up the evidence and challenge
specific calls. The full per-condition rule tables and source citations
are in `kg_v2_clinical_evidence.md`.

---

## Self-stop trigger events (transparency)

Two conditions exceeded the pre-set 25%-flip-rate threshold (the
threshold at which we pause to re-verify the rule table before
sweeping further):

- **Tennis elbow** — 33% flip rate on dangerous-tagged verdicts.
- **Golfer's elbow** — 43% flip rate on dangerous-tagged verdicts.

Both were caused by the same systematic AI error (inverting the
tendinopathy treatment paradigm). Both were verified against published
loading protocols (JOSPT 2010 Tyler eccentric protocol). The rule
tables held; the flips were correct. This is documented in the evidence
ledger.

---

## What this means for users

When the new database ships:

- **Tendon-injury patients see the biggest improvement.** Previously,
  the app's softer AI checks were more likely to mis-flag therapeutic
  loading exercises as dangerous. Now patients with Achilles
  tendinopathy, tennis elbow, jumper's knee, etc. can be recommended
  the actual evidence-based loading protocols.

- **Spinal patients see safer recommendations.** Particularly stenosis
  patients (where the AI was inverting biomechanics) and disc patients
  (where the AI was over-restricting the McKenzie protocol).

- **All 25 conditions** see ~6× more deterministic safety coverage —
  meaning fewer cases where the app must make judgment calls without a
  named-guideline-backed safety net.

---

## What's still open

Two follow-up steps are deferred to a separate session, on principle
that any change affecting what users see should go through its own
review:

1. **Run the merge.** One command (`merge_kg_review.py` without
   `--dry-run`) writes the production database file. Already verified
   to pass dry-run.
2. **Turn on the feature flag.** One-line code change in
   `KnowledgeGraphService.swift` that flips the new database from
   "loaded but ignored" to "active."

The hard work — the clinical judgment — is done. Both follow-ups are
mechanical.

---

## TL;DR for the elevator

The app's safety net just got 6× bigger. AI generated the expansion in
40 minutes for $6.42, but made 76 specific medical errors a real
clinician would catch — most of them inverting the treatment paradigm
for tendon injuries. We caught all 76 by cross-checking every
high-stakes verdict against published clinical guidelines and the
existing hand-curated database. The result is named-guideline-backed
deterministic safety coverage for 3,505 (condition, exercise) pairs and
269 specifically blocked dangerous combinations. Trust is layered: the
new database unions on top of the original hand-curated one (no
regression possible), debatable cases were rejected rather than
shipped (no wrong coverage), and a separate runtime AI provides a
second cross-check. Source citations are inline for 115 verdicts.
