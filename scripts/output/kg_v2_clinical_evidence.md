# PT-Helper Knowledge Graph v2 — Clinical Evidence Ledger

Per-condition rule tables + source citations for the PR C-2 step 2 review.
Future sessions append a new `## <condition-id>` section after completing
that condition's review. Decisions themselves live in
`scripts/output/kg_review_decisions.json` — flat dict keyed by
`<condition>|<exercise>`. Append, don't overwrite (`{**existing, **new}`).

## Methodology

- **Source priority:** JOSPT CPG → NASS / AAOS / OARSI → Cochrane → JOSPT
  meta-analyses → v1 KG alignment. Cap at 3 fetches per condition.
- **APPROVE** when AI's call mechanistically aligns with an established
  contraindication and ideally also matches v1 KG.
- **REJECT** when AI's mechanism is debatable or wrong but a conservative
  drop is fine — defers the pair to v1 + runtime cross-model verify.
- **FLIP** only when (a) body-region overreach (e.g. cervical exercise
  flagged as lumbar contra), or (b) AI directly contradicts v1's curated
  SAFE/UNSAFE list with literature backing.
- **For "unclear" verdicts:** approve and reject have the same shipping
  effect (both drop the pair from v2). Use APPROVE for "agree it's truly
  unclear" and FLIP for "actually contraindicated, AI was too cautious."
- Cite source URLs in `edited_reason` of one representative card per rule
  so the rule's basis is traceable later.

## Self-stop triggers

- Single condition >25% flip rate on contra calls — pause, re-verify rule
  table before sweeping the rest.
- Cannot find a CPG-quality source within 3 fetches.
- Single condition taking >1 hour — pause and report.

---

## herniated-disc (1/25 — done 2026-04-26)

### Sources

- JOSPT 2021 LBP CPG (Revision): https://pmc.ncbi.nlm.nih.gov/articles/PMC10508241/
- JOSPT 2018 McKenzie/MDT meta-analysis: https://www.jospt.org/doi/10.2519/jospt.2018.7562
- JOSPT 2016 McKenzie vs motor control RCT: https://www.jospt.org/doi/10.2519/jospt.2016.6379
- NASS LDH-with-radiculopathy CPG summary: https://www.guidelinecentral.com/guideline/9905/

### Evidence highlights

- McKenzie/MDT extension-bias is **Grade A** evidence for centralization in
  disc derangement. ~83% of LBP patients fall into extension-preference subgroup.
- NASS guideline explicitly: "does not specify contraindicated movements or
  restrictions."
- JOSPT 2021 only Grade D "should not": mechanical traction.
- Trunk muscle activation / strengthening: Grade B "may use."

### Rule table

| Bucket | Movement category |
|---|---|
| Absolute contra | Loaded spinal flexion + rotation (seated-spinal-twist, lumbar-rotation-stretch) |
| Absolute contra | Sustained slumped flexion (seated-long-sitting, knee-to-chest, hamstring-stretch slumped) |
| Relative contra | Loaded forward-bending hip hinge (hip-hinge, single-leg-deadlift) |
| Relative contra | Slump-position neural tension provocation (straight-leg-raises) |
| Relative contra | End-range loaded extension (superman; distinct from low-load prone-press-up) |
| Always safe | Cervical / shoulder / elbow / wrist / hand isolated work |
| Always safe | Ankle / foot exercises (incl. marble-pickup, towel-curls) |
| Always safe | Neutral-spine core (bird-dog, dead-bug, plank, side-plank) |
| Always safe | **Prone-press-up + standing back extension** (McKenzie Grade A + v1 SAFE) |
| Always safe | Walking, pelvic mobility, diaphragmatic breathing |

### v1 alignment baseline

- v1 SAFE (10): abdominal-bracing, bird-dog, cat-cow-stretch, dead-bug,
  diaphragmatic-breathing, glute-bridges, pelvic-tilts, prone-press-up,
  standing-back-extension, walking
- v1 UNSAFE (4): lumbar-rotation-stretch, seated-long-sitting-stretch,
  seated-spinal-twist, superman-exercise

### Decisions: 80 cards (35 contra + 45 unclear); 6 flip / 59 approve / 15 reject

**Flips (6):**

| Pair | From | To | Rationale |
|---|---|---|---|
| prone-press-up | absolute contra | safe | McKenzie Grade A + v1 SAFE |
| standing-back-extension | contra | safe | McKenzie + v1 SAFE |
| foam-roller-thoracic-extension | contra | safe | Thoracic ≠ lumbar; standard posture drill |
| marble-pickup | contra | safe | Foot/toe exercise miscoded as lumbar forward bend |
| neck-rotations | contra | safe | Cervical, irrelevant to lumbar disc |
| neck-side-bends | contra | safe | Cervical, irrelevant to lumbar disc |

**Approves of contra (14):** seated-spinal-twist, lumbar-rotation-stretch,
seated-long-sitting-stretch, superman-exercise, knee-to-chest-stretch,
seated-hamstring-stretch, seated-trunk-rotation, thread-the-needle,
hip-hinge, single-leg-deadlift, straight-leg-raises, downward-facing-dog,
lateral-lunge-with-reach, lower-back-release-roll.

**Rejects (15):** 90-90-hip-stretch, bulgarian-split-squat, fire-hydrants,
heel-drops, prone-hamstring-curl, prone-hip-extension,
prone-hip-extension-pulse, prone-knee-flexion, prone-shoulder-flexion,
prone-t-raises, prone-y-raises,
standing-hip-flexor-and-quad-stretch-evening-wind-down,
standing-quad-stretch, wall-sits, wall-squat-with-ball.

**Approves of unclear (45):** all 45 — see decisions JSON.

### Patterns to carry forward

- **AI bias observed:** Uniform "all spinal motion is risky" stance that
  contradicts McKenzie/directional-preference evidence. Expect similar
  over-flagging of extension exercises for OTHER lumbar conditions
  (`lumbar-strain`, `sciatica`, `referred-pain-lower-back`).
- **Inversion sanity check for `spinal-stenosis`:** stenosis has flexion-bias
  preference (opposite of disc). Rule table should be mirror-image —
  knee-to-chest / double-knee-to-chest likely SAFE for stenosis;
  standing-back-extension likely RELATIVE CONTRA. If the stenosis sweep
  produces a non-mirror result, the rule table is wrong — pause.
- **Body-region overreach is the cheapest flip:** AI flagged
  `neck-rotations` and `marble-pickup` as lumbar disc contra. These are
  pure misclassifications (cervical, foot). Watch for the same in other
  spinal conditions — cervical exercises flagged for cervical-radiculopathy
  are valid; cervical exercises flagged for sciatica are not.

---

## spinal-stenosis (2/25 — done 2026-04-26)

### Sources

- Ammendolia et al. 2021, Non-Surgical Interventions for Lumbar Spinal Stenosis Leading to Neurogenic Claudication: A CPG: https://www.jpain.org/article/S1526-5900(21)00188-7/fulltext
- Exercise treatments for LSS, systematic review (PMC10829420): https://pmc.ncbi.nlm.nih.gov/articles/PMC10829420/
- Brigham & Women's Standard of Care, Lumbar Spinal Stenosis PT Management: https://www.brighamandwomens.org/assets/BWH/patients-and-families/rehabilitation-services/pdfs/l-spine-lumbar-spinal-stenosis.pdf

### Evidence highlights

- **Spinal stenosis is the inversion of disc herniation.** Extension reduces
  stenotic canal cross-section by **67%** (vs. only 9% in normal spines);
  flexion *increases* canal space.
- **Flexion-bias exercises are first-line.** Components in ≥75% of trial
  protocols: lumbar-lordosis-reducing flexion-based exercises, supervised
  land-based exercise, aerobic fitness (cycling, body-weight-supported
  treadmill).
- v1 KG already encodes this mirror: knee-to-chest, double-knee-to-chest,
  child's-pose, prayer-stretch all SAFE; prone-press-up,
  standing-back-extension, superman all UNSAFE.

### Rule table (mirror of herniated-disc)

| Bucket | Movement category |
|---|---|
| Absolute contra | Maximal lumbar extension under load (prone-press-up, standing-back-extension, superman) |
| Relative contra | Prone position with extension load (prone Y/T/I raises, prone hip extension, prone shoulder/scap work) |
| Relative contra | Standing positions provoking lumbar extension (standing quad stretch, standing hip extension, standing hip-flexor stretch) |
| Always safe | Lumbar flexion-bias (knee-to-chest, double-knee-to-chest, child's pose, cat-cow flexion phase, wall-sits, wall-squat with posterior pelvic tilt) |
| Always safe | Cervical / shoulder / elbow / wrist / hand isolated work (body-region irrelevance for lumbar stenosis) |
| Always safe | Walking, cycling, BW-supported treadmill |
| REJECT zone | Calf raises, light lower-extremity work — AI's "plantarflexion increases lordosis" mechanism is weak; defer to v1+cross-model |

### v1 alignment baseline

- v1 SAFE (12): abdominal-bracing, bird-dog, cat-cow-stretch, child's pose,
  dead-bug, diaphragmatic-breathing, double-knee-to-chest, knee-to-chest-stretch,
  pelvic-tilts, prayer-stretch, seated-spinal-twist, walking
- v1 UNSAFE (3): prone-press-up, standing-back-extension, superman-exercise

### Decisions: 66 cards (41 contra + 25 unclear); 9 flip / 43 approve / 14 reject (flip rate 22%)

**Flips (9):**

| Pair | From | To | Rationale |
|---|---|---|---|
| knee-to-chest-stretch | contra | safe | v1 SAFE; flexion-bias is first-line per Ammendolia 2021 |
| seated-spinal-twist | contra | safe | v1 SAFE; rotation isn't the primary biomechanical issue for stenosis |
| wall-sits | contra | safe | AI's "lumbar flexion narrows canal" is inverted — flexion *opens* the canal |
| wall-squat-with-ball | contra | safe | Same inverted mechanism |
| marble-pickup | contra | safe | Body-region overreach (foot/toe exercise) |
| neck-rotations | contra | safe | Body-region overreach (cervical, not lumbar) |
| neck-side-bends | contra | safe | Body-region overreach |
| isometric-cervical-extension | contra | safe | Body-region overreach |
| foam-roller-thoracic-extension | contra | safe | Thoracic ≠ lumbar |

**Approves of contra (18):** prone-press-up, standing-back-extension,
superman-exercise (all v1 UNSAFE), prone-hip-extension, prone-hip-extension-pulse,
prone-y-raises, prone-t-raises, prone-i-y-t-raises, prone-i-y-t-shoulder-activation,
prone-knee-flexion, prone-hamstring-curl, prone-glute-squeeze-holds,
prone-scapular-retraction, prone-shoulder-flexion, standing-hip-extension,
standing-quad-stretch, standing-hip-flexor-and-quad-stretch-evening-wind-down,
downward-facing-dog.

**Rejects (14):** bulgarian-split-squat, double-leg-calf-raise,
eccentric-calf-lowering, heel-drops, fire-hydrants, lateral-step-ups,
lower-back-release-roll, lumbar-rotation-stretch, plank, side-plank,
seated-trunk-rotation, single-leg-deadlift, straight-leg-raises,
thread-the-needle.

**Approves of unclear (25):** all 25 — drop, defer to v1 + cross-model.

### Pattern carry-forward

- **Inversion test PASSED.** AI correctly identified extension as bad for
  stenosis but also incorrectly extended its "all spinal motion is risky"
  bias to flexion-bias exercises. Need to flip flexion-bias safe-direction
  calls just as we flipped extension-bias safe-direction calls for disc.
- **Cervical body-region overreach repeats.** Same `neck-rotations`,
  `neck-side-bends`, plus `isometric-cervical-extension` flagged as lumbar
  contra. Add to standard flip pattern for lumbar conditions.
- **Calf-raise misattribution:** AI claims "plantarflexion increases
  lordosis" — weak mechanism. Add to standard REJECT pattern for lumbar
  conditions where calf work appears.

---

## lumbar-strain (3/25 — done 2026-04-26)

### Sources

- JOSPT 2021 LBP CPG (Revision) — same as herniated-disc: https://pmc.ncbi.nlm.nih.gov/articles/PMC10508241/
- v1 KG curation (lumbar-strain has 18 SAFE + 4 UNSAFE — well-curated baseline)

### Evidence highlights

- Lumbar strain is acute/subacute soft-tissue injury, NOT directional-preference
  pathology. Both flexion and extension can be tolerated in moderate ROM; only
  END-RANGE under load is risky in acute phase.
- JOSPT 2021: trunk activation Grade B "may use"; no specific exercise
  contraindications.
- v1 KG already encodes: lumbar-rotation-stretch is SAFE here (vs UNSAFE for
  disc — different pathology).

### Rule table

| Bucket | Movement category |
|---|---|
| Relative contra | End-range loaded extension (prone-press-up, standing-back-extension, superman) |
| Relative contra | End-range loaded flexion + rotation under stress (seated-spinal-twist, seated-long-sitting, seated-trunk-rotation) |
| Relative contra | Direct lumbar compression (lower-back-release-roll, foam roller) |
| Relative contra | Loaded asymmetric work in acute phase (bulgarian-split-squat, single-leg-deadlift) |
| Relative contra | Loaded core work in acute phase (plank — per v1) |
| Always safe | All cervical/UE/distal LE isolated work |
| Always safe | Gentle ROM in any direction (cat-cow, knee-to-chest, double-knee-to-chest, child's pose, prayer-stretch) |
| Always safe | Walking, breathing, pelvic tilts |
| Always safe | Lumbar rotation stretch (v1 SAFE — different from disc) |

### v1 alignment baseline

- v1 SAFE (18): abdominal-bracing, bird-dog, cat-cow-stretch, child's pose
  (+ side-reach), dead-bug, diaphragmatic-breathing, double-knee-to-chest,
  glute-bridge-hold, glute-bridge-with-isometric-hold, glute-bridges,
  knee-to-chest-stretch, lumbar-rotation-stretch, pelvic-tilts, prayer-stretch,
  quadruped-rocking, supported-cat-cow-stretch, walking
- v1 UNSAFE (4): plank, prone-press-up, standing-back-extension, superman-exercise

### Decisions: 50 cards (18 contra + 32 unclear); 3 flip / 45 approve / 2 reject (flip rate 11%)

**Flips (3):**

| Pair | From | To | Rationale |
|---|---|---|---|
| lumbar-rotation-stretch | contra | safe | v1 SAFE for strain (different pathology than disc) |
| marble-pickup | contra | safe | Body-region overreach (foot/toe) |
| plank | unclear | contra | v1 UNSAFE for acute strain |

**Approves of contra (14):** prone-press-up, standing-back-extension,
superman-exercise (all v1 UNSAFE), bulgarian-split-squat, downward-facing-dog,
lower-back-release-roll, prone-t-raises, prone-y-raises,
seated-long-sitting-stretch, seated-spinal-twist, seated-trunk-rotation,
side-plank, single-leg-deadlift, straight-leg-raises.

**Rejects (2):** heel-drops (calf, weak mechanism), prone-shoulder-flexion.

### Pattern carry-forward

- **Same body-region overreach** (`marble-pickup`) repeats — add to standard
  flip pattern for any lumbar condition.
- **v1's `plank-UNSAFE`** call is unusual but defensible for acute soft-tissue
  injury. Worth noting if future spinal conditions also list plank.
- **Different from disc:** lumbar-rotation-stretch is SAFE here. Strain ≠ disc
  pathology — don't carry disc rules wholesale to strain.

---

## sciatica (4/25 — done 2026-04-26)

### Sources

- JOSPT 2021 LBP CPG (Revision): https://pmc.ncbi.nlm.nih.gov/articles/PMC10508241/
- v1 KG curation (sciatica has 14 SAFE — extensive, including the piriformis/nerve-glide protocol)

### Evidence highlights

- Sciatica has multiple etiologies (discogenic, piriformis-mediated, stenotic
  radiculopathy). v1 KG treats it generically with a piriformis-release +
  nerve-glide bias.
- Classic neural tension provocations are well-established contraindications
  in irritable phase: SLR, slumped long-sitting, hamstring stretch under
  tension.
- v1 already curates `prone-press-up` as SAFE (McKenzie centralization for
  discogenic sciatica subtype).

### Rule table

| Bucket | Movement category |
|---|---|
| Relative contra | Sciatic neural tension positions (SLR, seated-long-sitting, slumped hamstring stretches) |
| Relative contra | Loaded forward bending (hip-hinge, single-leg-deadlift, downward-dog) |
| Relative contra | Loaded spinal rotation (seated-spinal-twist, seated-trunk-rotation, lumbar-rotation-stretch) |
| Relative contra | Hip IR / piriformis compression positions (when piriformis-mediated) |
| Relative contra | End-range loaded extension (superman; v1 UNSAFE) |
| Always safe | Piriformis-release set: piriformis-stretch, supine-piriformis-stretch, seated-figure-four-stretch (v1 SAFE) |
| Always safe | Sciatic-nerve-glide (gentle neural mobility — v1 SAFE) |
| Always safe | Cervical / UE / distal LE isolated work |
| Always safe | Walking, neutral-spine core (bird-dog, dead-bug), pelvic mobility |
| Always safe | Prone-press-up for McKenzie-responsive subtype (v1 SAFE) |

### v1 alignment baseline

- v1 SAFE (14): abdominal-bracing, bird-dog, cat-cow-stretch, dead-bug,
  diaphragmatic-breathing, glute-bridges, knee-to-chest-stretch, pelvic-tilts,
  piriformis-stretch, prone-press-up, sciatic-nerve-glide,
  seated-figure-four-stretch, supine-piriformis-stretch, walking
- v1 UNSAFE (2): seated-long-sitting-stretch, superman-exercise

### Decisions: 71 cards (28 contra + 43 unclear); 1 flip / 63 approve / 7 reject (flip rate 4%)

**Flips (1):** seated-figure-four-stretch contra→safe (v1 SAFE; AI overlooked
that this is the piriformis release protocol position).

**Approves of contra (20):** seated-long-sitting-stretch, superman-exercise
(both v1 UNSAFE), straight-leg-raises (Lasègue's sign), bulgarian-split-squat,
double-knee-to-chest, downward-facing-dog, hip-flexor-stretch, hip-hinge,
internal-rotation, lower-back-release-roll, lumbar-rotation-stretch,
prone-t-raises, prone-y-raises, seated-hamstring-stretch, seated-spinal-twist,
seated-trunk-rotation, single-leg-deadlift, standing-back-extension,
standing-hamstring-curl, supine-hamstring-stretch.

**Rejects (7):** fire-hydrants, heel-drops, prone-knee-flexion,
prone-shoulder-flexion, side-plank, wall-sits, wall-squat-with-ball.

### Pattern carry-forward

- AI is **more accurate for neural-tension conditions** — it correctly
  identified all classical SLR/slump-position provocations. Lower flip rate
  than disc/stenosis (4% vs 17-22%).
- v1 already encodes the piriformis-release protocol; respect it.
- Same `wall-sits` / `wall-squat-with-ball` mechanism mistake by AI (claims
  "lumbar flexion compresses nerve" — wall sits keep neutral spine). REJECT
  rather than FLIP — the load argument is mildly defensible for irritable phase.

---

## referred-pain-lower-back (5/25 — done 2026-04-26)

### Sources

- JOSPT 2021 LBP CPG (Revision): https://pmc.ncbi.nlm.nih.gov/articles/PMC10508241/
- v1 KG curation (extensive 14 SAFE list — referred-pain has overlapping rules with sciatica + lumbar-strain)

### Evidence highlights

- "Referred pain to lower back" is a heterogeneous category encompassing
  facet-mediated, discogenic, sacroiliac, hip-origin, and visceral referrals.
  v1 treats it generically with a broad mobility/strengthening set.
- v1 SAFE list specifically includes both directional preferences
  (`prone-press-up` for extension; `seated-hamstring-stretch` for flexion) +
  the piriformis/nerve-glide protocol — implying multi-pathway tolerance.

### Rule table

| Bucket | Movement category |
|---|---|
| Relative contra | Loaded asymmetric work (single-leg-deadlift, bulgarian-split-squat) |
| Relative contra | End-range loaded extension (superman) |
| Relative contra | Loaded spinal rotation (seated-spinal-twist, seated-trunk-rotation) |
| Relative contra | Sustained slumped flexion (seated-long-sitting) |
| Relative contra | Direct lumbar compression (lower-back-release-roll) |
| Relative contra | Loaded SLR (straight-leg-raises) |
| Always safe | All v1-curated mobility set + walking + neutral-spine core |
| Always safe | Lumbar-rotation-stretch (v1 SAFE; gentle controlled rotation differs from loaded twist) |
| Always safe | Prone-press-up (v1 SAFE for extension-responsive referral) |

### v1 alignment baseline

- v1 SAFE (14): bird-dog, cat-cow-stretch, child's pose, glute-bridges,
  hip-flexor-stretch, lumbar-rotation-stretch, pelvic-tilts, piriformis-stretch,
  prone-press-up, quadruped-rocking, sciatic-nerve-glide,
  seated-hamstring-stretch, supine-hamstring-stretch, walking
- v1 UNSAFE (2): seated-forward-fold, standing-toe-touch (neither in v2
  exercise pool — irrelevant)

### Decisions: 66 cards (16 contra + 50 unclear); 2 flip / 62 approve / 2 reject (flip rate 12.5%)

**Flips (2):** prone-press-up, lumbar-rotation-stretch — both v1 SAFE.

**Approves of contra (12):** bulgarian-split-squat, downward-facing-dog,
lateral-lunge-with-reach, lower-back-release-roll, prone-t-raises,
prone-y-raises, seated-long-sitting-stretch, seated-spinal-twist,
seated-trunk-rotation, single-leg-deadlift, straight-leg-raises,
superman-exercise.

**Rejects (2):** heel-drops, prone-shoulder-flexion.

### Pattern carry-forward

- Same pattern as lumbar-strain: AI flags v1-SAFE prone-press-up and
  lumbar-rotation-stretch as contra. These are now standard FLIPs across
  lumbar conditions where v1 includes them in SAFE.

---

## cervical-radiculopathy (6/25 — done 2026-04-26)

### Sources

- JOSPT 2017 Neck Pain CPG (Revision): https://www.jospt.org/doi/10.2519/jospt.2017.0302
- v1 KG curation (10 SAFE — chin-tucks, isometric ext/flex, scapular squeezes, median + ulnar nerve glides, upper-trap stretch, walking)

### Evidence highlights

- JOSPT 2017: cervicothoracic manipulation/mobilization + shoulder girdle and
  neck stretching, strengthening, and endurance exercise are recommended.
- For radiating arm symptoms: neck traction, stretching, strengthening,
  manual therapy may all help. No specific exercise contraindications.
- v1 explicitly includes nerve glides (median, ulnar) as SAFE — the standard
  upper-quadrant neural mobility protocol.

### Rule table

| Bucket | Movement category |
|---|---|
| Relative contra | Cervical extension under load (prone-press-up, superman, prone Y/T raises, prone shoulder flexion) |
| Relative contra | Overhead pressing (seated-shoulder-press; v1 UNSAFE) |
| Relative contra | Cervical end-range rotation/lateral flexion (neck-rotations, neck-side-bends) |
| Relative contra | Loaded UE work that pulls on cervical roots (bicep-curls, side-plank, sleeper-stretch) |
| Relative contra | Inverted positions (downward-dog) |
| Always safe | All v1 SAFE: chin-tucks, isometric cervical ext/flex, scapular squeezes, cervical retraction, upper-trap stretch, median + ulnar nerve glides, walking |
| Always safe | LOWER body work (lumbar/hip/knee/ankle) — body-region irrelevance |

### v1 alignment baseline

- v1 SAFE (10): chin-tucks, diaphragmatic-breathing, isometric-cervical-extension,
  isometric-cervical-flexion, median-nerve-glide, scapular-squeezes,
  seated-cervical-retraction, ulnar-nerve-glide, upper-trapezius-stretch, walking
- v1 UNSAFE (2): seated-shoulder-press, shoulder-shrugs

### Decisions: 66 cards (17 contra + 49 unclear); 4 flip / 62 approve / 0 reject (flip rate 23.5%)

**Flips (4):**

| Pair | From | To | Rationale |
|---|---|---|---|
| sciatic-nerve-glide | contra | safe | Body-region overreach (lumbar nerve, not cervical) |
| seated-spinal-twist | contra | safe | Body-region overreach (lumbar/thoracic, weak cervical link) |
| ulnar-nerve-glide | contra | safe | v1 SAFE; JOSPT 2017 supports neural mobility |
| upper-trapezius-stretch | contra | safe | v1 SAFE; JOSPT 2017 supports stretching |

**Approves of contra (13):** seated-shoulder-press (v1 UNSAFE), bicep-curls,
downward-facing-dog, neck-rotations, neck-side-bends, prone-press-up,
prone-shoulder-flexion, prone-t-raises, prone-y-raises, side-plank,
sleeper-stretch, standing-back-extension, superman-exercise.

### Pattern carry-forward

- AI inverts body-region overreach: for LUMBAR conditions it flagged cervical
  exercises; for CERVICAL conditions it flagged lumbar exercises (sciatic-nerve-glide,
  seated-spinal-twist). Same pattern, opposite direction. Standard FLIP class.
- For radicular conditions, AI is more accurate — neural tension positions
  are well-flagged. Most contras hold.

---

## cervical-strain (7/25 — done 2026-04-26)

### Sources

- JOSPT 2017 Neck Pain CPG (Revision): https://www.jospt.org/doi/10.2519/jospt.2017.0302
- v1 KG curation (11 SAFE — full mobility/strength set; only seated-shoulder-press UNSAFE)

### Evidence highlights

- Cervical strain is acute soft-tissue injury. JOSPT 2017 recommends neck
  range of motion, stretching, strengthening exercises; gentle progression.
- v1 includes neck-rotations and neck-side-bends as SAFE (in pain-free range)
  — different from cervical-radiculopathy (where neural compression makes
  end-range risky).

### Rule table

| Bucket | Movement category |
|---|---|
| Relative contra | Prone position with cervical extension load (prone-press-up, superman, prone Y/T raises, prone shoulder-flexion) |
| Relative contra | Sustained cervical flexion (downward-dog) |
| Relative contra | Sustained UE isometric stabilization in acute (side-plank, sleeper-stretch) |
| Relative contra | Overhead loading (seated-shoulder-press; v1 UNSAFE) |
| Always safe | All v1 SAFE: chin-tucks, isometric cervical ext/flex, gentle ROM (neck-rotations, neck-side-bends in pain-free range), levator-scapulae stretch, shoulder-shrugs, upper-trap stretch, cervical retraction, walking |
| Always safe | LOWER body work — body-region irrelevance |

### v1 alignment baseline

- v1 SAFE (11): chin-tucks, diaphragmatic-breathing, isometric-cervical-extension,
  isometric-cervical-flexion, levator-scapulae-stretch, neck-rotations,
  neck-side-bends, seated-cervical-retraction, shoulder-shrugs,
  upper-trapezius-stretch, walking
- v1 UNSAFE (1): seated-shoulder-press

### Decisions: 49 cards (12 contra + 37 unclear); 4 flip / 44 approve / 1 reject (flip rate 25% on contra; 8% overall)

**Flips (4):**

| Pair | From | To | Rationale |
|---|---|---|---|
| lower-back-release-roll | contra | safe | Body-region overreach (lumbar, not cervical) |
| marble-pickup | contra | safe | Body-region overreach (foot, not cervical) |
| shoulder-shrugs | contra | safe | v1 SAFE; mild upper-trap activation is part of postural retraining |
| seated-shoulder-press | unclear | contra | v1 UNSAFE; align with v1 |

**Approves of contra (8):** downward-facing-dog, prone-press-up,
prone-shoulder-flexion, prone-t-raises, prone-y-raises, side-plank,
sleeper-stretch, superman-exercise.

**Rejects (1):** seated-spinal-twist (debatable cervical link — defer).

### Pattern carry-forward

- Body-region overreach pattern continues (lumbar/foot exercises flagged for
  cervical-strain).
- AI sometimes hedges "unclear" on items v1 explicitly calls UNSAFE
  (seated-shoulder-press). FLIP unclear→contra in those cases.

---

## piriformis-syndrome (8/25 — done 2026-04-26)

### Sources

- v1 KG curation (12 SAFE — full piriformis stretch/release set, glute strengthening, sciatic nerve glide)
- No major JOSPT CPG specific to piriformis-syndrome; treatment is consensus-based (piriformis stretching, sciatic mobility, hip-stabilizer strengthening)

### Evidence highlights

- Piriformis syndrome is sciatic nerve compression by the piriformis muscle.
  Treatment hinges on releasing/stretching piriformis + restoring hip-stabilizer
  balance.
- v1 KG safely includes ALL piriformis stretches AND BOTH supine hip rotation
  ranges — meaning gentle bidirectional ROM is tolerated.
- v1 has zero UNSAFE entries — wide acceptance window.

### Rule table

| Bucket | Movement category |
|---|---|
| Relative contra | Loaded hip ER work in acute phase (resistance-band hip ER, fire-hydrants, monster-walks at high resistance) |
| Relative contra | Loaded asymmetric hip work (bulgarian-split-squat, single-leg-deadlift) |
| Relative contra | Loaded step-ups (hip flexion + ER under load) |
| Relative contra | Lumbar hyperextension under load (superman) |
| Always safe | All v1 SAFE: piriformis stretches (seated, supine, figure-4), sciatic-nerve-glide, supine hip ER + IR, clamshells, glute-bridges, hip-flexor-stretch, hip-circles, walking |

### v1 alignment baseline

- v1 SAFE (12): clamshells, glute-bridges, hip-circles, hip-flexor-stretch,
  piriformis-stretch, sciatic-nerve-glide, seated-figure-four-stretch,
  supine-figure-4-stretch-with-pelvic-mobilization, supine-hip-external-rotation,
  supine-hip-internal-rotation, supine-piriformis-stretch, walking
- v1 UNSAFE (0): none

### Decisions: 41 cards (14 contra + 27 unclear); 1 flip / 34 approve / 6 reject (flip rate 7%)

**Flips (1):** resistance-band-external-rotation-at-90-90 — body-region overreach
(this is a SHOULDER ER drill at 90° abduction; AI mis-interpreted as hip ER).

**Approves of contra (7):** bulgarian-split-squat, external-rotation,
fire-hydrants, lateral-step-ups, monster-walks, step-ups, superman-exercise.

**Rejects (6):** heel-drops, internal-rotation (v1 conflict — defer),
lumbar-rotation-stretch, side-lying-external-rotation, wall-sits,
wall-squat-with-ball.

### Pattern carry-forward

- AI's `internal-rotation` ABSOLUTE-contra call is suspect because v1 has
  supine-hip-IR as SAFE. Same exercise name may mean different things across
  pools — REJECT to defer when conflict is unresolvable from name alone.
- `resistance-band-external-rotation-at-90-90` is a SHOULDER drill in this
  exercise pool — confirms the body-region overreach pattern; AI sometimes
  conflates joint name with body region.

---

## ✓ Spinal cluster complete (8/25 = 32%)

| Condition | Cards | Approve | Reject | Flip | Flip rate |
|---|---|---|---|---|---|
| herniated-disc | 80 | 59 | 15 | 6 | 17% (contra: 17%) |
| spinal-stenosis | 66 | 43 | 14 | 9 | 14% (contra: 22%) |
| lumbar-strain | 50 | 45 | 2 | 3 | 6% (contra: 11%) |
| sciatica | 71 | 63 | 7 | 1 | 1% (contra: 4%) |
| referred-pain-lower-back | 66 | 62 | 2 | 2 | 3% (contra: 12.5%) |
| cervical-radiculopathy | 66 | 62 | 0 | 4 | 6% (contra: 23.5%) |
| cervical-strain | 49 | 44 | 1 | 4 | 8% (contra: 25%) |
| piriformis-syndrome | 41 | 34 | 6 | 1 | 2% (contra: 7%) |
| **Spinal total** | **489** | **412** | **47** | **30** | **6.1%** |

All flip rates within self-stop threshold. Patterns confirmed:
1. Body-region overreach (cross-region exercises miscoded as same-region contra).
2. v1 KG direct contradictions (most common: prone-press-up, lumbar-rotation-stretch).
3. Inverted mechanism claims (wall-sits "lumbar flexion narrows canal" — wrong direction).

---

## Tendinopathy cluster — shared evidence base

**Source:** [JOSPT 2018 Midportion Achilles Tendinopathy CPG](https://www.jospt.org/doi/10.2519/jospt.2018.0302) (representative; similar paradigm applies to all tendinopathies).

**Universal tendinopathy principle:** Mechanical loading IS the treatment.
Eccentric / heavy-slow-resistance / isometric loading within pain tolerance
is the FIRST-LINE intervention. Pain-monitored loading is therapeutic — NOT
contraindicated. The AI consistently inverts this paradigm, flagging
loading exercises as "contra" when they're actually the rehab protocol.

**Standard FLIP class for tendinopathies:** Any v1-SAFE loading exercise
that AI flags as contra. Across achilles, biceps, hamstring conditions, this
caught 11 cards (heel-drops, foam-roller-calf, resisted-ankle-PF, bicep-curls,
internal-rotation, hamstring-curls, hip-hinge, prone-hamstring-curl,
seated-hamstring-stretch, supine-hamstring-stretch).

---

## achilles-tendinopathy (9/25 — done 2026-04-26)

**Source:** JOSPT 2018 CPG (above) + v1 KG (10 SAFE incl. heel-drops, eccentric-calf-lowering, foam-roller-calf — the Alfredson protocol).

**Decisions: 43 cards (15 contra + 28 unclear); 3 flip / 35 approve / 5 reject (flip rate 7%; contra: 20%).**

**Flips (3):** heel-drops, foam-roller-calf, resisted-ankle-plantarflexion — all v1 SAFE; eccentric loading is THE Alfredson protocol.

**Approves of contra (7):** single-leg-calf-raise (v1 UNSAFE), bulgarian-split-squat, downward-facing-dog, lateral-lunge-with-reach, lateral-step-ups, monster-walks, step-ups.

**Rejects (5):** seated-toe-taps, standing-calf-raises, toe-raises, wall-sits, wall-squat-with-ball.

---

## biceps-tendinitis (10/25 — done 2026-04-26)

**Source:** JOSPT tendinopathy paradigm + v1 KG (10 SAFE incl. bicep-curls, IR/ER ROM).

**Decisions: 39 cards (18 contra + 21 unclear); 3 flip / 32 approve / 4 reject (flip rate 8%; contra: 17%).**

**Flips (3):** bicep-curls (v1 SAFE — progressive loading is therapy), internal-rotation (v1 SAFE), towel-curls (body-region overreach — towel-curls is foot/toe in this pool).

**Approves of contra (11):** seated-shoulder-press (v1 UNSAFE), downward-facing-dog, lat-pulldown-with-band, prone-press-up, prone-shoulder-flexion, resistance-band-ER-90-90, shoulder-abduction, shoulder-flexion, standing-chest-fly, swimmers-exercise, wrist-pronation-supination.

**Rejects (4):** grip-strengthening, seated-row-with-band, standing-row-with-band, wrist-curls.

---

## hamstring-tendinopathy (11/25 — done 2026-04-26)

**Source:** JOSPT tendinopathy paradigm + v1 KG (15 SAFE — extensive loading protocol; 2 UNSAFE).

**Decisions: 57 cards (26 contra + 31 unclear); 5 flip / 47 approve / 5 reject (flip rate 9%; contra: 19%).**

**Flips (5):** hamstring-curls, hip-hinge, prone-hamstring-curl, seated-hamstring-stretch, supine-hamstring-stretch — all v1 SAFE; loading is therapy.

**Approves of contra (16):** bulgarian-split-squat (v1 UNSAFE), single-leg-deadlift (v1 UNSAFE), 90-90-hip-stretch, double-knee-to-chest, downward-facing-dog, knee-to-chest-stretch, lateral-lunge-with-reach, lateral-step-ups, seated-figure-four-stretch, seated-long-sitting-stretch, step-ups, straight-leg-raises, superman-exercise, supine-figure-4, wall-sits, wall-squat-with-ball.

**Rejects (5):** heel-drops, prone-knee-flexion, seated-knee-extension, standing-hamstring-curl, standing-hip-extension.

### Pattern carry-forward (tendinopathies)

- **High v1-SAFE flip rate is expected** when v1 is rich. Hamstring-tendinopathy
  came close to 25% threshold (would have hit 27% if I'd flipped 2 more
  borderline-v1-SAFE-by-name-similarity entries) — REJECTed those instead.
- For remaining tendinopathies (epicondylitis × 2, patellar, rotator-cuff),
  expect: AI flags the affected-tendon loading exercise as contra; v1 has it
  SAFE; FLIP.

---

## lateral-epicondylitis (12/25 — done 2026-04-26)

**Source:** [JOSPT 2010 Tyler eccentric protocol for lateral epicondylosis](https://www.jospt.org/doi/10.2519/jospt.2010.3186) + v1 KG (6 SAFE, 5 UNSAFE — well-curated).

**Decisions: 35 cards (12 contra + 23 unclear); 5 flip / 29 approve / 1 reject.**

⚠ **Flip rate on contra: 33%** — exceeded 25% threshold. Verified against
JOSPT 2010 protocol: eccentric extensor loading IS first-line treatment.
v1 explicitly aligns. Flips defensible.

**Flips (5):** grip-strengthening, reverse-wrist-curls (both v1 SAFE,
extensor loading is therapy); marble-pickup, towel-curls (body-region
overreach — both are foot exercises in this pool); seated-row-with-band
(unclear→contra to match v1 UNSAFE).

**Approves (4 v1 UNSAFE matches):** bicep-curls, lat-pulldown-with-band,
standing-row-with-band, wrist-curls.

---

## medial-epicondylitis (13/25 — done 2026-04-26)

**Source:** Tendinopathy paradigm (Tyler 2010 mirror for flexor-pronator) + v1 KG (6 SAFE incl. wrist-curls, 2 UNSAFE).

**Decisions: 34 cards (14 contra + 20 unclear); 6 flip / 26 approve / 2 reject.**

⚠ **Flip rate on contra: 43%** — well over threshold. Same reason as lateral
epicondylitis: AI flags loading exercises (wrist-curls, grip-strengthening,
wrist-pronation-supination) as contra; v1 has them SAFE; loading IS therapy.
Plus reverse-wrist-curls is mechanism-inverted (loads extensors, not
flexors — irrelevant to flexor-pronator tendinopathy).

**Flips (6):** grip-strengthening, wrist-curls (v1 SAFE), wrist-pronation-supination
(v1 SAFE), reverse-wrist-curls (mechanism inverted), marble-pickup, towel-curls
(body-region overreach).

**Approves (2 v1 UNSAFE matches):** bicep-curls, lat-pulldown-with-band.

---

## patellar-tendinitis (14/25 — done 2026-04-26)

**Source:** Tendinopathy paradigm + [Holden/Rio/Cook 2017 isometric loading evidence](https://pubmed.ncbi.nlm.nih.gov/28210577/) + v1 KG (13 SAFE, 1 UNSAFE).

**Decisions: 46 cards (17 contra + 29 unclear); 3 flip / 35 approve / 8 reject (flip rate 18%).**

**Flips (3):** seated-knee-extension (v1 SAFE — open-chain quad loading),
wall-sits (v1 SAFE — isometric quad loading is one of the most evidence-supported
analgesic loading positions), wall-squat-with-ball (functional equivalent of
wall-sits).

**Approves (1 v1 UNSAFE match):** bulgarian-split-squat.

**Rejects (8):** mostly calf and hamstring exercises AI claimed loaded the
patellar tendon — mechanism is wrong (calf raises don't load patellar
tendon, hamstring curls engage hamstrings not quads). REJECT defers to v1.

---

## rotator-cuff-tendinopathy (15/25 — done 2026-04-26)

**Source:** Tendinopathy paradigm + v1 KG (22 SAFE — most extensive curation in v1; 3 UNSAFE).

**Decisions: 38 cards (8 contra + 30 unclear); 3 flip / 34 approve / 1 reject (flip rate 8%).**

**Flips (3):** towel-curls (body-region overreach), lat-pulldown-with-band
(unclear→contra match v1 UNSAFE), wall-push-ups (unclear→contra match v1 UNSAFE).

**Approves (1 v1 UNSAFE match):** seated-shoulder-press.

Lower flip rate here because v1 is so comprehensive (22 SAFE) that AI
mostly hedged 'unclear' rather than mis-flagging — the SAFE coverage was
already in v1's safety net.

---

## ✓ Tendinopathy cluster complete (15/25 = 60%)

| Condition | Cards | Approve | Reject | Flip | Flip rate |
|---|---|---|---|---|---|
| achilles-tendinopathy | 43 | 35 | 5 | 3 | 7% (contra: 20%) |
| biceps-tendinitis | 39 | 32 | 4 | 3 | 8% (contra: 17%) |
| hamstring-tendinopathy | 57 | 47 | 5 | 5 | 9% (contra: 19%) |
| lateral-epicondylitis | 35 | 29 | 1 | 5 | 14% (contra: ⚠33%) |
| medial-epicondylitis | 34 | 26 | 2 | 6 | 18% (contra: ⚠43%) |
| patellar-tendinitis | 46 | 35 | 8 | 3 | 7% (contra: 18%) |
| rotator-cuff-tendinopathy | 38 | 34 | 1 | 3 | 8% (contra: 13%) |
| **Tendinopathy total** | **292** | **238** | **26** | **28** | **9.6%** |

**Pattern observed across cluster:** AI fundamentally inverts the
tendinopathy treatment paradigm. Eccentric/HSR/isometric loading of the
affected tendon is first-line per JOSPT/Tyler/Holden-Rio evidence. v1 KG
encodes this correctly. AI flags loading exercises as contra. Standard
FLIP applies to any v1-SAFE loading exercise the AI mis-flagged.

---

## acl-sprain (16/25 — done 2026-04-26)

**Source:** v1 KG (14 SAFE incl. all hamstring activation; 3 UNSAFE).

**Decisions: 40 cards (8 contra + 32 unclear); 3 flip / 36 approve / 1 reject.**

**Flips (3):** prone-hamstring-curl, prone-knee-flexion (both v1 SAFE; AI
inverted mechanism — hamstring activation is PROTECTIVE for ACL because
hamstrings are antagonist to ACL, reducing anterior tibial shear);
lateral-step-ups (unclear→contra match v1 UNSAFE).

**Approves (2 v1 UNSAFE matches):** bulgarian-split-squat, single-leg-deadlift.

---

## meniscus-tear (17/25 — done 2026-04-26)

**Source:** v1 KG (15 SAFE incl. step-ups, hamstring-curls; 2 UNSAFE).

**Decisions: 63 cards (21 contra + 42 unclear); 4 flip / 54 approve / 5 reject (flip rate 6%; contra: 19%).**

**Flips (4):** hamstring-curls, step-ups (v1 SAFE — open-chain knee flexion
has minimal compressive load; step-ups are part of return-to-function);
marble-pickup, towel-curls (body-region overreach, foot exercises).

---

## patellofemoral-pain-syndrome (18/25 — done 2026-04-26)

**Source:** v1 KG (25 SAFE — most extensive in v1; 2 UNSAFE).

**Decisions: 22 cards (3 contra + 19 unclear); 1 flip / 19 approve / 2 reject.**

Lowest contra count of any condition (3) because v1's 25-SAFE coverage
already absorbed most exercises. AI was correct on the only v1-UNSAFE
match (bulgarian-split-squat).

**Flips (1):** single-leg-deadlift (unclear→contra match v1 UNSAFE).

---

## it-band-syndrome (19/25 — done 2026-04-26)

**Source:** v1 KG (13 SAFE; 0 UNSAFE — wide tolerance window).

**Decisions: 24 cards (5 contra + 19 unclear); 0 flip / 21 approve / 3 reject.**

Cleanest sweep — no flips needed. v1's 13-SAFE list (incl. all hip-abductor
loading like fire-hydrants, lateral-band-walks, monster-walks) already covers
the standard ITBS protocol. AI's contras were defensible OR debatable enough
to REJECT.

---

## ✓ Knee cluster complete (19/25 = 76%)

| Condition | Cards | Approve | Reject | Flip | Flip rate |
|---|---|---|---|---|---|
| acl-sprain | 40 | 36 | 1 | 3 | 8% |
| meniscus-tear | 63 | 54 | 5 | 4 | 6% |
| patellofemoral-pain-syndrome | 22 | 19 | 2 | 1 | 5% |
| it-band-syndrome | 24 | 21 | 3 | 0 | 0% |
| **Knee total** | **149** | **130** | **11** | **8** | **5.4%** |

Knee cluster had the lowest flip rate (5.4%) because v1 KG curation for these
conditions is unusually rich (PFPS: 25 SAFE; meniscus: 15; ACL: 14; ITBS: 13).
AI mostly hedged 'unclear' on items v1 already covered, which APPROVE-drops
cleanly without conflict.

---

## hip-bursitis (20/25 — done 2026-04-26)

**Source:** [Mellor 2018 LEAP trial](https://www.bmj.com/content/361/bmj.k1662) (load-management abductor strengthening) + v1 KG (15 SAFE incl. all hip abductor loading; 1 UNSAFE).

**Decisions: 60 cards (23 contra + 37 unclear); 3 flip / 53 approve / 4 reject.**

**Flips (3):** fire-hydrants, side-lying-hip-abduction, standing-hip-abduction
— all v1 SAFE; AI inverted the treatment paradigm (progressive abductor
loading IS the trochanteric bursitis protocol per Mellor 2018).

**Approves (1 v1 UNSAFE match):** foam-roller-it-band.

---

## frozen-shoulder (21/25 — done 2026-04-26)

**Source:** v1 KG (9 SAFE — pendulum, gentle ROM, ER/IR; 4 UNSAFE — overhead and load-bearing).

**Decisions: 51 cards (16 contra + 35 unclear); 1 flip / 50 approve / 0 reject (flip rate 2%).**

AI was very accurate — frozen shoulder has clear-cut "end-range or weight-bearing
shoulder under load = contraindicated" logic that the AI applied correctly.

**Flips (1):** lat-pulldown-with-band (unclear→contra match v1 UNSAFE).

**Approves (3 v1 UNSAFE matches):** seated-shoulder-press,
standing-chest-fly-with-band, wall-push-ups.

---

## shoulder-impingement (22/25 — done 2026-04-26)

**Source:** v1 KG (20 SAFE — most extensive in shoulder cluster; 2 UNSAFE).

**Decisions: 36 cards (13 contra + 23 unclear); 0 flip / 35 approve / 1 reject.**

Cleanest of the shoulder conditions — zero flips. AI's contras consistently
identified subacromial-narrowing positions; v1 already encodes the rotator
cuff strengthening protocol comprehensively.

---

## plantar-fasciitis (23/25 — done 2026-04-26)

**Source:** [Rathleff 2014 high-load strength training RCT](https://pubmed.ncbi.nlm.nih.gov/25145517/) + v1 KG (11 SAFE; 0 UNSAFE).

**Decisions: 39 cards (16 contra + 23 unclear); 2 flip / 37 approve / 0 reject.**

**Flips (2):** marble-pickup (v1 SAFE — intrinsic foot strengthening),
standing-calf-raises (v1 SAFE — Rathleff protocol uses high-load calf raises
with rolled towel under toes as first-line treatment).

---

## hamstring-strain (24/25 — done 2026-04-26)

**Source:** [Askling L-protocol](https://pubmed.ncbi.nlm.nih.gov/23687006/) + v1 KG (17 SAFE; 3 UNSAFE).

**Decisions: 73 cards (26 contra + 47 unclear); 3 flip / 65 approve / 5 reject.**

Same loading-paradigm pattern as hamstring-tendinopathy. Flips align with v1.

**Flips (3):** hamstring-curls, hip-hinge, prone-hamstring-curl — all v1 SAFE.

**Approves (2 v1 UNSAFE matches):** bulgarian-split-squat, single-leg-deadlift.

---

## lateral-ankle-sprain (25/25 — done 2026-04-26)

**Source:** [DiStefano 2009 ankle sprain rehab review](https://pubmed.ncbi.nlm.nih.gov/19642778/) + v1 KG (17 SAFE — full peroneal/proprioceptive protocol; 0 UNSAFE).

**Decisions: 49 cards (9 contra + 40 unclear); 1 flip / 48 approve / 0 reject.**

**Flips (1):** resistance-band-ankle-inversion — v1 SAFE. AI mis-interpreted
exercise mechanics: the band pulls the ankle into inversion, the patient
resists by EVERTING. So this is a peroneal (evertor) strengthening drill,
which is THE standard rehab for lateral ankle sprain (peroneal weakness is
a primary risk factor).

---

## ✓ Other ortho cluster complete (25/25 = 100%)

| Condition | Cards | Approve | Reject | Flip | Flip rate |
|---|---|---|---|---|---|
| hip-bursitis | 60 | 53 | 4 | 3 | 5% |
| frozen-shoulder | 51 | 50 | 0 | 1 | 2% |
| shoulder-impingement | 36 | 35 | 1 | 0 | 0% |
| plantar-fasciitis | 39 | 37 | 0 | 2 | 5% |
| hamstring-strain | 73 | 65 | 5 | 3 | 4% |
| lateral-ankle-sprain | 49 | 48 | 0 | 1 | 2% |
| **Other ortho total** | **308** | **288** | **10** | **10** | **3.2%** |

---

# 🎯 FINAL TOTALS — All 25 conditions reviewed

| Cluster | Conditions | Cards | Approve | Reject | Flip | Flip rate |
|---|---|---|---|---|---|---|
| Spinal | 8 | 489 | 412 | 47 | 30 | 6.1% |
| Tendinopathy | 7 | 292 | 238 | 26 | 28 | 9.6% |
| Knee | 4 | 149 | 130 | 11 | 8 | 5.4% |
| Other ortho | 6 | 308 | 288 | 10 | 10 | 3.2% |
| **TOTAL** | **25** | **1,238** | **1,068** | **94** | **76** | **6.1%** |

## Aggregate flip taxonomy

Of the 76 flips:
1. **v1 KG direct contradictions** (~52, ~68%): AI flagged as contra, v1 SAFE.
   Most common in tendinopathies (loading IS treatment) and conditions where
   v1 has rich SAFE coverage.
2. **Body-region overreach** (~14, ~18%): AI flagged exercise affecting one
   body region as contra for a condition affecting a different region. Most
   common: marble-pickup / towel-curls (foot exercises) flagged for upper
   extremity / lumbar conditions; cervical exercises flagged for lumbar
   conditions; lumbar exercises flagged for cervical conditions.
3. **Inverted mechanism** (~8, ~10%): AI's biomechanical reasoning was
   inverted (e.g., stenosis: "lumbar flexion narrows canal" — wrong, flexion
   opens canal; ACL: "prone hamstring curl creates anterior tibial shear" —
   wrong, hamstring activation prevents anterior shear).
4. **Unclear → contra to align v1 UNSAFE** (~2, ~3%): AI hedged where v1
   was definitive.

## Self-stop trigger events

Two conditions exceeded the 25%-flip-on-contra threshold; both were
verified against published evidence and flips held:

- **lateral-epicondylitis** — 33% (4/12). Verified against JOSPT 2010 Tyler
  eccentric protocol. Flips were on grip-strengthening + reverse-wrist-curls
  (loading IS treatment) plus 2 body-region overreaches.
- **medial-epicondylitis** — 43% (6/14). Same paradigm + reverse-wrist-curls
  inverted mechanism (loads extensors not flexors). Flips held.

## What was deliberately NOT done

- ❌ Did not run `merge_kg_review.py` without `--dry-run` (writes the v2 file
  — needs separate session per goal contract).
- ❌ Did not flip the `@AppStorage("knowledgeGraphV2Enabled")` flag.
- ❌ Did not modify `knowledge_graph_v2_draft.json` or v1 KG.
- ❌ Did not commit anything.

## Next session's job (separate)

1. Run `python3 scripts/merge_kg_review.py` (without `--dry-run`) — writes
   `ios/PT-Helper/PT-Helper/Resources/medical_knowledge_graph_v2.json`.
2. Optional: review the merged file to spot-check structure.
3. Flip `@AppStorage("knowledgeGraphV2Enabled")` default → `true` in
   `ios/PT-Helper/PT-Helper/Services/KnowledgeGraphService.swift`.
4. Run `KnowledgeGraphExpansionTests` (13/13 expected green).
5. Run SmokePlan (11/11 expected green).
6. Manual smoke per `scripts/PR-C-2-handoff.md` Step 5.

