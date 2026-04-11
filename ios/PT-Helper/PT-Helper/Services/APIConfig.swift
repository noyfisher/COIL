import Foundation

enum APIConfig {
    // Firebase Cloud Function proxy URL (API key + prompts are stored server-side)
    static let claudeProxyURL = "https://us-central1-pt-helper-dev.cloudfunctions.net/claudeProxy"

    // Managed Agent endpoint for recovery insights (server fetches data, multi-step analysis)
    static let agentInsightsURL = "https://us-central1-pt-helper-dev.cloudfunctions.net/agentInsights"
}
