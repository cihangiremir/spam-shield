import Foundation

public struct FilterDecision: Equatable, Sendable {
    public let action: FilterAction
    /// The rule that decided the action. Nil means no rule matched: the message is allowed,
    /// or sent to Promotions when `isFromClassifier`.
    public let matchedRule: Rule?
    /// True when no rule matched and the classifier found the message spammy.
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
    }

    private let compiledRules: [CompiledRule]
    private let classifier: SpamClassifier?

    /// `classifier` is asked only when no rule matched, see `SpamClassifier`.
    public init(rules: [Rule], classifier: SpamClassifier? = nil) {
        self.classifier = classifier
        compiledRules = rules.compactMap { rule in
            // Same checks as `validationError`, without compiling each regex a second time.
            guard rule.isEnabled, !rule.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

            switch rule.matchType {
            case .regex:
                let pattern = TextNormalizer.foldRegexPattern(rule.pattern)
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
                return CompiledRule(rule: rule, text: pattern, regex: regex)
            case .contains, .prefix:
                let text = rule.target == .sender
                    ? TextNormalizer.normalizeSender(rule.pattern)
                    : TextNormalizer.normalize(rule.pattern)
                return CompiledRule(rule: rule, text: text, regex: nil)
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

            // Rules earlier in the list win ties.
            if let current = best, compiled.rule.action.precedence <= current.action.precedence { continue }
            best = compiled.rule
            if compiled.rule.action == .allow { break }
        }

        if let best { return FilterDecision(action: best.action, matchedRule: best) }
        if let classifier, let body, classifier.isJunk(body) {
            return FilterDecision(action: .promotion, matchedRule: nil, isFromClassifier: true)
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
            let range = NSRange(input.startIndex..., in: input)
            return compiled.regex?.firstMatch(in: input, range: range) != nil
        }
    }
}
