# Changelog

All notable changes to PT Helper are documented here.

## [Unreleased]

### Added
- **Smart Health History** — Enriched data model for surgeries (body area, recovery status, restrictions), injuries (year, doctor visits, PT history, recovery status), and medications
- **Health History Relevance Filter** — Kinetic chain-based classification of health history as directly relevant, possibly relevant, or background-only for AI prompts
- **Medication-Aware Safety** — Validation pipeline checks for blood thinners (fall risk), corticosteroids (tendon weakness), beta blockers (RPE guidance)
- **Post-Surgical Restriction Warnings** — Active surgical recovery flagged in rehab plan validation
- **Treatment History Per Assessment** — Track doctor visits, imaging, diagnosis, and active treatment per pain region
- **Expanded Medical Conditions** — Osteoporosis, Blood Clotting Disorder, Fibromyalgia, Previous Cancer, Hypermobility, Neuropathy
- **Medications Tracking** — Blood Thinners, Beta Blockers, Corticosteroids, Insulin/Diabetes Meds, Pain Medication, Muscle Relaxants
- **Relevance-Sorted AI Prompts** — Surgical and injury history now organized by relevance to assessed pain region
- **Production Documentation** — README, API docs, safety docs, data model, contributing guide, changelog, privacy policy

### Changed
- System prompts updated with patient history usage instructions (kinetic chain, medication context, doctor recommendations)
- Profile review step now displays all enriched health history fields

## [0.9.0] — 2025-03-08

### Added
- **Firebase Crashlytics** — Automatic dSYM upload for crash reporting
- **Apply to All Regions** — Button to copy pain details across multiple selected body regions
- **Session Logging** — Detailed event logging for analysis and workout sessions with Firestore upload

### Fixed
- Analysis and rehab plan navigation crashes resolved
- Firebase warning suppression in test suite

## [0.8.0] — 2025-02-28

### Added
- **3D Body Map Proxy Entities** — Invisible collision entities for occluded body regions (back, glutes)
- **Comprehensive Collision Tests** — BodyMapCollisionTests for proxy entity validation
- **Test Reorganization** — 22 focused test files with Xcode Test Plans

## [0.7.0] — 2025-02-20

### Added
- **AI Response Validation Pipeline** — 8-layer safety validation for analysis and rehab plan responses
- **Exercise Contraindication Checker** — Cross-references exercises against diagnosed conditions
- **Medical Red Flag Detector** — Symptom pattern matching for emergency conditions
- **Anatomical Relevance Checker** — Validates AI conditions match assessed body regions
- **Confidence Calibration** — Caps AI confidence at 85%, maps to human-friendly labels
- **Exercise Images** — 178 AI-generated exercise illustrations (FLUX 2 Pro)

## [0.6.0] — 2025-02-10

### Added
- **Tester Feedback Round** — Onboarding UX improvements, analysis flow refinements, workout logging enhancements
- **TestFlight Configuration** — Bundle ID update, provisioning for TestFlight distribution

## [0.5.0] — 2025-01-30

### Added
- **Firebase Cloud Functions Proxy** — Server-side API key management, rate limiting, system prompts
- **Exercise Image Logging** — Missing image detection and Firestore reporting
- **Pre-TestFlight Polish** — UI refinements and stability improvements

## [0.4.0] — 2025-01-20

### Added
- **Injury Analysis** — AI-powered pain assessment with condition identification
- **Rehab Plans** — Personalized exercise programs with weekly schedules
- **Guided Workouts** — Step-by-step workout sessions with timers and counters
- **Plan Management** — Save, edit, and track rehab plans
- **Onboarding Flow** — Multi-step health profile collection

## [0.3.0] — 2025-01-10

### Added
- **3D Body Map** — Interactive RealityKit body model with tap-to-select regions
- **Pain Detail Collection** — Multi-factor pain assessment (type, intensity, duration, triggers)
- **Progress Tracking** — Workout streaks, achievements, progress charts

## [0.2.0] — 2024-12-15

### Added
- Initial app structure with SwiftUI navigation
- Firebase Authentication (Apple Sign-In, Google Sign-In)
- Basic user profile management
- Notes system for tracking observations
