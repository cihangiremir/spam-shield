import Foundation

/// Where a message ends up. Maps 1:1 to `ILMessageFilterAction` in the extension.
public enum FilterAction: String, Codable, CaseIterable, Sendable {
    case allow
    case junk
    case promotion
    case transaction

    /// When several rules match, the action with the highest precedence wins.
    /// An explicit allow always beats everything else so the user can rescue a sender.
    /// A transaction beats a promotion: OTPs, card alerts and delivery notices carry the same footers as campaigns
    /// (Mersis, RET, "B0xx"), while the transaction rules are kept narrow enough not to catch campaigns.
    var precedence: Int {
        switch self {
        case .allow: return 3
        case .junk: return 2
        case .transaction: return 1
        case .promotion: return 0
        }
    }
}

/// Which part of the message a rule looks at.
public enum RuleTarget: String, Codable, CaseIterable, Sendable {
    case body
    case sender
}

public enum MatchType: String, Codable, CaseIterable, Sendable {
    /// Plain text search. Case, Turkish characters and spacing are ignored ("Kazandınız" == "kazandiniz").
    case contains
    /// Text must start with the pattern. Mostly for sender numbers such as "+90850".
    case prefix
    /// Regular expression, run against the normalized (lowercased, Turkish-folded) text.
    case regex
}

public struct Rule: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var target: RuleTarget
    public var matchType: MatchType
    public var pattern: String
    public var action: FilterAction
    /// Set for rules that ship with the app (see `DefaultRules`), nil for the user's own rules.
    /// Lets app updates deliver improved versions of these rules.
    public var builtInID: String?
    /// True once the user edits a built-in rule. App updates then leave it alone.
    public var isCustomized: Bool
    /// Built-in rules only: the group the Rules screen lists it under (e.g. "scam") and a plain-language
    /// explanation shown instead of the pattern. Both come from `RuleCatalog`.
    public var category: String?
    public var details: String?
    /// A regex the sender must match too, run on `TextNormalizer.normalizeSender` output. A missing sender counts
    /// as empty text. Only built-in rules set it, e.g. so a phone number never gets a message into Transactions.
    public var senderPattern: String?
    /// A regex on the message text that, when found, keeps the rule from applying (an exception such as
    /// "has opt-out info"). Runs on normalized text like a regex pattern. Only built-in rules set it.
    public var unlessPattern: String?

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        target: RuleTarget = .body,
        matchType: MatchType = .contains,
        pattern: String,
        action: FilterAction,
        builtInID: String? = nil,
        isCustomized: Bool = false,
        category: String? = nil,
        details: String? = nil,
        senderPattern: String? = nil,
        unlessPattern: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.target = target
        self.matchType = matchType
        self.pattern = pattern
        self.action = action
        self.builtInID = builtInID
        self.isCustomized = isCustomized
        self.category = category
        self.details = details
        self.senderPattern = senderPattern
        self.unlessPattern = unlessPattern
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        target = try container.decode(RuleTarget.self, forKey: .target)
        matchType = try container.decode(MatchType.self, forKey: .matchType)
        pattern = try container.decode(String.self, forKey: .pattern)
        action = try container.decode(FilterAction.self, forKey: .action)
        builtInID = try container.decodeIfPresent(String.self, forKey: .builtInID)
        // Hand-written rule files usually leave this out.
        isCustomized = try container.decodeIfPresent(Bool.self, forKey: .isCustomized) ?? false
        category = try container.decodeIfPresent(String.self, forKey: .category)
        details = try container.decodeIfPresent(String.self, forKey: .details)
        senderPattern = try container.decodeIfPresent(String.self, forKey: .senderPattern)
        unlessPattern = try container.decodeIfPresent(String.self, forKey: .unlessPattern)
    }

    /// Message shown in the rule editor when the pattern can't be used, otherwise nil.
    public var validationError: String? {
        if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "The pattern can't be empty.", bundle: .module)
        }
        if matchType == .regex, (try? NSRegularExpression(pattern: TextNormalizer.foldRegexPattern(pattern))) == nil {
            return String(localized: "Invalid regex.", bundle: .module)
        }
        if let senderPattern, (try? NSRegularExpression(pattern: senderPattern)) == nil {
            return String(localized: "Invalid regex.", bundle: .module)
        }
        if let unlessPattern, (try? NSRegularExpression(pattern: TextNormalizer.foldRegexPattern(unlessPattern))) == nil {
            return String(localized: "Invalid regex.", bundle: .module)
        }
        return nil
    }
}
