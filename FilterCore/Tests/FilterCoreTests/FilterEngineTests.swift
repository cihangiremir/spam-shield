import Foundation
import Testing
@testable import FilterCore

struct TextNormalizerTests {
    @Test func foldsTurkishCharactersAndCase() {
        #expect(TextNormalizer.normalize("TEBRİKLER Kazandınız ŞIK ÖDÜL") == "tebrikler kazandiniz sik odul")
    }

    @Test func removesInvisibleCharactersAndCollapsesWhitespace() {
        #expect(TextNormalizer.normalize("ba\u{200B}his   \n  sitesi") == "bahis sitesi")
    }

    @Test func foldsDecomposedCharacters() {
        #expect(TextNormalizer.normalize("s\u{0327}ans") == "sans")
    }

    @Test(arguments: [
        ("B.A.H.İ.S sitesi", "bahis sitesi"),
        ("c a s i n o bonusu", "casino bonusu"),
        ("K-a-z-a-n-ç fırsatı", "kazanc firsati"),
        ("b_a_h_i_s ve c*a*s*i*n*o", "bahis ve casino"),
        ("b\u{0430}his", "bahis"), // Cyrillic "а"
    ])
    func undoesLetterObfuscation(text: String, expected: String) {
        #expect(TextNormalizer.normalize(text) == expected)
    }

    @Test(arguments: [
        "T.C. Ziraat Bankası A.Ş.",
        "Plaka: 34 ABC 123",
        "Saat 10.30'da, 3. kat",
        "o bir e-posta",
    ])
    func leavesAbbreviationsAndShortLettersAlone(text: String) {
        // Joining spaced-out letters drops characters; folding and lowercasing don't.
        #expect(TextNormalizer.normalize(text).count == text.count)
    }

    @Test func normalizesSenderNumbers() {
        #expect(TextNormalizer.normalizeSender("+90 (850) 123-45-67") == "+908501234567")
    }

    @Test(arguments: ["0555 111 22 33", "+90 555 111 22 33", "905551112233"])
    func writesTurkishNumbersTheSameWay(sender: String) {
        #expect(TextNormalizer.normalizeSender(sender) == "+905551112233")
    }

    @Test(arguments: ["3404", "0044 20 1234 5678", "TRENDYOL"])
    func leavesShortCodesForeignNumbersAndNamesAlone(sender: String) {
        #expect(TextNormalizer.normalizeSender(sender) == TextNormalizer.normalize(sender).filter { $0 != " " })
    }

    @Test func regexPatternKeepsEscapes() {
        #expect(TextNormalizer.foldRegexPattern(#"\D\S İŞ"#) == #"\D\S is"#)
    }
}

struct FilterEngineTests {
    private func evaluate(_ body: String, sender: String? = "+905551112233", rules: [Rule] = DefaultRules.all) -> FilterDecision {
        FilterEngine(rules: rules).evaluate(sender: sender, body: body)
    }

    // MARK: Default rules

    @Test(arguments: [
        "Deneme Bonusu 500 TL! Hemen üye ol: betxyz123.com",
        "%100 bonus fırsatı canlı bahis sitemizde",
        "Kredi notunuz ne olursa olsun anında kredi! Bilgi için arayın",
        "Tüm borçlarınızı kapatıyoruz, icralı kişilere kredi",
        "TEBRİKLER! Çekilişimizde iPhone kazandınız",
        "Size özel fırsat: bit.ly/3abcde",
        "PTT: Kargonuz teslim edilemedi, adres bilgilerinizi güncelleyin https://ptt-kargo.xyz",
        "HGS geçiş cezanız bulunmaktadır, ödemek için www.hgs-odeme.top",
        "500 TL deneme hediyesi hesabınızda",
        "Yatırım şartsız anlık çekim fırsatı",
        "Çevrimsiz kazanç burada",
        "Sana özel: https://kisalt.art/abc",
        "Detaylar: https://ornek.art",
        "B.A.H.İ.S sitemize üye ol, 500 TL senin",
        "C A S İ N O oyunlarında büyük ödül",
        "bаhis fırsatı", // Cyrillic "а"
        "VIP grubumuza katıl: https://t.me/kazanc_vip",
        "Kanalımız: t.me/bonusgrubu",
    ])
    func defaultRulesSendSpamToJunk(body: String) {
        #expect(evaluate(body).action == .junk)
    }

    @Test(arguments: [
        ("e-Devlet: Adınıza destek ödemesi tanımlandı, başvuru: https://turkiye.gov.tr-destek.com/basvur", "Resmi kurum taklidi linkler"),
        ("Destek ödemenizi almak için edevlet-sorgu.net adresine girin", "Resmi kurum taklidi linkler"),
        ("GİB: vergi iadenizi almak için edevlet-sorgu.net adresine girin", "Sahte kargo, ceza ve iade linkleri"),
        ("Puanlarınızın süresi doluyor, hemen kullanın: puan-merkezi.online", "Şüpheli alan adı uzantıları"),
        ("Hesabınız kısıtlandı, açmak için: https://banka-giris.netlify.app", "Ücretsiz hosting ve IP linkleri"),
        ("Paketiniz bekliyor: http://198.51.100.7/takip", "Ücretsiz hosting ve IP linkleri"),
        ("Faturanız iade edilecek: turkcell-odeme.com", "Marka taklidi alan adları"),
        ("Hesabınız bloke edildi. Kart bilgilerinizi doğrulamak için tıklayın: bankam.com/kart", "Link ile bilgi isteyen mesajlar"),
        ("Anne ben Can, telefonum bozuldu. Acil 2.000 TL lazım, şu hesaba gönderir misin?", "\"Anne/baba ben\" dolandırıcılığı"),
        ("Merhaba, yanlışlıkla hesabınıza 3.000 TL gönderdim, lütfen iade edin.", "Yanlış havale dolandırıcılığı"),
        ("Kartınızla 9.800 TL işlem yapıldı. İşlem size ait değilse hemen 0532 111 22 33'ü arayın.", "Cep numarası aratan banka uyarısı"),
        ("Evden çalışarak günde 1.500 TL kazanın, deneyim gerekmez!", "Sahte iş ilanı"),
        ("Bankanızın güvenlik biriminden arıyoruz. İşlemi durdurmak için telefonunuza gelen kodu bize iletir misiniz?", "Kod paylaşma tuzağı"),
        ("Hediyenizi tanımlamak için SMS ile gelen doğrulama kodunu buraya yazın.", "Kod paylaşma tuzağı"),
    ])
    func phishingRulesSendScamsToJunk(body: String, ruleName: String) {
        let decision = evaluate(body)
        #expect(decision.action == .junk)
        #expect(decision.matchedRule?.name == ruleName)
    }

    /// Real messages that share words or link shapes with scams must not end up in Junk.
    /// The same list guards rule updates downloaded from GitHub (see `RuleCatalog`).
    @Test(arguments: RuleCatalog.legitimateSamples)
    func legitimateLookalikesAreNotJunk(body: String) {
        #expect(evaluate(body).action != .junk)
    }

    /// Betting spam sent from a hijacked company sender ID, with İYS codes so it looks like a normal ad.
    @Test func bettingSpamWithIysCodesGoesToJunk() {
        let body = """
        ACIL AKOM UYARDI 190KG YAGMUR DUSUCEK B001





        180.000 TL TOPLAM DENEME HEDIYE
        YATIRIM SARTSIZ ANLIK CEKIM
        1 SANIYE ODEME HIZI


        https://kisalt.art/ B052
        """
        let decision = evaluate(body, sender: "SDNMAKİNA")
        #expect(decision.action == .junk)
        #expect(decision.matchedRule?.name == "Bahis ve casino")
    }

    @Test(arguments: [
        "Sepette %30 indirim! SMS almak istemiyorsanız RET yazıp 3404'e gönderin. B002",
        "Yeni sezon ürünleri mağazalarda. Mersis: 0123456789012345",
    ])
    func defaultRulesSendCommercialSmsToPromotions(body: String) {
        #expect(evaluate(body).action == .promotion)
    }

    @Test(arguments: [
        "Doğrulama kodunuz: 482913. Kimseyle paylaşmayın.",
        "Your verification code is 123456",
        "Kargonuz dağıtıma çıktı, gün içinde teslim edilecek.",
        "1234 ile biten kartınızla 250,00 TL harcama yapılmıştır.",
    ])
    func defaultRulesSendInfoMessagesToTransactions(body: String) {
        #expect(evaluate(body).action == .transaction)
    }

    @Test(arguments: [
        "Akşam yemeğe geliyor musun?",
        "Toplantı yarın saat 10'da",
        "Garanti BBVA Bonus kartınızın ekstresi hazır.",
    ])
    func normalMessagesAreAllowed(body: String) {
        let decision = evaluate(body)
        #expect(decision.action == .allow)
        #expect(decision.matchedRule == nil)
    }

    @Test func disabledDefaultRulesDoNotMatch() {
        #expect(evaluate("Detaylar: https://example.com/haber").action == .allow)
        #expect(evaluate("Merhaba", sender: "+90 850 222 00 00").action == .allow)
    }

    @Test func everyDefaultRuleIsValid() {
        for rule in DefaultRules.all {
            #expect(rule.validationError == nil, "\(rule.name)")
        }
    }

    // MARK: Precedence

    @Test func junkBeatsTransaction() {
        let decision = evaluate("Deneme bonusu kodunuz: 1234")
        #expect(decision.action == .junk)
        #expect(decision.matchedRule?.name == "Bahis ve casino")
    }

    @Test func allowBeatsJunk() {
        let allowSender = Rule(name: "Bankam", target: .sender, matchType: .contains, pattern: "BANKAM", action: .allow)
        let decision = evaluate("Tebrikler, çekilişi kazandınız!", sender: "BANKAM", rules: DefaultRules.all + [allowSender])
        #expect(decision.action == .allow)
        #expect(decision.matchedRule?.id == allowSender.id)
    }

    @Test func earlierRuleWinsTie() {
        let first = Rule(name: "first", pattern: "kampanya", action: .junk)
        let second = Rule(name: "second", pattern: "kampanya", action: .junk)
        #expect(evaluate("Kampanya", rules: [first, second]).matchedRule?.id == first.id)
    }

    // MARK: Match types

    @Test func containsIgnoresCaseAndTurkishCharacters() {
        let rule = Rule(name: "kelime", pattern: "Şans Oyunu", action: .junk)
        #expect(evaluate("SANS OYUNU burada", rules: [rule]).action == .junk)
    }

    @Test func senderPrefixMatchesIgnoringFormatting() {
        let rule = Rule(name: "prefix", target: .sender, matchType: .prefix, pattern: "+90 850", action: .junk)
        #expect(evaluate("Merhaba", sender: "+908502220000", rules: [rule]).action == .junk)
        #expect(evaluate("Merhaba", sender: "+905552220000", rules: [rule]).action == .allow)
    }

    @Test func senderRuleMatchesNumberWrittenDifferently() {
        let rule = Rule(name: "numara", target: .sender, matchType: .prefix, pattern: "0555 111 22 33", action: .junk)
        #expect(evaluate("Merhaba", sender: "+905551112233", rules: [rule]).action == .junk)
    }

    @Test func senderRuleDoesNotMatchMissingSender() {
        let rule = Rule(name: "prefix", target: .sender, matchType: .prefix, pattern: "+90", action: .junk)
        #expect(evaluate("Merhaba", sender: nil, rules: [rule]).action == .allow)
    }

    @Test func invalidRegexIsReportedAndSkipped() {
        let rule = Rule(name: "bozuk", matchType: .regex, pattern: "(abc", action: .junk)
        #expect(rule.validationError != nil)
        #expect(evaluate("abc", rules: [rule]).action == .allow)
    }

    @Test func emptyPatternIsInvalid() {
        #expect(Rule(name: "boş", pattern: "  ", action: .junk).validationError != nil)
    }
}

struct RuleStoreTests {
    @Test func savesAndLoadsRules() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RuleStore(fileURL: url)
        let rules = DefaultRules.all + [Rule(name: "test", pattern: "abc", action: .junk)]

        try store.save(rules)

        #expect(store.load() == rules)
    }

    @Test func decodesRulesWithoutBuiltInFields() throws {
        let json = #"[{"id":"7C8D3E5A-0000-4000-8000-000000000001","name":"x","isEnabled":true,"target":"body","matchType":"contains","pattern":"abc","action":"junk"}]"#
        let rule = try #require(try RuleStore.decode(Data(json.utf8)).first)
        #expect(rule.builtInID == nil)
        #expect(rule.isCustomized == false)
    }

    @Test func fallsBackToDefaultsWhenFileIsMissingOrBroken() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RuleStore(fileURL: url)

        #expect(store.load().map(\.name) == DefaultRules.all.map(\.name))

        try Data("not json".utf8).write(to: url)
        #expect(store.load().map(\.name) == DefaultRules.all.map(\.name))
    }

    @Test func loadForEditingThrowsOnlyWhenFileIsBroken() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rules-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = RuleStore(fileURL: url)

        #expect(try store.loadForEditing().map(\.name) == DefaultRules.all.map(\.name))

        try Data("not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try store.loadForEditing() }
    }
}

struct DefaultRulesMergeTests {
    private var latestBetting: Rule { DefaultRules.all.first { $0.builtInID == "betting" }! }

    @Test func builtInIDsAreUnique() {
        let ids = DefaultRules.all.compactMap(\.builtInID)
        #expect(ids.count == DefaultRules.all.count)
        #expect(Set(ids).count == ids.count)
    }

    @Test func updatesUneditedBuiltInRuleAndKeepsItsState() {
        let saved = Rule(name: "Eski ad", isEnabled: false, pattern: "eski", action: .junk, builtInID: "betting")

        let merged = DefaultRules.merged(with: [saved])
        let betting = merged.filter { $0.builtInID == "betting" }

        #expect(betting.count == 1)
        #expect(betting[0].pattern == latestBetting.pattern)
        #expect(betting[0].name == latestBetting.name)
        #expect(betting[0].id == saved.id)
        #expect(betting[0].isEnabled == false)
    }

    @Test func keepsEditedBuiltInRuleWithoutDuplicatingIt() {
        let edited = Rule(name: "Benim bahis kuralım", pattern: "benim", action: .junk, builtInID: "betting", isCustomized: true)

        let merged = DefaultRules.merged(with: [edited])

        var expected = edited
        expected.category = latestBetting.category
        expected.details = latestBetting.details
        #expect(merged.filter { $0.builtInID == "betting" } == [expected])
    }

    @Test func addsNewBuiltInRulesAndKeepsUserRules() {
        let userRule = Rule(name: "kendi", pattern: "abc", action: .junk)

        let merged = DefaultRules.merged(with: [userRule])

        #expect(merged.first == userRule)
        #expect(merged.count == DefaultRules.all.count + 1)
    }

    @Test func dropsRetiredBuiltInRuleUnlessEdited() {
        let retired = Rule(name: "eski", pattern: "a", action: .junk, builtInID: "retired")
        let retiredEdited = Rule(name: "eski2", pattern: "b", action: .junk, builtInID: "retired-2", isCustomized: true)

        let merged = DefaultRules.merged(with: [retired, retiredEdited])

        #expect(!merged.contains { $0.id == retired.id })
        #expect(merged.contains { $0.id == retiredEdited.id })
    }
}
