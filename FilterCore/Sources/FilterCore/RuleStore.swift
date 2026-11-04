import Foundation

/// Reads and writes the rule list as JSON. The app writes it into the shared App Group container,
/// the filter extension only reads it (iOS doesn't let message filter extensions write there).
public struct RuleStore {
    /// Must match the App Group in both targets' entitlements (see project.yml).
    public static let appGroupIdentifier = "group.com.emirchngr.spamshield"

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Store in the shared App Group container. Nil if the App Group isn't set up in signing.
    public static func shared() -> RuleStore? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            .map { RuleStore(fileURL: $0.appendingPathComponent("rules.json")) }
    }

    /// The downloaded rule list, saved next to the rules file (see `saveCatalog`).
    public var catalogURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("rule-catalog.json")
    }

    /// The newest built-in rules: the downloaded list when it is readable and newer than the one in this
    /// app version, otherwise the bundled one. An app update with a newer bundled list wins over an old download.
    public func loadCatalog() -> RuleCatalog {
        guard let data = try? Data(contentsOf: catalogURL),
              let downloaded = try? RuleCatalog(data: data),
              downloaded.version > RuleCatalog.bundled.version
        else { return .bundled }
        return downloaded
    }

    /// Saves a downloaded list. The caller checks it first (`RuleCatalog(data:)`, `checkNoJunk()`).
    public func saveCatalog(_ data: Data) throws {
        try data.write(to: catalogURL, options: .atomic)
    }

    /// Saved rules brought up to date with the newest built-in rules (see `loadCatalog()`), or those rules
    /// when nothing has been saved yet or the file can't be read.
    /// Falling back keeps filtering working instead of silently letting everything through.
    /// Merging here means the extension uses improved built-in rules right after an app update or download,
    /// even before the app is opened and saves them.
    public func load() -> [Rule] {
        (try? loadForEditing()) ?? loadCatalog().rules
    }

    /// Like `load()`, but throws when the file exists and can't be read, instead of falling back.
    /// The app uses this so it doesn't save the defaults over the user's unreadable rules.
    public func loadForEditing() throws -> [Rule] {
        let latest = loadCatalog().rules
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return latest }
        return DefaultRules.merged(with: try Self.decode(Data(contentsOf: fileURL)), latest: latest)
    }

    public func save(_ rules: [Rule]) throws {
        try Self.encode(rules).write(to: fileURL, options: .atomic)
    }

    // Also used for import / export, so the exported file is the same format as the stored one.

    public static func encode(_ rules: [Rule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(rules)
    }

    public static func decode(_ data: Data) throws -> [Rule] {
        try JSONDecoder().decode([Rule].self, from: data)
    }
}
