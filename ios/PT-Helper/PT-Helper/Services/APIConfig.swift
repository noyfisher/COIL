import Foundation

enum APIConfig {
    // Firebase Cloud Function proxy URL (API key + prompts are stored server-side)
    static let claudeProxyURL = "https://us-central1-pt-helper-dev.cloudfunctions.net/claudeProxy"

    // Managed Agent endpoint for recovery insights (server fetches data, multi-step analysis)
    static let agentInsightsURL = "https://us-central1-pt-helper-dev.cloudfunctions.net/agentInsights"

    // On-demand exercise image generation (FLUX 2 Pro + Gemini QA)
    static let generateImageURL = "https://us-central1-pt-helper-dev.cloudfunctions.net/generateExerciseImage"

    /// Tier 3 PR E: client-side mirror of the server's `MODEL_CONFIG.analysis.model`
    /// (see `functions/src/index.ts`). Used by `ValidationRegressionRunner`
    /// to decide whether committed golden responses are still valid for the
    /// current production model.
    ///
    /// **MUST be kept in sync** with the server when the model is rotated.
    /// If the server bumps to a new model and this string isn't updated, the
    /// regression suite would silently run against stale goldens. The runner
    /// guards against this by skipping (loud warning, NOT silent pass) when
    /// the case's pinned model differs from this constant.
    ///
    /// Cross-reference grep before any model change:
    ///   grep -rn "claude-haiku-4-5-20251001" functions/src/ ios/PT-Helper/
    static let currentModel = "claude-haiku-4-5-20251001"
}
