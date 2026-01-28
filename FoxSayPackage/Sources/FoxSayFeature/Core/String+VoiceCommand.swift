import Foundation

extension String {
    /// Normalize text for voice command detection
    /// - Lowercases the string
    /// - Collapses multiple spaces into single space
    /// - Strips trailing punctuation (. ! ? , ; :)
    /// - Trims whitespace
    var normalizedForVoiceCommand: String {
        var normalized = self.lowercased()

        // Collapse multiple spaces into single space
        while normalized.contains("  ") {
            normalized = normalized.replacingOccurrences(of: "  ", with: " ")
        }

        normalized = normalized.trimmingCharacters(in: .whitespaces)

        // Remove trailing punctuation that speech recognition often adds
        let trailingPunctuation = CharacterSet(charactersIn: ".!?,;:")
        while let last = normalized.last,
              let scalar = last.unicodeScalars.first,
              trailingPunctuation.contains(scalar) {
            normalized = String(normalized.dropLast())
        }

        return normalized.trimmingCharacters(in: .whitespaces)
    }
}
