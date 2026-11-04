import FilterCore
import SwiftUI
import UniformTypeIdentifiers

struct RulesView: View {
    @Environment(RuleListModel.self) private var model

    @State private var editingRule: Rule?
    @State private var searchText = ""
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isConfirmingReset = false

    private var visibleRules: [Rule] {
        let query = TextNormalizer.normalize(searchText)
        guard !query.isEmpty else { return model.rules }
        return model.rules.filter { TextNormalizer.normalize("\($0.name) \($0.summary)").contains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                let rules = visibleRules
                ownRulesSection(rules.filter { $0.displayCategory == nil })
                ForEach(RuleCategory.allCases, id: \.self) { category in
                    categorySection(category, rules: rules.filter { $0.displayCategory == category })
                }
            }
            .overlay {
                if !searchText.isEmpty && visibleRules.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Kural ara")
            .refreshable { await model.updateRules(force: true) }
            .navigationTitle("Kurallar")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Kural ekle", systemImage: "plus") { addRule() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Diğer", systemImage: "ellipsis") {
                        Button("Dışa aktar", systemImage: "square.and.arrow.up") { isExporting = true }
                        Button("İçe aktar (mevcutların yerine)", systemImage: "square.and.arrow.down") { isImporting = true }
                        Button("Varsayılanlara dön", systemImage: "arrow.counterclockwise", role: .destructive) {
                            isConfirmingReset = true
                        }
                    }
                }
            }
            .sheet(item: $editingRule) { rule in
                RuleEditorView(rule: rule) { model.saveEdited($0) }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: RulesDocument(rules: model.rules),
                contentType: .json,
                defaultFilename: String(localized: "spam-kurallari", comment: "File name for exported rules")
            ) { _ in }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result { model.importRules(from: url) }
            }
            .confirmationDialog("Tüm kurallar silinip varsayılanlar yüklensin mi?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
                Button("Varsayılanlara dön", role: .destructive) { model.resetToDefaults() }
            }
        }
    }

    private func addRule() {
        editingRule = Rule(name: "", pattern: "", action: .junk)
    }

    @ViewBuilder
    private func ownRulesSection(_ rules: [Rule]) -> some View {
        if !rules.isEmpty || searchText.isEmpty {
            Section {
                ForEach(rules) { rule in
                    row(for: rule, showsAction: true)
                        .swipeActions {
                            Button("Sil", systemImage: "trash", role: .destructive) { model.delete(rule) }
                        }
                }
                if searchText.isEmpty {
                    Button("Kural ekle", systemImage: "plus.circle.fill", action: addRule)
                }
            } header: {
                Label("Kendi kuralların", systemImage: "person")
            } footer: {
                if rules.isEmpty {
                    Text("Kaçan bir spam mesajdan kural oluşturmak için Kontrol et sekmesine yapıştır.")
                }
            }
        }
    }

    @ViewBuilder
    private func categorySection(_ category: RuleCategory, rules: [Rule]) -> some View {
        if !rules.isEmpty {
            Section {
                // Built-in rules come back with the next app update, so they can only be turned off, not deleted.
                ForEach(rules) { rule in
                    row(for: rule, showsAction: category == .sorting || rule.action != .junk)
                }
            } header: {
                HStack {
                    Label(category.title, systemImage: category.systemImage)
                    Spacer()
                    Text("\(rules.filter(\.isEnabled).count)/\(rules.count) açık")
                        .monospacedDigit()
                }
            } footer: {
                if let footer = category.footer { Text(footer) }
            }
        }
    }

    private func row(for rule: Rule, showsAction: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                editingRule = rule
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(rule.name)
                        if rule.isCustomized {
                            Text("Düzenlendi")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary, in: .capsule)
                        }
                    }
                    Text(rule.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if showsAction {
                        Label(rule.action.outcome, systemImage: rule.action.systemImage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(rule.action.tint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle(rule.name, isOn: Binding(
                get: { rule.isEnabled },
                set: { model.setEnabled($0, for: rule) }
            ))
            .labelsHidden()
        }
        .padding(.vertical, 2)
        .opacity(rule.isEnabled ? 1 : 0.55)
    }
}

/// Lets `fileExporter` save the rules as a JSON file.
struct RulesDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var rules: [Rule]

    init(rules: [Rule]) {
        self.rules = rules
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        rules = try RuleStore.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try RuleStore.encode(rules))
    }
}
