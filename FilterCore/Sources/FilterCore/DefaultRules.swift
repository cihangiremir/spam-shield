import Foundation

/// Rules the app starts with. They live in `Resources/rules.json` (see `RuleCatalog`).
/// Regex patterns run on normalized text, so they are written lowercase and without Turkish characters
/// ("kazandiniz", not "Kazandınız").
public enum DefaultRules {
    public static var all: [Rule] { RuleCatalog.bundled.rules }

    /// Brings saved rules up to date with the latest built-in rules (the bundled list or a newer downloaded one):
    /// - built-in rules the user hasn't edited get the latest pattern, keeping their on/off state,
    /// - new built-in rules are appended,
    /// - dropped built-in rules are removed unless the user edited them,
    /// - the user's own and edited rules are kept as they are; edited built-in rules still get the latest
    ///   category and explanation, so they stay in their group on the Rules screen.
    public static func merged(with saved: [Rule], latest: [Rule] = all) -> [Rule] {
        let latestByID = Dictionary(uniqueKeysWithValues: latest.compactMap { rule in rule.builtInID.map { ($0, rule) } })

        var result: [Rule] = []
        for rule in saved {
            guard let builtInID = rule.builtInID else {
                result.append(rule)
                continue
            }
            let newest = latestByID[builtInID]
            if rule.isCustomized {
                var kept = rule
                if let newest {
                    kept.category = newest.category
                    kept.details = newest.details
                }
                result.append(kept)
                continue
            }
            guard var updated = newest else { continue }
            updated.id = rule.id
            updated.isEnabled = rule.isEnabled
            result.append(updated)
        }

        let savedBuiltInIDs = Set(saved.compactMap(\.builtInID))
        result += latest.filter { !savedBuiltInIDs.contains($0.builtInID ?? "") }
        return result
    }
}
