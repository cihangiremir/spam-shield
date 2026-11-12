import FilterCore
import SwiftUI

struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var rule: Rule
    /// Regex and match type are tucked away. The user's own regex rules start with them open,
    /// because the pattern is the rule; built-in ones start closed and show their explanation instead.
    @State private var isShowingAdvanced: Bool
    private let onSave: (Rule) -> Void

    init(rule: Rule, onSave: @escaping (Rule) -> Void) {
        _rule = State(initialValue: rule)
        _isShowingAdvanced = State(initialValue: rule.matchType == .regex && rule.builtInID == nil)
        self.onSave = onSave
    }

    private var isRegex: Bool { rule.matchType == .regex }

    private var canSave: Bool {
        !rule.name.trimmingCharacters(in: .whitespaces).isEmpty && rule.validationError == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Kural adı", text: $rule.name)
                    Toggle("Etkin", isOn: $rule.isEnabled)
                } footer: {
                    if rule.builtInID != nil {
                        Text("Hazır kural silinemez, kapatılabilir. Düzenlersen güncellemeler bu kuralı değiştirmez.")
                    }
                }

                if let details = rule.details {
                    Section("Ne yakalar") {
                        Text(details)
                    }
                }

                Section {
                    if isRegex {
                        Label("Bu kural gelişmiş bir desen kullanıyor. Gelişmiş'ten görebilirsin.", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        targetPicker
                        patternField
                    }
                } header: {
                    Text("Ne zaman")
                } footer: {
                    if !isRegex { patternFooter }
                }

                Section("Mesaj nereye gitsin") {
                    Picker("Mesaj nereye gitsin", selection: $rule.action) {
                        ForEach(FilterAction.allCases, id: \.self) { action in
                            Label {
                                Text(action.title)
                            } icon: {
                                Image(systemName: action.systemImage).foregroundStyle(action.tint)
                            }
                            .tag(action)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    DisclosureGroup("Gelişmiş", isExpanded: $isShowingAdvanced) {
                        Picker("Eşleşme", selection: $rule.matchType) {
                            ForEach(MatchType.allCases, id: \.self) { Text($0.title) }
                        }
                        if isRegex {
                            targetPicker
                            patternField
                        }
                    }
                } footer: {
                    if isShowingAdvanced && isRegex {
                        patternFooter
                    } else {
                        Text("Birden fazla kural eşleşirse öncelik: İzin ver › Gereksiz › İşlemler › Promosyonlar.")
                    }
                }
            }
            .navigationTitle(rule.name.isEmpty ? String(localized: "Yeni kural") : rule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        onSave(rule)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var targetPicker: some View {
        Picker("Nereye bakılsın", selection: $rule.target) {
            ForEach(RuleTarget.allCases, id: \.self) { Text($0.title) }
        }
        .pickerStyle(.segmented)
    }

    private var patternField: some View {
        TextField(placeholder, text: $rule.pattern, axis: .vertical)
            .font(isRegex ? .body.monospaced() : .body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private var placeholder: String {
        switch (rule.target, isRegex) {
        case (_, true): return String(localized: "Regex deseni")
        case (.sender, false): return String(localized: "Ör. +90850 veya FIRMAADI")
        case (.body, false): return String(localized: "Ör. deneme bonusu")
        }
    }

    @ViewBuilder
    private var patternFooter: some View {
        if !rule.pattern.isEmpty, let error = rule.validationError {
            Text(error).foregroundStyle(.red)
        } else if isRegex {
            Text("Regex küçük harfli ve Türkçe karaktersiz metne uygulanır (\"kazandınız\" → \"kazandiniz\"). Deseni de öyle yaz.")
        } else {
            Text("Büyük/küçük harf, Türkçe karakterler ve fazla boşluklar dikkate alınmaz.")
        }
    }
}
