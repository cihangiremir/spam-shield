import Foundation
import Testing
@testable import FilterCore

struct RuleSuggesterTests {
    private let bettingSpam = """
    ACIL AKOM UYARDI 190KG YAGMUR DUSUCEK B001
    180.000 TL TOPLAM DENEME HEDIYE
    YATIRIM SARTSIZ ANLIK CEKIM
    https://kisalt.art/ B052
    """

    // MARK: Link domains

    @Test func findsLinkDomainInReportedSpam() {
        #expect(RuleSuggester.linkDomains(in: bettingSpam) == ["kisalt.art"])
    }

    @Test(arguments: [
        ("Giriş: https://a.b.ornek.com/x", ["ornek.com"]),
        ("Detay: www.ornek.com.tr", ["ornek.com.tr"]),
        ("Ödeme: gib.gov.tr-islemw4.store", ["tr-islemw4.store"]),
        ("Bilgi: ornek.xyz ve https://ORNEK.xyz/a", ["ornek.xyz"]),
        ("İki link: http://bir.site/a ve iki.online", ["bir.site", "iki.online"]),
        ("Detay: kargo-takip.site.", ["kargo-takip.site"]),
    ])
    func extractsRegistrableDomains(text: String, expected: [String]) {
        #expect(RuleSuggester.linkDomains(in: text) == expected)
    }

    @Test(arguments: [
        "180.000 TL toplam, saat 10.30'da",
        "Teslim edildi.Teşekkür ederiz",
        "Sorular için info@firma.com adresine yazın",
        "Normal bir mesaj",
    ])
    func ignoresTextThatIsNotALink(text: String) {
        #expect(RuleSuggester.linkDomains(in: text).isEmpty)
    }

    /// A spammer controls the text; a backtracking regex used to take minutes on 100 characters of this.
    @Test(.timeLimit(.minutes(1)), arguments: ["a.1", "a-1.", "a.", "a-"])
    func longRepetitiveTextIsFast(unit: String) {
        let text = String(repeating: unit, count: 3000 / unit.count)
        let duration = ContinuousClock().measure { _ = RuleSuggester.linkDomains(in: text) }
        #expect(duration < .seconds(1))
    }

    @Test func domainRuleBlocksTheMessageAndOtherSubdomains() {
        let rule = RuleSuggester.domainRule("kisalt.art")
        let engine = FilterEngine(rules: [rule])
        #expect(engine.evaluate(sender: nil, body: bettingSpam).action == .junk)
        #expect(engine.evaluate(sender: nil, body: "Yeni link: http://x.kisalt.art/abc").action == .junk)
    }

    @Test func domainRuleDoesNotMatchLongerDomains() {
        let engine = FilterEngine(rules: [RuleSuggester.domainRule("hepsiburada.co")])
        #expect(engine.evaluate(sender: nil, body: "Kampanya: hepsiburada.co/x").action == .junk)
        #expect(engine.evaluate(sender: nil, body: "Siparişiniz: https://hepsiburada.com/siparis").action == .allow)
        #expect(engine.evaluate(sender: nil, body: "Detay: www.hepsiburada.co.uk").action == .allow)
        #expect(engine.evaluate(sender: nil, body: "Detay: xhepsiburada.co").action == .allow)
    }

    // MARK: Sender and phrase

    @Test func senderRuleBlocksThatSender() throws {
        let rule = try #require(RuleSuggester.senderRule(" SDNMAKİNA "))
        let engine = FilterEngine(rules: [rule])
        #expect(engine.evaluate(sender: "SDNMAKINA", body: "merhaba").action == .junk)
        #expect(engine.evaluate(sender: "BASKAFIRMA", body: "merhaba").action == .allow)
    }

    @Test func emptySenderOrPhraseGivesNoRule() {
        #expect(RuleSuggester.senderRule("  ") == nil)
        #expect(RuleSuggester.phraseRule(" \n ") == nil)
    }

    @Test func phraseRuleMatchesRegardlessOfCaseAndTurkishLetters() throws {
        let rule = try #require(RuleSuggester.phraseRule("Deneme Hediye"))
        #expect(FilterEngine(rules: [rule]).evaluate(sender: nil, body: "500 TL deneme hediyesi").action == .junk)
    }

    @Test func checksWhetherPhraseIsInMessage() {
        #expect(RuleSuggester.message(bettingSpam, contains: "yatırım şartsız"))
        #expect(!RuleSuggester.message(bettingSpam, contains: "kredi"))
        #expect(!RuleSuggester.message(bettingSpam, contains: "  "))
    }

    // MARK: Words

    @Test func wordsSkipLinksNumbersAndDuplicates() {
        let words = RuleSuggester.words(in: "DENEME hediye deneme 180.000 TL, https://kisalt.art/ ok!")
        #expect(words == ["DENEME", "hediye"])
    }
}
