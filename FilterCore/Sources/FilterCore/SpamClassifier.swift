import Foundation

/// The four kinds the training messages are labelled with (see the README).
public enum MessageKind: String, Codable, CaseIterable, Sendable {
    /// From a person, or a warning the user should see (police, bank security). Stays in the inbox.
    case personal
    /// A notice: codes, deliveries, card activity, bills, appointments. Goes to Transactions.
    case transaction
    /// An ad or campaign. Goes to Promotions.
    case promotion
    /// Spam. Also goes to Promotions, never to Junk (see `SpamClassifier`).
    case junk
}

/// Learns from labelled messages which words, link domains and shapes point to each `MessageKind`
/// (a naive Bayes classifier). It only keeps counts: how many messages of each kind it saw and in how many of
/// them each token appeared, so the messages themselves aren't stored, only their words.
///
/// The engine asks it only when no rule matched. A wrong guess must not hide a message the user needs, so it
/// moves a message only when the message is clearly not personal (`hidingMargin`), sends spam to Promotions,
/// never to Junk, and sends nothing to Promotions that could be a notice (`promotionMargin`).
public struct SpamClassifier: Codable, Equatable, Sendable {
    /// Number of messages of each kind.
    public private(set) var messages: [MessageKind: Int] = [:]
    /// Number of messages of each kind each token appeared in.
    private(set) var tokens: [MessageKind: [String: Int]] = [:]

    // Derived from the counts above, kept so scoring a message doesn't walk the whole vocabulary.
    private var totals: [MessageKind: Int] = [:]
    private var vocabularySize = 0

    /// Log-odds by which another kind must beat `personal` before a message leaves the inbox.
    /// Chosen on the validation messages (`swift run TrainClassifier` prints the choices): one step above the
    /// lowest value that moved none of their personal messages, because moving one costs more than missing spam.
    public static let hidingMargin = 8.0
    /// Log-odds by which promotion or junk must beat `transaction` before a message goes to Promotions.
    /// One step above the lowest value, for the same reason.
    public static let promotionMargin = 2.0

    public init() {}

    /// The model trained on the messages listed in the README, shipped with the app.
    /// Empty (never moves a message) if the resource is missing or unreadable.
    public static let bundled: SpamClassifier = {
        guard let url = Bundle.module.url(forResource: "classifier", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let classifier = try? JSONDecoder().decode(SpamClassifier.self, from: data)
        else { return SpamClassifier() }
        return classifier
    }()

    /// Counts the message as `kind`. `weight` counts it as that many messages, so the few examples a user
    /// teaches on the phone are not drowned out by the thousands in the bundled model.
    public mutating func learn(_ text: String, as kind: MessageKind, weight: Int = 1) {
        messages[kind, default: 0] += weight
        for token in Self.tokens(in: text) { tokens[kind, default: [:]][token, default: 0] += weight }
        recomputeTotals()
    }

    /// Both models' counts together, e.g. the bundled model plus what the user taught on this phone.
    public func adding(_ other: SpamClassifier) -> SpamClassifier {
        var result = self
        result.messages.merge(other.messages, uniquingKeysWith: +)
        result.tokens.merge(other.tokens) { $0.merging($1, uniquingKeysWith: +) }
        result.recomputeTotals()
        return result
    }

    /// Drops tokens seen in fewer than `minimumCount` messages overall. Used when building the bundled model:
    /// rare tokens carry little signal and could be names or codes from a single message.
    public func pruned(minimumCount: Int) -> SpamClassifier {
        var counts: [String: Int] = [:]
        for kindTokens in tokens.values { counts.merge(kindTokens, uniquingKeysWith: +) }
        var result = self
        result.tokens = tokens.mapValues { $0.filter { counts[$0.key, default: 0] >= minimumCount } }
        result.recomputeTotals()
        return result
    }

    /// Log-probability of the message for each kind the model has seen, up to a shared constant.
    /// Only differences between kinds mean something.
    public func scores(_ text: String) -> [MessageKind: Double] {
        scores(normalized: TextNormalizer.normalize(text))
    }

    func scores(normalized: String) -> [MessageKind: Double] {
        let kinds = MessageKind.allCases.filter { messages[$0, default: 0] > 0 && totals[$0, default: 0] > 0 }
        guard !kinds.isEmpty else { return [:] }
        let messageCount = Double(messages.values.reduce(0, +))
        // A token the model never saw says nothing about the message.
        let known = Self.tokens(inNormalized: normalized).filter { token in kinds.contains { tokens[$0]?[token] != nil } }

        // Smoothing in proportion to each kind's size. With the usual +1 for every kind, a word seen a few times
        // in a large kind and never in a far smaller one would still push towards the smaller one.
        let vocabulary = Double(vocabularySize)
        var result: [MessageKind: Double] = [:]
        for kind in kinds {
            let total = Double(totals[kind]!)
            let kindTokens = tokens[kind] ?? [:]
            var score = log(Double(messages[kind]!) / messageCount)
            for token in known {
                score += log((Double(kindTokens[token, default: 0]) + total / vocabulary) / (2 * total))
            }
            result[kind] = score
        }
        return result
    }

    /// Where the message should go: `.transaction`, `.promotion`, or nil to leave it in the inbox.
    public func verdict(_ text: String) -> FilterAction? {
        verdict(normalized: TextNormalizer.normalize(text))
    }

    func verdict(normalized: String) -> FilterAction? {
        Self.verdict(for: scores(normalized: normalized))
    }

    /// The decision behind `verdict(_:)`, with the margins as parameters so the trainer can try others.
    public static func verdict(
        for scores: [MessageKind: Double],
        hidingMargin: Double = SpamClassifier.hidingMargin,
        promotionMargin: Double = SpamClassifier.promotionMargin
    ) -> FilterAction? {
        // A model that never saw personal messages can't tell them apart, so it moves nothing.
        guard let personal = scores[.personal] else { return nil }
        let notice = scores[.transaction] ?? -.infinity
        let campaign = max(scores[.promotion] ?? -.infinity, scores[.junk] ?? -.infinity)

        if campaign > notice, campaign - personal > hidingMargin, campaign - notice > promotionMargin {
            return .promotion
        }
        return notice - personal > hidingMargin ? .transaction : nil
    }

    /// What the classifier looks at: words of two or more letters outside links, link domains ("d:ornek.com"),
    /// whether there is a link at all and whether there is a number. Each counts once per message.
    /// Words inside links ("https", "www", "com") are left out: in the training data they mostly come with
    /// campaigns, and would send notices with a link to Promotions.
    static func tokens(in text: String) -> Set<String> {
        tokens(inNormalized: TextNormalizer.normalize(text))
    }

    private static func tokens(inNormalized normalized: String) -> Set<String> {
        var tokens = Set<String>()
        let domains = RuleSuggester.linkDomains(inNormalized: normalized)
        let hasLink = normalized.contains("http://") || normalized.contains("https://") || normalized.contains("www.")

        var word = String.UnicodeScalarView()
        func endWord() {
            if word.count >= 2 { tokens.insert(String(word)) }
            word.removeAll()
        }
        var hasNumber = false
        for chunk in normalized.split(separator: " ") {
            if hasLink && (chunk.contains("://") || chunk.hasPrefix("www.")) || domains.contains(where: chunk.contains) {
                if chunk.contains(where: \.isNumber) { hasNumber = true }
                continue
            }
            for scalar in chunk.unicodeScalars {
                if ("a"..."z").contains(scalar) {
                    word.append(scalar)
                } else {
                    endWord()
                    if ("0"..."9").contains(scalar) { hasNumber = true }
                }
            }
            endWord()
        }

        for domain in domains { tokens.insert("d:" + domain) }
        if hasLink { tokens.insert("<link>") }
        if hasNumber { tokens.insert("<num>") }
        return tokens
    }

    private mutating func recomputeTotals() {
        tokens = tokens.filter { !$0.value.isEmpty }
        totals = tokens.mapValues { $0.values.reduce(0, +) }
        vocabularySize = Set(tokens.values.flatMap(\.keys)).count
    }

    // Only the counts are saved; the totals are worked out again when reading.

    private enum CodingKeys: String, CodingKey {
        case messages, tokens
        // Saved by app versions with two kinds; examples a user taught there are still read.
        case junkMessages, otherMessages, junkTokens, otherTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.messages) {
            messages = try Self.byKind(container.decode([String: Int].self, forKey: .messages))
            tokens = try Self.byKind(container.decode([String: [String: Int]].self, forKey: .tokens))
        } else {
            // "Not spam" taught in the old app meant a normal message: personal.
            messages = [.junk: try container.decode(Int.self, forKey: .junkMessages),
                        .personal: try container.decode(Int.self, forKey: .otherMessages)].filter { $0.value > 0 }
            tokens = [.junk: try container.decode([String: Int].self, forKey: .junkTokens),
                      .personal: try container.decode([String: Int].self, forKey: .otherTokens)]
        }
        recomputeTotals()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Keyed by name: a dictionary keyed by an enum would be saved as a list.
        try container.encode(Dictionary(uniqueKeysWithValues: messages.map { ($0.key.rawValue, $0.value) }), forKey: .messages)
        try container.encode(Dictionary(uniqueKeysWithValues: tokens.map { ($0.key.rawValue, $0.value) }), forKey: .tokens)
    }

    /// Unknown kinds (from a newer app version) are dropped instead of failing the whole file.
    private static func byKind<Value>(_ dictionary: [String: Value]) -> [MessageKind: Value] {
        Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in MessageKind(rawValue: key).map { ($0, value) } })
    }
}

/// Whether the classifier is on and what the user taught it on this phone. The app and the share extension
/// save it in the App Group (`RuleStore.saveClassifierSettings`), the filter extension reads it.
public struct ClassifierSettings: Codable, Equatable, Sendable {
    /// On by default: it only moves messages no rule matched, and only when it is clearly sure (see `verdict`).
    public var isEnabled = true
    public private(set) var learned = SpamClassifier()
    public private(set) var exampleCount = 0

    /// A taught message counts as this share of the bundled model's messages of the same kind (1/50 = 2%),
    /// so a single correction changes the verdict for that kind of message despite the thousands of
    /// messages in the model. A fixed weight would be too strong for small kinds or too weak for large ones.
    static let userExampleShare = 50

    public init() {}

    /// Missing fields get their defaults, so a file saved by an older app version still reads after a field is added.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        learned = try container.decodeIfPresent(SpamClassifier.self, forKey: .learned) ?? SpamClassifier()
        exampleCount = try container.decodeIfPresent(Int.self, forKey: .exampleCount) ?? 0
    }

    public mutating func learn(_ text: String, as kind: MessageKind) {
        let weight = max(1, SpamClassifier.bundled.messages[kind, default: 0] / Self.userExampleShare)
        learned.learn(text, as: kind, weight: weight)
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
