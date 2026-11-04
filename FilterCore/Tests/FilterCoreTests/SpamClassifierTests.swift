import Foundation
import Testing
@testable import FilterCore

struct SpamClassifierTests {
    /// Small model where "kazanc", "oyna" and "ornekbet.vip" only appear in junk.
    private var toyClassifier: SpamClassifier {
        var classifier = SpamClassifier()
        for _ in 0..<3 {
            classifier.learn("Kazanç seni bekliyor, hemen oyna: ornekbet.vip", isJunk: true)
        }
        for text in ["Yarın görüşelim mi?", "Toplantı saat 10'da", "Kargonuz yola çıktı", "Akşam yemeğe gel", "Siparişiniz hazır"] {
            for _ in 0..<3 { classifier.learn(text, isJunk: false) }
        }
        return classifier
    }

    @Test func tokensAreFoldedWordsDomainsLinksAndNumbers() {
        let tokens = SpamClassifier.tokens(in: "KAZANÇ 500 TL: https://x.ornekbet.vip/a b")
        #expect(tokens == ["kazanc", "tl", "https", "ornekbet", "vip", "d:ornekbet.vip", "<link>", "<num>"])
    }

    @Test func emptyClassifierNeverSaysJunk() {
        #expect(!SpamClassifier().isJunk("Kazanç seni bekliyor"))
    }

    @Test func scoresByWhatItLearned() {
        let classifier = toyClassifier
        #expect(classifier.isJunk("Büyük kazanç için oyna: ornekbet.vip"))
        #expect(!classifier.isJunk("Yarın toplantı var mı?"))
    }

    @Test func survivesSavingAndReading() throws {
        let classifier = toyClassifier
        let decoded = try JSONDecoder().decode(SpamClassifier.self, from: JSONEncoder().encode(classifier))
        #expect(decoded == classifier)
        #expect(decoded.score("kazanç oyna") == classifier.score("kazanç oyna"))
    }

    @Test func pruningDropsRareTokens() {
        var classifier = toyClassifier
        classifier.learn("tekseferlikkelime", isJunk: true)
        #expect(classifier.junkTokens["tekseferlikkelime"] == 1)
        let pruned = classifier.pruned(minimumCount: 3)
        #expect(pruned.junkTokens["tekseferlikkelime"] == nil)
        #expect(pruned.junkTokens["kazanc"] == 3)
    }

    @Test func addingCombinesCounts() {
        let combined = toyClassifier.adding(toyClassifier)
        #expect(combined.junkMessages == 6)
        #expect(combined.otherTokens["kargonuz"] == 6)
    }

    // MARK: Bundled model

    @Test func bundledModelIsLoaded() {
        #expect(SpamClassifier.bundled.junkMessages > 100)
        #expect(SpamClassifier.bundled.otherMessages > 1000)
    }

    @Test func bundledModelCatchesBettingSpam() {
        #expect(SpamClassifier.bundled.isJunk("Kayıp bonusu ve freespin hediyesi seni bekliyor! Hemen yatır, anlık çekim: https://t2m.io/xyz"))
    }

    /// Promotions isn't Junk, but legitimate messages still shouldn't be moved out of the inbox.
    @Test(arguments: RuleCatalog.legitimateSamples)
    func bundledModelLeavesLegitimateSamplesAlone(sample: String) {
        #expect(!SpamClassifier.bundled.isJunk(sample))
    }

    /// A spammer controls the text and the filter extension has little time per message.
    @Test(.timeLimit(.minutes(1)), arguments: ["a ", "a.1", "kazanc ", "https://a.b/"])
    func longRepetitiveTextIsFast(unit: String) {
        let text = String(repeating: unit, count: 3000 / unit.count)
        let duration = ContinuousClock().measure { _ = SpamClassifier.bundled.score(text) }
        #expect(duration < .milliseconds(200))
    }

    // MARK: Engine

    @Test func engineAsksClassifierOnlyWhenNoRuleMatched() {
        let transaction = Rule(name: "Kargo", pattern: "kargonuz", action: .transaction)
        let engine = FilterEngine(rules: [transaction], classifier: toyClassifier)

        let spam = engine.evaluate(sender: nil, body: "Büyük kazanç için oyna: ornekbet.vip")
        #expect(spam.action == .promotion && spam.isFromClassifier && spam.matchedRule == nil)

        let matched = engine.evaluate(sender: nil, body: "Kargonuz yolda, büyük kazanç için oyna: ornekbet.vip")
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
        let falsePositive = "Bonus puan kazandınız! Detaylar https://ornekmarket.com"
        var settings = ClassifierSettings()
        #expect(settings.classifier.isJunk(falsePositive))
        settings.learn(falsePositive, isJunk: false)
        #expect(!settings.classifier.isJunk(falsePositive))

        let missedSpam = "Yeni platform zorbix ile her gün garantili zorbix getirisi: zorbix.top"
        #expect(!settings.classifier.isJunk(missedSpam))
        settings.learn(missedSpam, isJunk: true)
        #expect(settings.classifier.isJunk(missedSpam))
        #expect(settings.exampleCount == 2)
    }

    @Test func forgettingExamplesGoesBackToTheBundledModel() {
        var settings = ClassifierSettings()
        settings.learn("zorbix zorbix.top", isJunk: true)
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
        settings.isEnabled = true
        settings.learn("zorbix zorbix.top", isJunk: true)
        try store.saveClassifierSettings(settings)
        #expect(store.loadClassifierSettings() == settings)
    }
}
