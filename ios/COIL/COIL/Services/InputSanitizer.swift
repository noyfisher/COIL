import Foundation

/// Best-effort scrubbing of user-provided text before it is sent to the AI API.
/// This is DEFENSE IN DEPTH, not a guarantee: blacklist-based pattern stripping
/// is inherently bypassable, so safety must not depend on it — user content is
/// also delimited (`delimit`), kept out of the system prompt server-side, and
/// constrained by output schemas. It reduces the easy injection surface and
/// enforces length limits.
///
/// Tier 2 expansions:
/// 1. Unicode NFKC normalization — collapses compatibility characters (ligatures,
///    full-width forms, etc.). NOTE: NFKC does NOT map cross-script homoglyphs —
///    e.g. Cyrillic "а" (U+0430) has no compatibility mapping to Latin "a", so a
///    homoglyph-based bypass survives normalization. This step is not a homoglyph
///    defense; the delimiting + server-side prompt separation are the real controls.
/// 2. HTML/XML tag strip — prevents users from injecting their own
///    `<user_notes>` delimiters around instructions.
/// 3. JSON role markers — blocks `"role":"system"` / `"role":"assistant"`
///    payloads that some models interpret as chat boundaries.
/// 4. Code-comment tokens — strips `/* */`, `//`, `<!-- -->`, leading `#`
///    that could hide injected instructions in ignored syntax.
/// 5. Additional Claude/model markers — `<system>`, `<assistant>`, `<user>`.
enum InputSanitizer {

    /// Maximum length for a single user-provided text field
    private static let maxFieldLength = 500

    /// Sanitize a single text field (pain description, notes, etc.)
    static func sanitize(_ text: String) -> String {
        // 0. Unicode NFKC normalization — collapses compatibility characters
        //    (ligatures, full-width forms, etc.) to canonical forms before pattern
        //    matching. This does NOT map cross-script homoglyphs (Cyrillic "а" is
        //    not decomposed to Latin "a"), so a homoglyph "іgnore" still survives —
        //    the pattern list is a speed bump, not the primary control.
        var cleaned = text.precomposedStringWithCompatibilityMapping

        // 1. Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. Enforce length limit
        if cleaned.count > maxFieldLength {
            cleaned = String(cleaned.prefix(maxFieldLength))
        }

        // 3. Strip HTML/XML tags. Runs BEFORE the injection-pattern pass so the
        //    instruction-like content inside tags still matches the next stage.
        if let htmlRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            cleaned = htmlRegex.stringByReplacingMatches(
                in: cleaned,
                range: NSRange(cleaned.startIndex..., in: cleaned),
                withTemplate: " "
            )
        }

        // 4. Strip common prompt injection patterns (case-insensitive)
        let injectionPatterns = [
            // Classic instruction-override attempts
            "ignore previous instructions",
            "ignore all instructions",
            "disregard previous",
            "disregard all",
            "forget your instructions",
            "override your instructions",
            "you are now",
            "new instructions:",
            // Chat-role impersonation (plain + JSON form)
            "system:",
            "assistant:",
            "\"role\"\\s*:\\s*\"system\"",
            "\"role\"\\s*:\\s*\"assistant\"",
            "\"role\"\\s*:\\s*\"user\"",
            // Instruction-format markers
            "\\[INST\\]",
            "\\[/INST\\]",
            "<\\|im_start\\|>",
            "<\\|im_end\\|>",
            // Claude-specific chat markers (HTML strip above may have already
            // removed the angle-bracket versions, but defend in depth).
            "<system>",
            "</system>",
            "<assistant>",
            "</assistant>",
            "<user>",
            "</user>",
            // Code-comment tokens that can hide injected payloads
            "/\\*",
            "\\*/",
            "<!--",
            "-->",
            "(?m)^\\s*//",
            "(?m)^\\s*#\\s",
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
