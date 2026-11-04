import Foundation

/// Brings text into a single form before matching so spammers' small tricks don't slip through:
/// Turkish-aware lowercasing, Turkish letters and Cyrillic look-alikes folded to ASCII (ı→i, ş→s, а→a, ...),
/// invisible characters removed, repeated whitespace collapsed and spaced-out words joined ("b.a.h.i.s" → "bahis").
public enum TextNormalizer {
    private static let turkishLocale = Locale(identifier: "tr_TR")

    private static let foldMap: [Character: Character] = [
        "ı": "i", "ş": "s", "ğ": "g", "ü": "u", "ö": "o", "ç": "c",
        "â": "a", "î": "i", "û": "u",
        // Cyrillic letters that look like Latin ones ("bаhis" with a Cyrillic "а").
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s", "һ": "h",
    ]

    /// Four or more single letters with dots, spaces, dashes, underscores or stars between them.
    /// Two or three letters are left alone so abbreviations like "a.s." and "t.c." stay as they are.
    private static let spacedOutWord = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])\p{L}(?:[ .\-_*]+\p{L}){3,}(?![\p{L}\p{N}])"#
    )

    /// Zero-width and formatting characters used to split words ("ba\u{200B}his").
    private static let invisibleScalars: Set<Unicode.Scalar> = [
        "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{FEFF}", "\u{00AD}",
    ]

    public static func normalize(_ text: String) -> String {
        // Precompose first so a decomposed "s + ◌̧" becomes "ş" and gets folded below.
        let lowered = text.precomposedStringWithCanonicalMapping.lowercased(with: turkishLocale)

        var result = ""
        result.reserveCapacity(lowered.count)
        var previousWasSpace = false

        for scalar in lowered.unicodeScalars where !invisibleScalars.contains(scalar) {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !previousWasSpace { result.append(" ") }
                previousWasSpace = true
                continue
            }
            previousWasSpace = false
            let character = Character(scalar)
            result.append(foldMap[character] ?? character)
        }

        return joinSpacedOutWords(result.trimmingCharacters(in: .whitespaces))
    }

    private static func joinSpacedOutWords(_ text: String) -> String {
        let matches = spacedOutWord.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: result[range].filter(\.isLetter))
        }
        return result
    }

    /// Folds only the Turkish letters in a regex pattern. Unlike `normalize`, it keeps everything
    /// else untouched, because lowercasing would turn escapes such as `\D` or `\S` into `\d` / `\s`.
    /// Case is handled by compiling the regex case-insensitive instead.
    public static func foldRegexPattern(_ pattern: String) -> String {
        let upperFoldMap: [Character: Character] = [
            "İ": "i", "Ş": "s", "Ğ": "g", "Ü": "u", "Ö": "o", "Ç": "c",
        ]
        return String(pattern.precomposedStringWithCanonicalMapping.map { upperFoldMap[$0] ?? foldMap[$0] ?? $0 })
    }

    /// Sender IDs come as "+90 850 123 45 67", "0555 111 22 33" or "TRENDYOL". Drop spaces and dashes so
    /// prefixes match, and write Turkish numbers as "+90..." so "0555..." and "+90555..." are the same sender.
    public static func normalizeSender(_ sender: String) -> String {
        let compact = normalize(sender).filter { $0 != " " && $0 != "-" && $0 != "(" && $0 != ")" }
        guard !compact.isEmpty, compact.allSatisfy(\.isNumber) else { return compact }

        if compact.hasPrefix("0"), !compact.hasPrefix("00") {
            return "+90" + compact.dropFirst()
        }
        if compact.count == 12, compact.hasPrefix("90") {
            return "+" + compact
        }
        return compact
    }
}
