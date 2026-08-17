---
name: run-tests
description: Run iOS test plans. Use when the user wants to run tests, verify changes, or check for regressions.
argument-hint: [smoke|unit|full|prerelease|TestClass/testMethod]
---

# Run Tests

Run the PT Helper iOS test suite using the specified test plan.

## Test Plan Mapping

| Argument | Test Plan | What it covers | Timeout |
|----------|-----------|----------------|---------|
| `smoke` | SmokePlan | 11 key tests — quick local sanity check only | 60s |
| `unit` (default) | UnitPlan | All unit tests — this is what CI gates PRs on | 120s |
| `full` | FullPlan | All unit + collision + UI tests — runs nightly in CI | 300s |
| `prerelease` | PreReleasePlan | All unit + UI tests + code coverage — gates TestFlight | 600s |

`smoke` is an 11-test allow-list, not a meaningful gate. Use it for a fast local
pulse check; never treat a green `smoke` run as evidence a change is safe.

## Instructions

Parse `$ARGUMENTS` to determine what to run:

1. **No arguments** → run UnitPlan (the default for day-to-day development)
2. **Plan name** (`smoke`, `unit`, `full`, `prerelease`) → run the corresponding test plan
3. **Test path** (contains `/`, e.g. `COILTests/UserProfileTests` or `COILTests/UserProfileTests/testDefaultUserProfile`) → run that specific test class or method

## How to Run

**Prefer XcodeBuildMCP** — check session defaults with `session_show_defaults` first. If project/scheme/simulator are configured, use `test_sim` with the appropriate `extraArgs`:

- For a test plan: `extraArgs: ["-testPlan", "<PlanName>"]`
- For a specific test: `extraArgs: ["-only-testing:COILTests/<path>"]`

**Fallback to xcodebuild CLI** if XcodeBuildMCP is not configured:

```bash
xcodebuild test \
  -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testPlan <PlanName>
```

For a specific test class/method:
```bash
xcodebuild test \
  -project ios/PT-Helper/COIL.xcodeproj \
  -scheme COIL \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:COILTests/<TestClass>/<testMethod>
```

## After Tests Complete

- Report total tests run, passed, failed, and skipped
- If any tests failed, list the failing test names and their error messages
- For `prerelease` plan, note coverage percentage if available in the output
