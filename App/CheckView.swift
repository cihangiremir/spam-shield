import FilterCore
import SwiftUI

/// The Check tab: paste a message, see where it goes and add rules from it.
struct CheckView: View {
    @State private var sender = ""
    @State private var messageText = ""

    private var hasInput: Bool { !messageText.isEmpty || !sender.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            CheckForm(sender: $sender, messageText: $messageText)
                .navigationTitle("Kontrol et")
                .toolbar {
                    if hasInput {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Temizle") {
                                sender = ""
                                messageText = ""
                            }
                        }
                    }
                }
        }
    }
}

/// Runs the current rules on a message the same way the filter extension does. When spam got through,
/// it offers rules built from the message (link domain, sender, phrase) and adds the ones the user picks.
/// iOS doesn't share Messages' own "Report Junk" with apps, so this is the on-device way to learn from it.
/// Used by the Check tab and the share extension.
struct CheckForm: View {
    @Environment(RuleListModel.self) private var model

    @Binding var sender: String
    @Binding var messageText: String

    @State private var selectedDomains: Set<String> = []
    @State private var blocksSender = false
    @State private var phrase = ""
    @State private var resultMessage: String?
    /// Set after teaching the classifier, so the same message isn't counted twice.
    @State private var taughtMessage: String?

    private var hasSender: Bool { !sender.trimmingCharacters(in: .whitespaces).isEmpty }

    private var domains: [String] { RuleSuggester.linkDomains(in: messageText) }

    private var phraseIsInMessage: Bool { RuleSuggester.message(messageText, contains: phrase) }

    private var selectedRules: [Rule] {
        var rules = domains.filter(selectedDomains.contains).map(RuleSuggester.domainRule)
        if blocksSender, let rule = RuleSuggester.senderRule(sender) { rules.append(rule) }
        if phraseIsInMessage, let rule = RuleSuggester.phraseRule(phrase) { rules.append(rule) }
        return rules
    }

    var body: some View {
        Form {
            messageSection

            if !messageText.isEmpty || hasSender {
                resultSection
            }

            if !messageText.isEmpty {
                if !domains.isEmpty { domainSection }
                if hasSender { senderSection }
                phraseSection
                addSection
                classifierSection
            } else {
                Section {
                    Label("Rehberindeki kişilerden, daha önce cevap yazdığın numaralardan gelen mesajlar ve iMessage'lar iOS tarafından filtreye hiç gönderilmez. Buradaki sonuç bu mesajlar için geçerli olmaz.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // `initial` so a message that is already there when the form opens (the share extension) gets its links selected.
        .onChange(of: messageText, initial: true) { oldText, newText in
            // Links are the most precise signal, so new ones start selected; sender and phrase are opt-in.
            // Domains that were already there keep the user's choice while they edit the text.
            let oldDomains = oldText == newText ? [] : Set(RuleSuggester.linkDomains(in: oldText))
            selectedDomains = Set(domains.filter { !oldDomains.contains($0) || selectedDomains.contains($0) })
            blocksSender = false
            phrase = ""
            resultMessage = nil
            taughtMessage = nil
        }
    }

    private var messageSection: some View {
        Section {
            TextField("Gönderici (ör. SDNMAKINA)", text: $sender)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            TextField("Mesaj metni", text: $messageText, axis: .vertical)
                .lineLimit(4...10)
            PasteButton(payloadType: String.self) { strings in
                messageText = strings.first ?? ""
            }
        } footer: {
            Text("Mesajlar'da mesaja uzun bas › Kopyala, sonra buraya yapıştır. Göndericiyi elle yazabilirsin.")
        }
    }

    private var resultSection: some View {
        let decision = model.engine.evaluate(sender: sender, body: messageText)
        return Section("Sonuç") {
            HStack(spacing: 14) {
                Image(systemName: decision.action.systemImage)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(decision.action.tint.gradient, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(decision.action.outcome)
                        .font(.headline)
                    Text(decision.matchedRule.map { String(localized: "Eşleşen kural: \($0.name)") }
                         ?? (decision.isFromClassifier
                             ? String(localized: "Hiçbir kural eşleşmedi, öğrenen filtre spam'e benzetti.")
                             : String(localized: "Hiçbir kural eşleşmedi.")))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var domainSection: some View {
        Section {
            ForEach(domains, id: \.self) { domain in
                Toggle(isOn: Binding(
                    get: { selectedDomains.contains(domain) },
                    set: { isOn in
                        if isOn { selectedDomains.insert(domain) } else { selectedDomains.remove(domain) }
                    }
                )) {
                    Text(domain).font(.body.monospaced())
                }
            }
        } header: {
            Text("Link adreslerini engelle")
        } footer: {
            Text("Bu adresi içeren tüm mesajlar Gereksiz'e gider. Bilinen bir siteyse (ör. instagram.com) işaretleme.")
        }
    }

    private var senderSection: some View {
        Section {
            Toggle("\(sender) göndericisini engelle", isOn: $blocksSender)
        } header: {
            Text("Göndericiyi engelle")
        } footer: {
            Text("Bahisçiler gerçek firmaların gönderici adlarını kullanabiliyor. Engellersen o firmanın gerçek mesajları da gelmez.")
        }
    }

    private var phraseSection: some View {
        Section {
            TextField("Engellenecek ifade", text: $phrase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(RuleSuggester.words(in: messageText), id: \.self) { word in
                        Button(word) {
                            phrase = phrase.isEmpty ? word : "\(phrase) \(word)"
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .font(.caption)
                    }
                }
            }
        } header: {
            Text("İfade engelle")
        } footer: {
            if !phrase.isEmpty && !phraseIsInMessage {
                Text("Bu ifade mesajda geçmiyor.").foregroundStyle(.red)
            } else {
                Text("Kelimelere dokunarak ifade oluştur. Kısa ve yaygın ifadeler normal mesajları da engelleyebilir; \"deneme hediye\" gibi spame özgü ifadeler seç.")
            }
        }
    }

    private var addSection: some View {
        Section {
            Button {
                let added = model.addReportedRules(selectedRules)
                resultMessage = added == 0
                    ? String(localized: "Bu kurallar zaten listende var.")
                    : String(localized: "\(added) kural eklendi. Benzer mesajlar artık Gereksiz'e gidecek.")
            } label: {
                Text(selectedRules.isEmpty
                     ? String(localized: "Engellemek için yukarıdan seç")
                     : String(localized: "Seçili kuralları ekle (\(selectedRules.count))"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedRules.isEmpty)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        } footer: {
            if let resultMessage { Text(resultMessage) }
        }
    }

    private var classifierSection: some View {
        let looksLikeSpam = model.classifier.isJunk(messageText)
        return Section {
            Label(looksLikeSpam
                  ? String(localized: "Öğrenen filtre bu mesajı spam'e benzetiyor.")
                  : String(localized: "Öğrenen filtre bu mesajı normal buluyor."),
                  systemImage: looksLikeSpam ? "exclamationmark.bubble" : "checkmark.bubble")
            HStack {
                Button("Spam") { teach(isJunk: true) }
                    .frame(maxWidth: .infinity)
                Button("Spam değil") { teach(isJunk: false) }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(taughtMessage != nil)
        } header: {
            Text("Öğrenen filtreye öğret")
        } footer: {
            if let taughtMessage {
                Text(taughtMessage)
            } else if model.classifierSettings.isEnabled {
                Text("Hiçbir kuralın yakalamadığı mesajlarda spam'e benzeyenleri Promosyonlar'a taşır. Mesaj saklanmaz, sadece kelimeleri sayılır.")
            } else {
                Text("Öğrenen filtre kapalı. Öğrettiklerin saklanır; Kurallar sekmesinden açınca kullanılır.")
            }
        }
    }

    private func teach(isJunk: Bool) {
        model.teachClassifier(messageText, isJunk: isJunk)
        taughtMessage = isJunk
            ? String(localized: "Spam olarak öğretildi.")
            : String(localized: "Normal mesaj olarak öğretildi.")
    }
}
