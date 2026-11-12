import Foundation

public struct FilterDecision: Equatable, Sendable {
    public let action: FilterAction
    /// The rule that decided the action. Nil means no rule matched: the message is allowed,
    /// or sorted by the classifier when `isFromClassifier`.
    public let matchedRule: Rule?
    /// True when no rule matched and the classifier moved the message to Promotions or Transactions.
    public let isFromClassifier: Bool

    init(action: FilterAction, matchedRule: Rule?, isFromClassifier: Bool = false) {
        self.action = action
        self.matchedRule = matchedRule
        self.isFromClassifier = isFromClassifier
    }
}

/// Runs the rules against one message. Build it once per rule set; patterns are prepared in `init`.
public struct FilterEngine {
    private struct CompiledRule {
        let rule: Rule
        let text: String
        let regex: NSRegularExpression?
        let senderRegex: NSRegularExpression?
        let unlessRegex: NSRegularExpression?
    }

    private let compiledRules: [CompiledRule]
    private let classifier: SpamClassifier?

    /// `classifier` is asked only when no rule matched, see `SpamClassifier`.
    public init(rules: [Rule], classifier: SpamClassifier? = nil) {
        self.classifier = classifier
        compiledRules = rules.compactMap { rule in
            // Same checks as `validationError`, without compiling each regex a second time.
            guard rule.isEnabled, !rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var senderRegex: NSRegularExpression?
            if let senderPattern = rule.senderPattern {
                guard let regex = try? NSRegularExpression(pattern: senderPattern, options: [.caseInsensitive]) else { return nil }
                senderRegex = regex
            }
            var unlessRegex: NSRegularExpression?
            if let unlessPattern = rule.unlessPattern {
                let pattern = TextNormalizer.foldRegexPattern(unlessPattern)
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
                unlessRegex = regex
            }

            switch rule.matchType {
            case .regex:
                let pattern = TextNormalizer.foldRegexPattern(rule.pattern)
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
                return CompiledRule(rule: rule, text: pattern, regex: regex, senderRegex: senderRegex, unlessRegex: unlessRegex)
            case .contains, .prefix:
                let text = rule.target == .sender
                    ? TextNormalizer.normalizeSender(rule.pattern)
                    : TextNormalizer.normalize(rule.pattern)
                return CompiledRule(rule: rule, text: text, regex: nil, senderRegex: senderRegex, unlessRegex: unlessRegex)
            }
        }
    }

    public func evaluate(sender: String?, body: String?) -> FilterDecision {
        let normalizedSender = sender.map(TextNormalizer.normalizeSender) ?? ""
        let normalizedBody = body.map(TextNormalizer.normalize) ?? ""

        var best: Rule?
        for compiled in compiledRules {
            let input = compiled.rule.target == .sender ? normalizedSender : normalizedBody
            guard !input.isEmpty, matches(compiled, input) else { continue }
            if let senderRegex = compiled.senderRegex, !Self.finds(senderRegex, in: normalizedSender) { continue }
            if let unlessRegex = compiled.unlessRegex, Self.finds(unlessRegex, in: normalizedBody) { continue }

            // Rules earlier in the list win ties.
            if let current = best, compiled.rule.action.precedence <= current.action.precedence { continue }
            best = compiled.rule
            if compiled.rule.action == .allow { break }
        }

        if let best { return FilterDecision(action: best.action, matchedRule: best) }
        if let classifier, let action = classifier.verdict(normalized: normalizedBody) {
            return FilterDecision(action: action, matchedRule: nil, isFromClassifier: true)
        }
        return FilterDecision(action: .allow, matchedRule: nil)
    }

    private func matches(_ compiled: CompiledRule, _ input: String) -> Bool {
        switch compiled.rule.matchType {
        case .contains:
            return input.contains(compiled.text)
        case .prefix:
            return input.hasPrefix(compiled.text)
        case .regex:
            return compiled.regex.map { Self.finds($0, in: input) } ?? false
        }
    }

    private static func finds(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
