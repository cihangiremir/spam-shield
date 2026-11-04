import Foundation

public struct FilterDecision: Equatable, Sendable {
    public let action: FilterAction
    /// The rule that decided the action. Nil means nothing matched and the message is allowed.
    public let matchedRule: Rule?
}

/// Runs the rules against one message. Build it once per rule set; patterns are prepared in `init`.
public struct FilterEngine {
    private struct CompiledRule {
        let rule: Rule
        let text: String
        let regex: NSRegularExpression?
    }

    private let compiledRules: [CompiledRule]

    public init(rules: [Rule]) {
        compiledRules = rules.compactMap { rule in
            guard rule.isEnabled, rule.validationError == nil else { return nil }

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

        return FilterDecision(action: best?.action ?? .allow, matchedRule: best)
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
