# Virtual User Dashboard Validation Report

**Date:** 2026-03-24
**Generated:** 2026-03-29T22:01:30.451278
**Personas:** 1
**Total Checks:** 11
**Passed:** 4 | **Failed:** 7
**Overall:** FAIL

---

## Screen Coverage (4/4 passed)

  ✅ screen.vuser-dropoff-bodymap-006.DashboardTab: expected=visited, actual=visited (persona: vuser-dropoff-bodymap-006)
  ✅ screen.vuser-dropoff-bodymap-006.Onboarding: expected=visited, actual=visited (persona: vuser-dropoff-bodymap-006)
  ✅ screen.vuser-dropoff-bodymap-006.DashProfile: expected=visited, actual=visited (persona: vuser-dropoff-bodymap-006)
  ✅ screen.vuser-dropoff-bodymap-006.BodyMap3D: expected=visited, actual=visited (persona: vuser-dropoff-bodymap-006)

## Funnel Accuracy (0/3 passed)

  ❌ funnel.sign_in_completed: expected=1, actual=2 (diff=1)
  ❌ funnel.onboarding_completed: expected=1, actual=0 (diff=-1)
  ❌ funnel.body_map_opened: expected=1, actual=0 (diff=-1)

## Sankey Flow Accuracy (0/2 passed)

  ❌ sankey.sign_in_completed -> onboarding_completed: expected=1, actual=0 (diff=-1)
  ❌ sankey.onboarding_completed -> body_map_opened: expected=1, actual=0 (diff=-1)

## Engagement Metrics (0/2 passed)

  ❌ engagement.dau: expected=1, actual=2
  ❌ engagement.tab_switched: expected=1, actual=0
