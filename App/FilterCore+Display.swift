import FilterCore
import SwiftUI

extension FilterAction {
    var title: String {
        switch self {
        case .allow: return String(localized: "İzin ver")
        case .junk: return String(localized: "Gereksiz")
        case .promotion: return String(localized: "Promosyonlar")
        case .transaction: return String(localized: "İşlemler")
        }
    }

    /// Where a matching message ends up, as a sentence.
    var outcome: String {
        switch self {
        case .allow: return String(localized: "Gelen kutusuna gelir")
        case .junk: return String(localized: "Gereksiz'e gider")
        case .promotion: return String(localized: "Promosyonlar'a gider")
        case .transaction: return String(localized: "İşlemler'e gider")
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

extension MessageKind {
    /// Button title for teaching the classifier.
    var title: String {
        switch self {
        case .junk: return String(localized: "Spam")
        case .promotion: return String(localized: "Kampanya")
        case .transaction: return String(localized: "Bildirim")
        case .personal: return String(localized: "Kişisel")
        }
    }
}

extension RuleTarget {
    var title: String {
        switch self {
        case .body: return String(localized: "Mesaj metni")
        case .sender: return String(localized: "Gönderici")
        }
    }
}

extension MatchType {
    var title: String {
        switch self {
        case .contains: return String(localized: "İçerir")
        case .prefix: return String(localized: "Şununla başlar")
        case .regex: return String(localized: "Regex")
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
        case .scam: return String(localized: "Dolandırıcılık")
        case .ads: return String(localized: "Bahis ve kredi reklamı")
        case .links: return String(localized: "Şüpheli linkler")
        case .sorting: return String(localized: "Klasörlere ayırma")
        case .other: return String(localized: "Diğer korumalar")
        case .strict: return String(localized: "Sıkı korumalar")
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
        case .scam: return String(localized: "Gerçek kurumların .tr adreslerine ve kendi numaralarına dokunmaz.")
        case .ads, .links, .other: return nil
        case .sorting: return String(localized: "Bu mesajlar silinmez; Mesajlar'daki Promosyonlar ve İşlemler klasörlerine ayrılır.")
        case .strict: return String(localized: "Varsayılan olarak kapalı. Açarsan bazı gerçek mesajlar da Gereksiz'e düşebilir.")
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
        switch (matchType, target) {
        case (.contains, .sender): return String(localized: "Gönderici \"\(pattern)\" içeriyorsa")
        case (.contains, .body): return String(localized: "Mesaj \"\(pattern)\" içeriyorsa")
        case (.prefix, .sender): return String(localized: "Gönderici \"\(pattern)\" ile başlıyorsa")
        case (.prefix, .body): return String(localized: "Mesaj \"\(pattern)\" ile başlıyorsa")
        case (.regex, _): return String(localized: "Gelişmiş desen (regex)")
        }
    }
}
