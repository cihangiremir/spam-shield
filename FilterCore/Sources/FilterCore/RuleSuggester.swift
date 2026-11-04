import Foundation

/// Turns a spam message the user reports into rules they can add: block its link domains,
/// its sender, or a phrase from it. Nothing is saved here; the app asks the user first.
public enum RuleSuggester {
    /// Link domains in the message, lowercase and without duplicates, e.g. ["kisalt.art"].
    /// Only the registrable part is kept ("a.b.ornek.com" → "ornek.com", "x.ornek.com.tr" → "ornek.com.tr")
    /// so the rule also catches the spammer's other subdomains.
    public static func linkDomains(in text: String) -> [String] {
        linkDomains(inNormalized: TextNormalizer.normalize(text))
    }

    /// `linkDomains(in:)` for text that already went through `TextNormalizer.normalize`.
    static func linkDomains(inNormalized normalized: String) -> [String] {
        let range = NSRange(normalized.startIndex..., in: normalized)

        var domains: [String] = []
        for match in hostRegex.matches(in: normalized, range: range) {
            guard let hostRange = Range(match.range(at: 3), in: normalized) else { continue }
            let host = String(normalized[hostRange])
            let hasScheme = match.range(at: 1).location != NSNotFound
            let hasWWW = match.range(at: 2).location != NSNotFound
            let hasPath = match.range(at: 4).location != NSNotFound
            let topLevel = String(host.split(separator: ".").last ?? "")

            // A bare "kredi.detay" is more likely a missing space than a link.
            guard hasScheme || hasWWW || hasPath || knownTopLevelDomains.contains(topLevel) else { continue }

            let domain = registrableDomain(of: host)
            if !domains.contains(domain) { domains.append(domain) }
        }
        return domains
    }

    /// Words of the message the user can tap to build a phrase. Links, numbers and very short words are left out.
    public static func words(in text: String) -> [String] {
        var seen = Set<String>()
        return text
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { word in
                word.count >= 3
                    && word.contains(where: \.isLetter)
                    && !word.contains("/") && !word.contains(".")
                    && seen.insert(TextNormalizer.normalize(word)).inserted
            }
    }

    /// True when the phrase appears in the message the same way the filter would see it.
    public static func message(_ text: String, contains phrase: String) -> Bool {
        let normalizedPhrase = TextNormalizer.normalize(phrase)
        return !normalizedPhrase.isEmpty && TextNormalizer.normalize(text).contains(normalizedPhrase)
    }

    /// Matches the domain and its subdomains only: a rule for "hepsiburada.co" must not catch
    /// "hepsiburada.com" or "hepsiburada.co.uk".
    public static func domainRule(_ domain: String) -> Rule {
        let pattern = #"(?<![a-z0-9-])"# + NSRegularExpression.escapedPattern(for: domain) + #"(?![a-z0-9-])(?!\.[a-z0-9])"#
        return Rule(name: String(localized: "Link: \(domain)", bundle: .module), matchType: .regex, pattern: pattern, action: .junk)
    }

    public static func senderRule(_ sender: String) -> Rule? {
        let trimmed = sender.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Rule(name: String(localized: "Sender: \(trimmed)", bundle: .module), target: .sender, matchType: .prefix, pattern: trimmed, action: .junk)
    }

    public static func phraseRule(_ phrase: String) -> Rule? {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !TextNormalizer.normalize(trimmed).isEmpty else { return nil }
        return Rule(name: String(localized: "Phrase: \(trimmed)", bundle: .module), matchType: .contains, pattern: trimmed, action: .junk)
    }

    // MARK: - Private

    /// 1: scheme, 2: "www.", 3: host, 4: path slash. The lookbehind skips e-mail addresses and word middles.
    /// Each label is atomic `(?>…)`: without it, text like "a.1a.1a.1…" makes the regex engine backtrack
    /// exponentially, and a 100-character message froze the app for minutes.
    private static let hostRegex = try! NSRegularExpression(
        pattern: #"(?<![a-z0-9@.-])(https?://)?(www\.)?((?:(?>[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)\.)+[a-z]{2,})(?![a-z0-9-])(/)?"#
    )

    private static let knownTopLevelDomains: Set<String> = [
        "com", "net", "org", "info", "biz", "tr", "io", "co", "me", "app", "dev", "art", "xyz", "site", "online",
        "store", "shop", "vip", "live", "icu", "top", "click", "link", "sbs", "cfd", "support", "help", "buzz",
        "club", "bond", "rest", "cyou", "monster", "lol", "quest", "website", "space", "fun", "pw", "tk", "ml",
        "ga", "cf", "gq", "ly", "gd", "cc", "gy", "tv", "ws", "ru", "cn", "de", "uk", "us",
    ]

    /// Second-level labels under .tr that are registered as a pair, like "com.tr".
    private static let turkishSecondLevels: Set<String> = [
        "com", "net", "org", "gov", "edu", "k12", "bel", "av", "gen", "web", "biz", "info", "tv", "name", "dr", "pol", "tsk",
    ]

    private static func registrableDomain(of host: String) -> String {
        let labels = host.split(separator: ".")
        let keep = labels.count >= 3 && labels.last == "tr" && turkishSecondLevels.contains(String(labels[labels.count - 2])) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}
