import Foundation

extension String {
    /// Returns the first `maxSentences` sentences and a flag indicating whether
    /// the preview is shorter than the full text. Falls back to fewer sentences
    /// when the joined preview exceeds `maxCharacters` so that very long sentences
    /// still produce a preview rather than another wall of text.
    /// Returns the trimmed input with `isTruncated == false` when the input has
    /// `maxSentences` or fewer sentences.
    func sentencePreview(maxSentences: Int = 3, maxCharacters: Int = 300) -> (preview: String, isTruncated: Bool) {
        let normalized = self
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalized.isEmpty else { return ("", false) }

        var sentences: [String] = []
        normalized.enumerateSubstrings(in: normalized.startIndex..<normalized.endIndex,
                                       options: .bySentences) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }

        if sentences.count <= maxSentences {
            return (normalized, false)
        }

        var take = maxSentences
        var preview = sentences.prefix(take).joined(separator: " ")
        while preview.count > maxCharacters && take > 1 {
            take -= 1
            preview = sentences.prefix(take).joined(separator: " ")
        }
        return (preview, true)
    }
}
