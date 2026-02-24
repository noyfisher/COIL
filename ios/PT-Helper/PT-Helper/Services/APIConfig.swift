import Foundation

enum APIConfig {
    // Firebase Cloud Function proxy URL (API key is stored server-side)
    static let claudeProxyURL = "https://us-central1-pt-helper-dev.cloudfunctions.net/claudeProxy"

    // Model configuration (sent to proxy, which forwards to Anthropic)
    static let anthropicModel = "claude-haiku-4-5-20251001"
    static let maxTokens = 4096
}

