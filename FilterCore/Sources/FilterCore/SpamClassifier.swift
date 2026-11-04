import Foundation

/// Learns from labelled messages which words, link domains and shapes point to spam (a naive Bayes classifier).
/// It only keeps counts: how many junk / other messages it saw and in how many of them each token appeared,
/// so no message text is stored.
///
/// The engine asks it only when no rule matched, and a spam verdict sends the message to Promotions, never to
/// Junk: a wrong guess must not hide a legitimate message.
public struct SpamClassifier: Codable, Equatable, Sendable {
    public private(set) var junkMessages = 0
    public private(set) var otherMessages = 0
    /// Number of junk / other messages each token appeared in.
    private(set) var junkTokens: [String: Int] = [:]
    private(set) var otherTokens: [String: Int] = [:]

    // Derived from the counts above, kept so scoring a message doesn't walk the whole vocabulary.
    private var junkTotal = 0
    private var otherTotal = 0
    private var vocabularySize = 0

    /// Log-odds a message must exceed to count as spam. Junk examples are much rarer than other messages
    /// in the training data, so a message needs several spam-only words to get there.
    public static let threshold = 3.0

    public init() {}

    /// The model trained on the messages listed in the README, shipped with the app.
    /// Empty (never says spam) if the resource is missing or unreadable.
    public static let bundled: SpamClassifier = {
        guard let url = Bundle.module.url(forResource: "classifier", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let classifier = try? JSONDecoder().decode(SpamClassifier.self, from: data)
        else { return SpamClassifier() }
        return classifier
    }()

    /// Counts the message as junk or not. `weight` counts it as that many messages, so the few examples a user
    /// teaches on the phone are not drowned out by the thousands in the bundled model.
    public mutating func learn(_ text: String, isJunk: Bool, weight: Int = 1) {
        let tokens = Self.tokens(in: text)
        if isJunk {
            junkMessages += weight
            for token in tokens { junkTokens[token, default: 0] += weight }
        } else {
            otherMessages += weight
            for token in tokens { otherTokens[token, default: 0] += weight }
        }
        recomputeTotals()
    }

    /// Both models' counts together, e.g. the bundled model plus what the user taught on this phone.
    public func adding(_ other: SpamClassifier) -> SpamClassifier {
        var result = self
        result.junkMessages += other.junkMessages
        result.otherMessages += other.otherMessages
        result.junkTokens.merge(other.junkTokens, uniquingKeysWith: +)
        result.otherTokens.merge(other.otherTokens, uniquingKeysWith: +)
        result.recomputeTotals()
        return result
    }

    /// Drops tokens seen in fewer than `minimumCount` messages overall. Used when building the bundled model:
    /// rare tokens carry little signal and could be names or codes from a single message.
    public func pruned(minimumCount: Int) -> SpamClassifier {
        var result = self
        let kept = Set(junkTokens.keys).union(otherTokens.keys).filter {
            junkTokens[$0, default: 0] + otherTokens[$0, default: 0] >= minimumCount
        }
        result.junkTokens = junkTokens.filter { kept.contains($0.key) }
        result.otherTokens = otherTokens.filter { kept.contains($0.key) }
        result.recomputeTotals()
        return result
    }

    /// Log-odds that the message is junk. Above `threshold` counts as spam.
    public func score(_ text: String) -> Double {
        guard junkMessages > 0, otherMessages > 0, junkTotal > 0, otherTotal > 0 else { return -.infinity }

        // Smoothing in proportion to each class's size. With the usual +1 for both, a word seen a few times in
        // normal messages and never in the far smaller junk set would still push towards junk.
        let vocabulary = Double(vocabularySize)
        func probability(_ count: Int, total: Int) -> Double {
            (Double(count) + Double(total) / vocabulary) / Double(2 * total)
        }

        var logOdds = log(Double(junkMessages) / Double(otherMessages))
        for token in Self.tokens(in: text) {
            let junkCount = junkTokens[token, default: 0]
            let otherCount = otherTokens[token, default: 0]
            // A token the model never saw says nothing about the message.
            guard junkCount + otherCount > 0 else { continue }
            logOdds += log(probability(junkCount, total: junkTotal)) - log(probability(otherCount, total: otherTotal))
        }
        return logOdds
    }

    public func isJunk(_ text: String) -> Bool {
        score(text) > Self.threshold
    }

    /// What the classifier looks at: words of two or more letters, link domains ("d:ornek.com"),
    /// whether there is a link at all and whether there is a number. Each counts once per message.
    static func tokens(in text: String) -> Set<String> {
        let normalized = TextNormalizer.normalize(text)
        var tokens = Set<String>()

        var word = String.UnicodeScalarView()
        func endWord() {
            if word.count >= 2 { tokens.insert(String(word)) }
            word.removeAll()
        }
        var hasNumber = false
        for scalar in normalized.unicodeScalars {
            if ("a"..."z").contains(scalar) {
                word.append(scalar)
            } else {
                endWord()
                if ("0"..."9").contains(scalar) { hasNumber = true }
            }
        }
        endWord()

        for domain in RuleSuggester.linkDomains(inNormalized: normalized) {
            tokens.insert("d:" + domain)
        }
        if normalized.contains("http://") || normalized.contains("https://") || normalized.contains("www.") {
            tokens.insert("<link>")
        }
        if hasNumber { tokens.insert("<num>") }
        return tokens
    }

    private mutating func recomputeTotals() {
        junkTotal = junkTokens.values.reduce(0, +)
        otherTotal = otherTokens.values.reduce(0, +)
        vocabularySize = Set(junkTokens.keys).union(otherTokens.keys).count
    }

    // Only the counts are saved; the totals are worked out again when reading.

    private enum CodingKeys: String, CodingKey {
        case junkMessages, otherMessages, junkTokens, otherTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        junkMessages = try container.decode(Int.self, forKey: .junkMessages)
        otherMessages = try container.decode(Int.self, forKey: .otherMessages)
        junkTokens = try container.decode([String: Int].self, forKey: .junkTokens)
        otherTokens = try container.decode([String: Int].self, forKey: .otherTokens)
        recomputeTotals()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(junkMessages, forKey: .junkMessages)
        try container.encode(otherMessages, forKey: .otherMessages)
        try container.encode(junkTokens, forKey: .junkTokens)
        try container.encode(otherTokens, forKey: .otherTokens)
    }
}

/// Whether the classifier is on and what the user taught it on this phone. The app and the share extension
/// save it in the App Group (`RuleStore.saveClassifierSettings`), the filter extension reads it.
public struct ClassifierSettings: Codable, Equatable, Sendable {
    /// Off until the user turns it on: rules are predictable, guesses are not.
    public var isEnabled = false
    public private(set) var learned = SpamClassifier()
    public private(set) var exampleCount = 0

    /// A taught message counts as this share of the bundled model's messages of the same kind (1/50 = 2%),
    /// so a single correction changes the verdict for that kind of message despite the thousands of
    /// messages in the model. A fixed weight would be too strong for junk or too weak for normal messages,
    /// which are 20 times more.
    static let userExampleShare = 50

    public init() {}

    public mutating func learn(_ text: String, isJunk: Bool) {
        let bundled = SpamClassifier.bundled
        let weight = max(1, (isJunk ? bundled.junkMessages : bundled.otherMessages) / Self.userExampleShare)
        learned.learn(text, isJunk: isJunk, weight: weight)
        exampleCount += 1
    }

    public mutating func forgetExamples() {
        learned = SpamClassifier()
        exampleCount = 0
    }

    /// The bundled model plus what the user taught. Built even when off, so the app can show its verdict.
    public var classifier: SpamClassifier {
        exampleCount == 0 ? .bundled : .bundled.adding(learned)
    }
}
