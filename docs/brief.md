# Product Brief (PT Helper)

Goal: Help athletes self-assess pain via a 3D body map, answer PT-style questions, and receive AI-powered condition analysis with personalized rehab plans and guided workouts.

Users: Athletes and fitness enthusiasts (self-directed rehabilitation).

## Core Flows
1. **3D Body Map** — Tap body regions to select pain areas (RealityKit, coach marks for first-time users)
2. **Pain Assessment** — Per-region form with collapsible optional sections, "Apply to All" for multi-region
3. **AI Analysis** — Two-call verification pipeline → top 3 conditions with confidence bands, red flag alerts
4. **Rehab Plan** — AI-generated plan with user preferences (equipment, session length, difficulty), exercise verification via knowledge graph + cross-model check
5. **Guided Workout** — Step-by-step execution with rest timers, exercise swaps, and crash-resilient checkpointing
6. **Progress Tracking** — Pain trend charts, workout streaks, AI-powered weekly recovery insights

## Safety
- Non-diagnosis disclaimer shown on first use
- Red flags trigger prominent urgent care alerts
- Confidence capped at 85% with user-facing explanation
- Exercise verification (knowledge graph + cross-model) flags contraindicated exercises
- Medication interaction checks via validation pipeline

## Technical Stack
- iOS: SwiftUI + RealityKit + Firebase (Auth, Firestore, Crashlytics)
- Backend: Firebase Cloud Functions (TypeScript) → Claude API proxy
- Images: ~190 AI-generated exercise illustrations (FLUX 2 Pro)
