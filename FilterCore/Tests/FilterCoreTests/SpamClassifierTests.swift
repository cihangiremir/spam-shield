import Foundation
import Testing
@testable import FilterCore

struct SpamClassifierTests {
    /// Small model where "kazanc", "oyna" and "ornekbet.vip" only appear in junk, "teslim" and "takip" only in notices.
    private var toyClassifier: SpamClassifier {
        var classifier = SpamClassifier()
        for _ in 0..<3 {
            classifier.learn("Kazanç seni bekliyor, hemen oyna, hemen kazan: ornekbet.vip", as: .junk)
            classifier.learn("Paketiniz teslim edildi, takip numarası teslimat kargo", as: .transaction)
        }
        for text in ["Yarın görüşelim mi?", "Toplantı saat 10'da", "Akşam yemeğe gel", "Ne zaman geliyorsun", "Annem aradı"] {
            for _ in 0..<3 { classifier.learn(text, as: .personal) }
        }
        return classifier
    }

    @Test func tokensAreFoldedWordsDomainsLinksAndNumbers() {
        let tokens = SpamClassifier.tokens(in: "KAZANÇ 500 TL: https://x.ornekbet.vip/a ödül")
        #expect(tokens == ["kazanc", "tl", "odul", "d:ornekbet.vip", "<link>", "<num>"])
        #expect(SpamClassifier.tokens(in: "Detay: ornek.com.tr/takip") == ["detay", "d:ornek.com.tr"])
    }

    @Test func emptyClassifierMovesNothing() {
        #expect(SpamClassifier().verdict("Kazanç seni bekliyor") == nil)
    }

    /// Without personal messages it can't tell what to leave alone.
    @Test func classifierWithoutPersonalMessagesMovesNothing() {
        var classifier = SpamClassifier()
        classifier.learn("Kazanç seni bekliyor", as: .junk)
        #expect(classifier.verdict("Kazanç seni bekliyor") == nil)
    }

    @Test func sortsByWhatItLearned() {
        let classifier = toyClassifier
        #expect(classifier.verdict("Kazanç seni bekliyor, hemen oyna, hemen kazan: ornekbet.vip") == .promotion)
        #expect(classifier.verdict("Paketiniz teslim edildi, takip numarası kargo") == .transaction)
        #expect(classifier.verdict("Yarın toplantı var mı?") == nil)
    }

    @Test func movesOnlyClearCases() {
        let personal = -10.0
        #expect(SpamClassifier.verdict(for: [.personal: personal, .promotion: personal + 7]) == nil)
        #expect(SpamClassifier.verdict(for: [.personal: personal, .promotion: personal + 9]) == .promotion)
        #expect(SpamClassifier.verdict(for: [.personal: personal, .transaction: personal + 9]) == .transaction)
        // Could be a notice: it isn't sent to Promotions.
        #expect(SpamClassifier.verdict(for: [.personal: personal, .junk: personal + 10, .transaction: personal + 9]) == .transaction)
        #expect(SpamClassifier.verdict(for: [.personal: personal, .junk: personal + 10, .transaction: personal + 1]) == .promotion)
    }

    @Test func survivesSavingAndReading() throws {
        let classifier = toyClassifier
        let decoded = try JSONDecoder().decode(SpamClassifier.self, from: JSONEncoder().encode(classifier))
        #expect(decoded == classifier)
        #expect(decoded.scores("kazanç oyna") == classifier.scores("kazanç oyna"))
    }

    /// What an older app version saved, with "not spam" read as personal.
    @Test func readsTheTwoKindFormat() throws {
        let json = #"{"junkMessages": 2, "otherMessages": 3, "junkTokens": {"kazanc": 2}, "otherTokens": {"yarin": 3}}"#
        let decoded = try JSONDecoder().decode(SpamClassifier.self, from: Data(json.utf8))
        #expect(decoded.messages == [.junk: 2, .personal: 3])
        #expect(decoded.tokens[.junk] == ["kazanc": 2])
        #expect(decoded.tokens[.personal] == ["yarin": 3])
    }

    @Test func pruningDropsRareTokens() {
        var classifier = toyClassifier
        classifier.learn("tekseferlikkelime", as: .junk)
        #expect(classifier.tokens[.junk]?["tekseferlikkelime"] == 1)
        let pruned = classifier.pruned(minimumCount: 3)
        #expect(pruned.tokens[.junk]?["tekseferlikkelime"] == nil)
        #expect(pruned.tokens[.junk]?["kazanc"] == 3)
    }

    @Test func addingCombinesCounts() {
        let combined = toyClassifier.adding(toyClassifier)
        #expect(combined.messages[.junk] == 6)
        #expect(combined.tokens[.transaction]?["teslim"] == 6)
    }

    // MARK: Bundled model

    @Test func bundledModelIsLoaded() {
        for kind in MessageKind.allCases { #expect(SpamClassifier.bundled.messages[kind, default: 0] > 1000) }
    }

    @Test func bundledModelCatchesBettingSpam() {
        #expect(SpamClassifier.bundled.verdict("Kayıp bonusu ve freespin hediyesi seni bekliyor! Hemen yatır, anlık çekim: https://t2m.io/xyz") == .promotion)
    }

    /// A spammer controls the text and the filter extension has little time per message.
    @Test(.timeLimit(.minutes(1)), arguments: ["a ", "a.1", "kazanc ", "https://a.b/"])
    func longRepetitiveTextIsFast(unit: String) {
        let text = String(repeating: unit, count: 3000 / unit.count)
        let duration = ContinuousClock().measure { _ = SpamClassifier.bundled.scores(text) }
        #expect(duration < .milliseconds(200))
    }

    // MARK: Engine

    @Test func engineAsksClassifierOnlyWhenNoRuleMatched() {
        let transaction = Rule(name: "Kargo", pattern: "kargonuz", action: .transaction)
        let engine = FilterEngine(rules: [transaction], classifier: toyClassifier)

        let spam = engine.evaluate(sender: nil, body: "Kazanç seni bekliyor, hemen oyna, hemen kazan: ornekbet.vip")
        #expect(spam.action == .promotion && spam.isFromClassifier && spam.matchedRule == nil)

        let notice = engine.evaluate(sender: nil, body: "Paketiniz teslim edildi, takip numarası kargo")
        #expect(notice.action == .transaction && notice.isFromClassifier)

        let matched = engine.evaluate(sender: nil, body: "Kargonuz yolda, büyük kazanç için hemen oyna, kazan: ornekbet.vip")
        #expect(matched.action == .transaction && !matched.isFromClassifier)

        let normal = engine.evaluate(sender: nil, body: "Yarın görüşelim mi?")
        #expect(normal.action == .allow && !normal.isFromClassifier)
    }

    @Test func engineWithoutClassifierAllowsUnmatchedMessages() {
        let decision = FilterEngine(rules: []).evaluate(sender: nil, body: "Büyük kazanç için oyna: ornekbet.vip")
        #expect(decision.action == .allow && !decision.isFromClassifier)
    }

    // MARK: Settings

    @Test func teachingOnceCorrectsTheVerdict() {
        let missedSpam = "Yeni platform zorbix ile her gün garantili zorbix getirisi: zorbix.top"
        var settings = ClassifierSettings()
        #expect(settings.classifier.verdict(missedSpam) == nil)
        settings.learn(missedSpam, as: .junk)
        #expect(settings.classifier.verdict(missedSpam) == .promotion)

        settings.learn(missedSpam, as: .personal)
        settings.learn(missedSpam, as: .personal)
        #expect(settings.classifier.verdict(missedSpam) == nil)

        let notice = "Zorbix aboneliğiniz yenilendi, zorbix hesabınızdan görebilirsiniz"
        settings.learn(notice, as: .transaction)
        #expect(settings.classifier.verdict(notice) == .transaction)
        #expect(settings.exampleCount == 4)
    }

    @Test func forgettingExamplesGoesBackToTheBundledModel() {
        var settings = ClassifierSettings()
        settings.learn("zorbix zorbix.top", as: .junk)
        settings.forgetExamples()
        #expect(settings.exampleCount == 0)
        #expect(settings.classifier == .bundled)
    }

    @Test func settingsAreSavedAndReadInTheStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RuleStore(fileURL: folder.appendingPathComponent("rules.json"))

        #expect(store.loadClassifierSettings() == ClassifierSettings())

        var settings = ClassifierSettings()
        settings.isEnabled = false  // the user turned it off; that choice must survive
        settings.learn("zorbix zorbix.top", as: .junk)
        try store.saveClassifierSettings(settings)
        #expect(store.loadClassifierSettings() == settings)
    }

    @Test func unreadableSettingsThrowForEditingButLoadAsDefaults() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = RuleStore(fileURL: folder.appendingPathComponent("rules.json"))
        try Data("not json".utf8).write(to: store.classifierURL)

        #expect(throws: (any Error).self) { try store.loadClassifierSettingsForEditing() }
        #expect(store.loadClassifierSettings() == ClassifierSettings())
    }

    /// A file from an app version with fewer fields still reads, instead of losing what the user taught.
    @Test func settingsWithMissingFieldsGetDefaults() throws {
        var settings = ClassifierSettings()
        settings.learn("zorbix zorbix.top", as: .junk)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        object["isEnabled"] = nil

        let decoded = try JSONDecoder().decode(ClassifierSettings.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.isEnabled)
        #expect(decoded.exampleCount == 1)
        #expect(decoded.learned == settings.learned)
    }
}
