import FilterCore
import SwiftUI

/// Start screen: how many rules are on, the rule list version and how filtering works.
/// iOS doesn't tell apps whether their filter is selected in Settings, so this can't show that.
struct HomeView: View {
    @Environment(RuleListModel.self) private var model
    let showOnboarding: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var markHeight = 88.0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    hero
                }
                .listRowBackground(Color.clear)

                if let errorMessage = model.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section("Açık kurallar") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(FilterAction.allCases, id: \.self, content: countTile)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                rulesUpdateSection

                Section("Nasıl çalışır") {
                    info("Filtrelenen mesajlar nereye gider", systemImage: "tray.full") {
                        Text("Filtrelenen mesajlar silinmez, bildirim de gelmez. Mesajlar'da sol üstteki Filtreler menüsünden Gereksiz, Promosyonlar ve İşlemler klasörlerinde görebilirsin.")
                        Text("Promosyonlar veya İşlemler klasörü görünmüyorsa o kuralları Gereksiz'e yönlendir.")
                    }
                    info("Hangi mesajlar filtrelenir", systemImage: "person.crop.circle.badge.questionmark") {
                        Text("Sadece tanımadığın göndericilerden gelen SMS'ler. Rehberindeki kişiler, cevap yazdığın numaralar ve iMessage'lar filtrelenmez.")
                        Text("Cevap yazdığın bir numara rehberden silinse de tanıdık sayılır.")
                    }
                    info("Gizlilik", systemImage: "lock") {
                        Text("Filtre tamamen iPhone'unda çalışır, mesajların hiçbir yere gönderilmez. İnternet sadece kural listesini güncellemek için kullanılır.")
                    }
                }
            }
            .navigationTitle("Koruma")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kurulum rehberi", systemImage: "questionmark.circle", action: showOnboarding)
                }
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(height: markHeight)
                .accessibilityHidden(true)
            Text("\(model.rules.filter(\.isEnabled).count) kural açık")
                .font(.title2.bold())
            Text("Filtrenin çalışması için Ayarlar'da Spam Shield'ı seç.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            MessagesSettingsButton()
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func countTile(_ action: FilterAction) -> some View {
        let count = enabledCount(for: action)
        return VStack(alignment: .leading, spacing: 4) {
            Image(systemName: action.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(action.tint)
            Text(count, format: .number)
                .font(.title.bold())
                .monospacedDigit()
            Text(action.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        // Fills the grid row, so tiles whose symbols differ in height still line up.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title)
        .accessibilityValue(Text(count, format: .number))
    }

    private var rulesUpdateSection: some View {
        Section {
            LabeledContent("Liste sürümü", value: "\(model.catalogVersion)")
            LabeledContent("Son kontrol") {
                if let lastUpdateCheck = model.lastUpdateCheck {
                    Text(lastUpdateCheck, format: .relative(presentation: .named))
                } else {
                    Text("Henüz yapılmadı")
                }
            }
            if let updateError = model.updateError {
                Label(updateError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button {
                Task { await model.updateRules(force: true) }
            } label: {
                HStack {
                    Text("Şimdi güncelle")
                    Spacer()
                    if model.isUpdating { ProgressView() }
                }
            }
            .disabled(model.isUpdating)
        } header: {
            Text("Kural listesi")
        } footer: {
            Text("Yeni kurallar otomatik indirilir. Değiştirdiğin kurallar korunur.")
        }
    }

    private func enabledCount(for action: FilterAction) -> Int {
        model.rules.filter { $0.isEnabled && $0.action == action }.count
    }

    private func info(_ title: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
        let content = content()
        return DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) { content }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
