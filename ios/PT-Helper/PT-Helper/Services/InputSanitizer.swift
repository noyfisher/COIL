import Foundation

/// Sanitizes user-provided text before it is sent to the AI API.
/// Prevents prompt injection by stripping instruction-like patterns
/// and enforcing length limits.
enum InputSanitizer {

    /// Maximum length for a single user-provided text field
    private static let maxFieldLength = 500

    /// Sanitize a single text field (pain description, notes, etc.)
    static func sanitize(_ text: String) -> String {
        var cleaned = text

        // 1. Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Enforce length limit
        if cleaned.count > maxFieldLength {
            cleaned = String(cleaned.prefix(maxFieldLength))
        }

        // 3. Strip common prompt injection patterns (case-insensitive)
        let injectionPatterns = [
            "ignore previous instructions",
            "ignore all instructions",
            "disregard previous",
            "disregard all",
            "forget your instructions",
            "override your instructions",
            "you are now",
            "new instructions:",
            "system:",
            "assistant:",
            "\\[INST\\]",
            "\\[/INST\\]",
            "<\\|im_start\\|>",
            "<\\|im_end\\|>",
        ]

        for pattern in injectionPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: "[removed]"
                )
            }
        }

        return cleaned
    }

    /// Sanitize an array of factor strings (aggravating/relieving factors)
    static func sanitize(_ texts: [String]) -> [String] {
        texts.map { sanitize($0) }
    }

    /// Wrap user-provided content in XML delimiters so the AI can distinguish
    /// user data from instructions.
    static func delimit(_ text: String, label: String) -> String {
        let sanitized = sanitize(text)
        return "<user_\(label)>\(sanitized)</user_\(label)>"
    }
}
