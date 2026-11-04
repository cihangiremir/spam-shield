import FilterCore
import SwiftUI

extension FilterAction {
    var title: String {
        switch self {
        case .allow: return "İzin ver"
        case .junk: return "Gereksiz"
        case .promotion: return "Promosyonlar"
        case .transaction: return "İşlemler"
        }
    }

    /// Where a matching message ends up, as a sentence.
    var outcome: String {
        switch self {
        case .allow: return "Gelen kutusuna gelir"
        case .junk: return "Gereksiz'e gider"
        case .promotion: return "Promosyonlar'a gider"
        case .transaction: return "İşlemler'e gider"
        }
    }

    var systemImage: String {
        switch self {
        case .allow: return "checkmark.shield"
        case .junk: return "xmark.bin"
        case .promotion: return "tag"
        case .transaction: return "creditcard"
        }
    }

    var tint: Color {
        switch self {
        case .allow: return .green
        case .junk: return .red
        case .promotion: return .orange
        case .transaction: return .blue
        }
    }
}

extension RuleTarget {
    var title: String {
        switch self {
        case .body: return "Mesaj metni"
        case .sender: return "Gönderici"
        }
    }
}

extension MatchType {
    var title: String {
        switch self {
        case .contains: return "İçerir"
        case .prefix: return "Şununla başlar"
        case .regex: return "Regex"
        }
    }
}

/// Groups the built-in rules on the Rules screen. Raw values are the `category` values in rules.json.
enum RuleCategory: String, CaseIterable {
    case scam
    case ads
    case links
    case sorting
    /// A category this app version doesn't know yet, from a newer downloaded rule list.
    case other
    case strict

    var title: String {
        switch self {
        case .scam: return "Dolandırıcılık"
        case .ads: return "Bahis ve kredi reklamı"
        case .links: return "Şüpheli linkler"
        case .sorting: return "Klasörlere ayırma"
        case .other: return "Diğer korumalar"
        case .strict: return "Sıkı korumalar"
        }
    }

    var systemImage: String {
        switch self {
        case .scam: return "exclamationmark.shield"
        case .ads: return "megaphone"
        case .links: return "link"
        case .sorting: return "tray.2"
        case .other: return "shield"
        case .strict: return "lock.shield"
        }
    }

    var footer: String? {
        switch self {
        case .scam: return "Gerçek kurumların .tr adreslerine ve kendi numaralarına dokunmaz."
        case .ads, .links, .other: return nil
        case .sorting: return "Bu mesajlar silinmez; Mesajlar'daki Promosyonlar ve İşlemler klasörlerine ayrılır."
        case .strict: return "Varsayılan olarak kapalı. Açarsan bazı gerçek mesajlar da Gereksiz'e düşebilir."
        }
    }
}

extension Rule {
    /// Nil for the user's own rules, which the Rules screen lists separately.
    var displayCategory: RuleCategory? {
        guard builtInID != nil else { return nil }
        return RuleCategory(rawValue: category ?? "") ?? .other
    }

    /// One line for the list: the explanation for built-in rules, what the rule looks for otherwise.
    var summary: String {
        if let details { return details }
        let subject = target == .sender ? "Gönderici" : "Mesaj"
        switch matchType {
        case .contains: return "\(subject) \"\(pattern)\" içeriyorsa"
        case .prefix: return "\(subject) \"\(pattern)\" ile başlıyorsa"
        case .regex: return "Gelişmiş desen (regex)"
        }
    }
}
