# PT Helper — Startup Plan & Operating Schedule

*Written 2026-06-04. Owner: Noy. Revisit every Sunday.*

## The honest diagnosis

The product is over-built and under-validated. The repo shows months of strong engineering
(safety pipelines, 3D body map, image pipeline, rebrand) while the only market signal you have
is: **TestFlight users try it once and don't come back.** That single fact outweighs everything
else. Until strangers come back for a second and third workout, this is a portfolio project,
not a company.

Your specific traps, named so you can catch yourself:

1. **Engineering as procrastination.** You're good at building, so building feels productive.
   Polish, rebrands, and new features are the comfort zone. None of them fix churn.
2. **Ambiguous co-founder situation.** Jalen is "a collaborator, not fully committed" and the
   original spec doc lives on his account. Unresolved equity/IP ambiguity has killed better
   companies than this one.
3. **No measurement.** "Casual chats" and unmeasured retention means every product decision so
   far has been a guess.

## North Star metric

**% of new TestFlight users who complete 3+ workout sessions within 14 days of their first assessment.**

Not downloads. Not assessments run. Repeat workouts. Pick a number to beat: if you can't get
this above ~20–25% after two months of focused iteration, the consumer wedge is wrong and you
pivot (likely to trainers/teams).

---

## Phase 0 — Truth-finding (Weeks 1–2)

Goal: replace guesses with facts. **No new features. No polish. Freeze the rebrand work after
you commit what's pending.**

- [ ] **10 churned-tester interviews.** Real, scheduled, 20-minute calls — not texts. Script:
  What were you hoping it would do? What happened after the analysis? Why didn't you start /
  finish the plan? What would have brought you back the next day? What do you currently do when
  something hurts?
- [ ] **Instrument the funnel.** Verify AnalyticsService actually answers: assessment → plan
  generated → first workout started → first workout completed → session 2 → session 3.
  Build one dashboard (even a script over Firestore) showing D1/D7/D14 retention per cohort.
- [ ] **Jalen conversation.** Decide: committed co-founder with vesting, or thanked collaborator
  with IP assigned to you. In writing. Deadline: end of week 2.
- [ ] **Write down your churn hypothesis** before the interviews, then compare. (Mine, for the
  record: time-to-first-workout is too long, plans feel generic, and nothing pulls users back
  on day 2 — a streak feature can't create a habit that never started.)

**Exit criteria:** You can state, with evidence, the top 2 reasons people don't come back.

## Phase 1 — Fix the retention loop (Weeks 3–8)

Goal: make strangers come back. Build *only* what interviews + funnel data justify.

- **Weekly cohort cycle:** recruit 5–10 fresh TestFlight users every week (Reddit r/running,
  r/bodyweightfitness, r/climbharder, campus gyms, club teams). Fresh users each week =
  uncontaminated read on whether this week's changes moved retention.
- **Ship one retention-driven change per week.** Likely candidates (validate first):
  shorter time-to-first-workout (do a 5-minute session the moment the plan is generated),
  day-2 re-engagement that references *their* specific pain, visible progress ("pain trend"
  needs ≥2 data points fast).
- **Talk to 3+ users every week.** Forever. This is not a phase, it's the job.
- **Legal floor (one afternoon + ~$300–800):** form an LLC, have a lawyer sanity-check your
  disclaimer/ToS for an AI health app, confirm App Store health guidelines compliance. You are
  not HIPAA-covered, but "AI injury analysis" claims need careful wording. Don't over-invest
  here; don't skip it either.

**Exit criteria (end of week 8):** a weekly cohort where ≥20–25% of new users hit 3 sessions
in 14 days. If after 6 weeks of honest iteration no cohort moves, that's a signal, not a
failure — go to the pivot gate.

## Phase 2 — Public launch + money test (Weeks 9–16)

Only if Phase 1 exit criteria are met.

- App Store launch (real listing, screenshots, ASO basics).
- **Price test immediately.** Subscription paywall after the first plan or first workout.
  You need to know if anyone pays — willingness-to-pay is validation no interview can give.
- **Content engine:** 3 short-form videos/week (TikTok/IG/YT Shorts). "Tap where it hurts"
  is a natively visual hook — the 3D body map demo is your ad. Budget $100–200/mo on boosting
  what organically works, nothing more.
- Keep the weekly cohort + interview cadence running.

**Decide the ambition question here, not before.** With retention + payment data, the
venture-vs-indie choice answers itself. Deciding now is astrology.

### Pivot gate (if Phase 1 fails)

Consumer retention for episodic pain is brutally hard — people churn when pain fades.
Fallback wedge: **athletic trainers / club teams** (your original UCSC idea). One trainer
managing 30 athletes solves distribution and retention simultaneously. Don't pursue both
wedges at once; sequence them.

---

## The weekly schedule (20 hrs)

| Block | Hours | What |
|---|---|---|
| Users | 8 | Interviews (3+/wk), recruiting cohort, support, reading session logs |
| Product | 8 | ONE retention-driven change, shipped and verified by Friday |
| Distribution | 3 | Reddit/community posts, content drafts, outreach DMs |
| Review | 1 | Sunday: cohort metrics vs. last week, write 3-line summary, plan next week |

### Daily defaults (non-negotiable, ~30 min even on busy school days)

1. Check yesterday's funnel numbers (2 min).
2. Send 5 outreach messages OR 1 community post (15 min).
3. Reply to every tester message same-day (10 min).

### Weekly Sunday review — answer in writing

1. North Star number this week vs. last week?
2. What did I learn from users this week (quote a real person)?
3. What's the ONE product change next week, and what number should it move?
4. Did I spend >10 hrs coding things no user asked for? (If yes: why?)

## What you are explicitly NOT doing for 16 weeks

Fundraising. Incubator applications. Android. Web version. New AI features. Rebrands.
More exercise images. Anything Jalen "might" do. If it doesn't move the North Star or
keep you legal, it waits.
