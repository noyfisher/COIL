import Foundation
import FirebaseAuth
import FirebaseFirestore
import os

// MARK: - Tier 3 PR C: shadow-mode strict JSON parser

/// Replaces the duplicated "try strict decode, fall back to brace
/// extraction" pattern in 7 parsers across the codebase. Behavior:
///
/// In shadow mode (default — `strictJsonParsingV1Enabled` UserDefaults
/// key absent or false):
///   1. Try strict JSON decode.
///   2. If strict succeeds → return.
///   3. If strict fails → run the permissive fallback (`first { to last }`
///      brace extraction + retry decode).
///   4. If permissive succeeds → log to `strictParseWouldReject/{requestType}`
///      Firestore counter (so we know what enforcement would have
///      rejected) AND return the permissive result. Production behavior
///      unchanged from before this PR — the user sees the parsed result.
///   5. If permissive also fails → throw `ClaudeAPIError.decodingError`.
///
/// In enforcement mode (`strictJsonParsingV1Enabled` = true, flipped
/// after a 2-week shadow-mode review confirms the rejection rate is low):
///   1. Try strict JSON decode.
///   2. If strict succeeds → return.
///   3. If strict fails → throw immediately. NO permissive fallback.
///
/// Why shadow mode first: the existing fallback exists because Claude
/// occasionally wraps JSON in markdown fences or adds a leading
/// disclaimer. We don't know the real rejection rate without measurement;
/// flipping straight to enforcement could break swap, form analysis, or
/// recovery insights for users in production.
enum ShadowModeJSONParser {

    /// Feature flag controlling whether the helper throws on strict failure
    /// instead of silently falling back. Defaults to false (shadow mode).
    /// Read-only — flip via UserDefaults / debug menu / `@AppStorage`.
    static let enforcementFlagKey = "strictJsonParsingV1Enabled"

    static var isEnforcementEnabled: Bool {
        UserDefaults.standard.bool(forKey: enforcementFlagKey)
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper",
        category: "shadowJSON"
    )

    // MARK: - Parse

    /// Parse a Claude response into `T`. See type doc-comment for behavior.
    ///
    /// `requestType` is a free-form tag for the telemetry counter. Use the
    /// matching `AIRequestType` raw value where applicable, otherwise a
    /// short stable string (e.g. "recovery_insights_agent").
    ///
    /// `decoder` is overridable for tests; production callers can use
    /// `JSONDecoder()`.
    static func parse<T: Decodable>(
        _ text: String,
        as type: T.Type,
        requestType: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        guard let strictData = text.data(using: .utf8) else {
            throw ClaudeAPIError.decodingError(NSError(
                domain: "ShadowModeJSONParser",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Response text could not be UTF-8 encoded"]
            ))
        }

        // 1. Strict attempt
        do {
            return try decoder.decode(T.self, from: strictData)
        } catch let strictError {
            // 2. Enforcement mode: don't try fallback.
            if isEnforcementEnabled {
                logger.warning("Strict-mode rejected response (\(requestType)): \(strictError.localizedDescription)")
                throw ClaudeAPIError.decodingError(strictError)
            }

            // 3. Shadow mode: try permissive fallback.
            if let startIndex = text.firstIndex(of: "{"),
               let endIndex = text.lastIndex(of: "}"),
               startIndex <= endIndex {
                let extracted = String(text[startIndex...endIndex])
                if let fallbackData = extracted.data(using: .utf8),
                   let fallbackResult = try? decoder.decode(T.self, from: fallbackData) {
                    // Permissive saved us where strict failed → log breadcrumb +
                    // bump the would-reject counter.
                    let trimmedChars = text.count - extracted.count
                    logger.info("Shadow-mode fallback used (\(requestType)): trimmed \(trimmedChars) chars")
                    Task.detached {
                        await ShadowModeJSONParserTelemetry.recordWouldReject(requestType: requestType)
                    }
                    return fallbackResult
                }
            }

            // 4. Both failed — propagate the strict error since it was first.
            logger.error("Both strict + fallback decode failed (\(requestType)): \(strictError.localizedDescription)")
            throw ClaudeAPIError.decodingError(strictError)
        }
    }
}

// MARK: - Telemetry

/// Fire-and-forget Firestore counter for shadow-mode "would have rejected"
/// events. After 2 weeks of shadow mode, query
/// `strictParseWouldReject/{requestType}.count` to decide whether to flip
/// enforcement on. Auth-safe: skips if no authenticated user.
enum ShadowModeJSONParserTelemetry {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.pthelper",
        category: "shadowJSON"
    )

    static func recordWouldReject(requestType: String) async {
        guard Auth.auth().currentUser != nil else { return }
        let docId = sanitizeDocId(requestType)
        do {
            try await Firestore.firestore()
                .collection("strictParseWouldReject")
                .document(docId)
                .setData([
                    "count": FieldValue.increment(Int64(1)),
                    "lastAt": FieldValue.serverTimestamp(),
                ], merge: true)
        } catch {
            logger.error("Failed to bump strictParseWouldReject counter: \(error.localizedDescription)")
        }
    }

    private static func sanitizeDocId(_ raw: String) -> String {
        let slug = raw
            .lowercased()
            .unicodeScalars
            .map { scalar -> String in
                if ("a"..."z").contains(String(scalar)) || ("0"..."9").contains(String(scalar)) {
                    return String(scalar)
                }
                return "-"
            }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "_unknown" : String(slug.prefix(100))
    }
}
