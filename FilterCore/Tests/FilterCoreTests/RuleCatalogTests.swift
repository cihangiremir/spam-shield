import Foundation
import Testing
@testable import FilterCore

struct RuleCatalogTests {
    /// A list file with the given rules, written the way `rules.json` is.
    private func catalogData(version: Int = 1, fragments: [String: String] = [:], rules: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": version, "fragments": fragments, "rules": rules])
    }

    private func entry(id: String = "test", pattern: String = "abc", action: String = "junk", matchType: String = "regex") -> [String: Any] {
        ["id": id, "name": id, "category": "scam", "details": "Test", "matchType": matchType, "pattern": pattern, "action": action]
    }

    @Test func bundledListIsComplete() {
        let catalog = RuleCatalog.bundled
        #expect(catalog.version > 0)
        #expect(!catalog.rules.isEmpty)
        for rule in catalog.rules {
            #expect(rule.builtInID != nil, "\(rule.name)")
            #expect(rule.category != nil, "\(rule.name)")
            #expect(rule.details?.isEmpty == false, "\(rule.name)")
        }
    }

    @Test func bundledListJunksNoLegitimateMessage() throws {
        try RuleCatalog.bundled.checkNoJunk()
    }

    @Test func readsOptionalFieldsWithDefaults() throws {
        var disabled = entry(id: "b")
        disabled["isEnabled"] = false
        disabled["target"] = "sender"
        let catalog = try RuleCatalog(data: catalogData(version: 7, rules: [entry(id: "a"), disabled]))

        #expect(catalog.version == 7)
        #expect(catalog.rules.map(\.builtInID) == ["a", "b"])
        #expect(catalog.rules[0].isEnabled && catalog.rules[0].target == .body)
        #expect(!catalog.rules[1].isEnabled && catalog.rules[1].target == .sender)
        #expect(catalog.rules[0].category == "scam" && catalog.rules[0].details == "Test")
    }

    @Test func usesTranslationForLanguageAndTurkishOtherwise() throws {
        var translated = entry(id: "a")
        translated["translations"] = ["en": ["name": "English name", "details": "English details"]]
        var nameOnly = entry(id: "b")
        nameOnly["translations"] = ["en": ["name": "Only name"]]
        let data = try catalogData(rules: [translated, nameOnly])

        let english = try RuleCatalog(data: data, language: "en")
        #expect(english.rules.map(\.name) == ["English name", "Only name"])
        #expect(english.rules.map(\.details) == ["English details", "Test"])

        let turkish = try RuleCatalog(data: data, language: "tr")
        #expect(turkish.rules.map(\.name) == ["a", "b"])
        #expect(turkish.rules.map(\.details) == ["Test", "Test"])
    }

    @Test func expandsFragmentsInsideFragments() throws {
        let fragments = ["inner": "xyz|top", "outer": "com|{{inner}}"]
        #expect(try RuleCatalog.expand(#"\.({{outer}})\b"#, fragments: fragments) == #"\.(com|xyz|top)\b"#)
        #expect(try RuleCatalog.expand("no fragments", fragments: fragments) == "no fragments")
    }

    @Test func rejectsUnknownFragment() {
        #expect(throws: RuleCatalogError.unknownFragment("missing")) {
            try RuleCatalog(data: catalogData(rules: [entry(pattern: "a{{missing}}")]))
        }
        #expect(throws: RuleCatalogError.unknownFragment("{{open")) {
            try RuleCatalog.expand("a{{open", fragments: [:])
        }
    }

    @Test func rejectsFragmentLoop() {
        #expect(throws: RuleCatalogError.fragmentLoop) {
            try RuleCatalog(data: catalogData(fragments: ["a": "{{b}}", "b": "{{a}}"], rules: [entry(pattern: "{{a}}")]))
        }
    }

    @Test func rejectsInvalidRegex() {
        #expect(throws: (any Error).self) {
            try RuleCatalog(data: catalogData(rules: [entry(pattern: "(abc")]))
        }
    }

    @Test func rejectsDuplicateIDEmptyListAndBrokenFile() {
        #expect(throws: RuleCatalogError.duplicateID("a")) {
            try RuleCatalog(data: catalogData(rules: [entry(id: "a"), entry(id: "a")]))
        }
        #expect(throws: RuleCatalogError.empty) {
            try RuleCatalog(data: catalogData(rules: []))
        }
        #expect(throws: RuleCatalogError.unreadable) {
            try RuleCatalog(data: Data("<html>404</html>".utf8))
        }
        #expect(throws: RuleCatalogError.unreadable) {
            try RuleCatalog(data: catalogData(rules: [entry(action: "delete")]))
        }
    }

    @Test func checkNoJunkRejectsRuleThatJunksLegitimateMessages() throws {
        let catalog = try RuleCatalog(data: catalogData(rules: [entry(pattern: ".")]))
        #expect(throws: (any Error).self) { try catalog.checkNoJunk() }

        let promotion = try RuleCatalog(data: catalogData(rules: [entry(pattern: ".", action: "promotion")]))
        try promotion.checkNoJunk()
    }

    /// App versions before `senderPattern` and `unlessPattern` ignore them and would apply "phone-lure" to every
    /// sender and junk loan campaigns that say how to opt out. Their own download check has to refuse the list,
    /// which it does through the Hepsiburada sample.
    @Test func olderAppsRefuseRulesThatNeedACondition() {
        let asOlderAppsSeeThem = RuleCatalog.bundled.rules.map { rule in
            var rule = rule
            rule.senderPattern = nil
            rule.unlessPattern = nil
            return rule
        }
        let engine = FilterEngine(rules: asOlderAppsSeeThem)
        #expect(RuleCatalog.legitimateSamples.contains { engine.evaluate(sender: nil, body: $0).action == .junk })
    }
}

struct RuleStoreCatalogTests {
    private func makeStore() -> (RuleStore, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (RuleStore(fileURL: folder.appendingPathComponent("rules.json")), folder)
    }

    private func catalogData(version: Int, pattern: String = "yeni kural") throws -> Data {
        let rule: [String: Any] = [
            "id": "downloaded", "name": "İndirilen", "category": "scam", "details": "Test",
            "matchType": "contains", "pattern": pattern, "action": "junk",
        ]
        return try JSONSerialization.data(withJSONObject: ["version": version, "rules": [rule]])
    }

    @Test func usesDownloadedListOnlyWhenNewer() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundledVersion = RuleCatalog.bundled.version

        try store.saveCatalog(catalogData(version: bundledVersion))
        #expect(store.loadCatalog() == .bundled)

        try store.saveCatalog(catalogData(version: bundledVersion + 1))
        #expect(store.loadCatalog().version == bundledVersion + 1)
        #expect(store.load().map(\.builtInID) == ["downloaded"])
    }

    @Test func ignoresBrokenDownloadedList() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }

        try Data("not json".utf8).write(to: store.catalogURL)

        #expect(store.loadCatalog() == .bundled)
        #expect(store.load() == DefaultRules.all)
    }

    @Test func savedRulesFollowDownloadedList() throws {
        let (store, folder) = makeStore()
        defer { try? FileManager.default.removeItem(at: folder) }
        let own = Rule(name: "kendi", pattern: "abc", action: .junk)
        try store.save(DefaultRules.all + [own])

        try store.saveCatalog(catalogData(version: RuleCatalog.bundled.version + 1))
        let rules = store.load()

        // Built-in rules dropped from the download are removed; the user's own rule stays.
        #expect(rules.map(\.builtInID) == [nil, "downloaded"])
        #expect(rules.first == own)
    }
}
