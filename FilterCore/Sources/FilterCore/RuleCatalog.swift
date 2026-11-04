import Foundation

/// The built-in rules, read from `Resources/rules.json`. The same file is published from GitHub,
/// so the app can pick up new rules without an update (see README, "Kural listesini güncelleme").
///
/// File format:
/// - `version`: a downloaded list replaces the current one only when its version is higher.
/// - `fragments`: pattern parts shared by several rules, used in patterns as `{{name}}`.
///   A fragment may use other fragments.
/// - `rules`: `id` (the rule's `builtInID`), `name`, `category`, `details`, `matchType`, `pattern`, `action`,
///   and optionally `target` (default `body`), `isEnabled` (default true) and `note` (for maintainers, not shown).
public struct RuleCatalog: Equatable, Sendable {
    public let version: Int
    public let rules: [Rule]

    /// The list that ships with the app. It is tested on every build, so failing to read it is a packaging bug.
    public static let bundled: RuleCatalog = {
        do {
            return try RuleCatalog(data: resource("rules"))
        } catch {
            fatalError("Bundled rules.json can't be read: \(error)")
        }
    }()

    /// Real messages no rule may send to Junk. Downloaded lists are checked against them,
    /// and the tests check the bundled list. Kept in the app, so a bad download can't weaken the check.
    public static let legitimateSamples: [String] = {
        do {
            return try JSONDecoder().decode([String].self, from: resource("legitimate-samples"))
        } catch {
            fatalError("Bundled legitimate-samples.json can't be read: \(error)")
        }
    }()

    /// Reads and checks a list: every fragment exists, every pattern compiles and every id is unique.
    public init(data: Data) throws {
        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw RuleCatalogError.unreadable
        }
        guard !file.rules.isEmpty else { throw RuleCatalogError.empty }

        let fragments = file.fragments ?? [:]
        var seenIDs: Set<String> = []
        var rules: [Rule] = []
        for entry in file.rules {
            guard seenIDs.insert(entry.id).inserted else { throw RuleCatalogError.duplicateID(entry.id) }
            let rule = Rule(
                name: entry.name,
                isEnabled: entry.isEnabled ?? true,
                target: entry.target ?? .body,
                matchType: entry.matchType,
                pattern: try Self.expand(entry.pattern, fragments: fragments),
                action: entry.action,
                builtInID: entry.id,
                category: entry.category,
                details: entry.details
            )
            if let error = rule.validationError { throw RuleCatalogError.invalidRule(entry.name, error) }
            rules.append(rule)
        }

        version = file.version
        self.rules = rules
    }

    /// Throws when any enabled rule would send one of the messages to Junk.
    public func checkNoJunk(in messages: [String] = legitimateSamples) throws {
        let engine = FilterEngine(rules: rules)
        for message in messages {
            let decision = engine.evaluate(sender: nil, body: message)
            if decision.action == .junk {
                throw RuleCatalogError.junksLegitimateMessage(rule: decision.matchedRule?.name ?? "", message: message)
            }
        }
    }

    /// Replaces each `{{name}}` with the fragment. Fragments can use other fragments.
    static func expand(_ pattern: String, fragments: [String: String], depth: Int = 0) throws -> String {
        // Real lists nest one level; this deep means two fragments use each other.
        guard depth < 5 else { throw RuleCatalogError.fragmentLoop }

        var result = ""
        var rest = pattern[...]
        while let start = rest.range(of: "{{") {
            result += rest[..<start.lowerBound]
            guard let end = rest.range(of: "}}", range: start.upperBound..<rest.endIndex) else {
                throw RuleCatalogError.unknownFragment(String(rest[start.lowerBound...]))
            }
            let name = String(rest[start.upperBound..<end.lowerBound])
            guard let value = fragments[name] else { throw RuleCatalogError.unknownFragment(name) }
            result += try expand(value, fragments: fragments, depth: depth + 1)
            rest = rest[end.upperBound...]
        }
        return result + rest
    }

    private static func resource(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    private struct File: Decodable {
        let version: Int
        let fragments: [String: String]?
        let rules: [Entry]
    }

    private struct Entry: Decodable {
        let id: String
        let name: String
        let category: String?
        let details: String?
        let target: RuleTarget?
        let matchType: MatchType
        let pattern: String
        let action: FilterAction
        let isEnabled: Bool?
    }
}

public enum RuleCatalogError: Error, Equatable, LocalizedError {
    case unreadable
    case empty
    case duplicateID(String)
    case unknownFragment(String)
    case fragmentLoop
    case invalidRule(String, String)
    case junksLegitimateMessage(rule: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "Kural listesi okunamadı."
        case .empty: return "Kural listesi boş."
        case .duplicateID(let id): return "Kural listesinde aynı kimlik iki kez geçiyor: \(id)."
        case .unknownFragment(let name): return "Kural listesinde tanımsız bir parça var: \(name)."
        case .fragmentLoop: return "Kural listesindeki parçalar birbirini kullanıyor."
        case .invalidRule(let name, let error): return "\"\(name)\" kuralı kullanılamıyor: \(error)"
        case .junksLegitimateMessage(let rule, let message):
            return "\"\(rule)\" kuralı normal bir mesajı Gereksiz'e atıyor: \"\(message)\""
        }
    }
}
