import FilterCore
import SwiftUI

/// Start screen: how many rules are on, shortcuts to the other tabs and how filtering works.
/// iOS doesn't tell apps whether their filter is selected in Settings, so this can't show that.
struct HomeView: View {
    @Environment(RuleListModel.self) private var model
    @Binding var selectedTab: AppTab
    let showOnboarding: () -> Void

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

                Section {
                    shortcut("Mesaj kontrol et", systemImage: "text.magnifyingglass", tint: .accentColor) {
                        selectedTab = .check
                    }
                    shortcut("Kuralları yönet", systemImage: "list.bullet.rectangle", tint: .indigo) {
                        selectedTab = .rules
                    }
                    shortcut("Kurulum rehberi", systemImage: "questionmark", tint: .gray, action: showOnboarding)
                }

                Section("Açık kurallar") {
                    ForEach(FilterAction.allCases, id: \.self) { action in
                        LabeledContent {
                            Text("\(enabledCount(for: action))")
                                .monospacedDigit()
                        } label: {
                            Label {
                                Text(action.title)
                            } icon: {
                                Image(systemName: action.systemImage)
                                    .foregroundStyle(action.tint)
                            }
                        }
                    }
                }

                rulesUpdateSection

                Section("Nasıl çalışır") {
                    info("Filtrelenen mesajlar nereye gider", systemImage: "tray.full") {
                        Text("Filtrelenen mesajlar silinmez. Mesajlar uygulamasında sol üstteki Filtreler menüsünden Gereksiz, Promosyonlar ve İşlemler klasörlerinde görebilirsin. Bu mesajlar için bildirim gelmez.")
                        Text("Promosyonlar veya İşlemler klasörü sende görünmüyorsa, ilgili kuralları açıp \"Mesaj nereye gitsin\" ayarını Gereksiz yap.")
                    }
                    info("Hangi mesajlar filtrelenir", systemImage: "person.crop.circle.badge.questionmark") {
                        Text("iOS sadece tanımadığın göndericilerden gelen SMS/MMS mesajlarını filtreye gönderir. Rehberindeki kişiler, daha önce cevap yazdığın numaralar ve iMessage'lar filtrelenmez.")
                        Text("Bir numarayı rehberden silmek onu filtreye sokmaz: o numaraya daha önce cevap yazdıysan iOS onu tanıdık saymaya devam eder.")
                    }
                    info("Gizlilik", systemImage: "lock") {
                        Text("Filtre tamamen iPhone'unda çalışır. Mesajların hiçbir sunucuya gönderilmez.")
                        Text("Uygulama internete sadece güncel kural listesini GitHub'dan indirmek için bağlanır.")
                    }
                }
            }
            .navigationTitle("Koruma")
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(Color.accentColor.gradient, in: .circle)
                .accessibilityHidden(true)
            Text("\(model.rules.filter(\.isEnabled).count) kural açık")
                .font(.title2.bold())
            Text("Rehberinde olmayan göndericilerden gelen SMS'ler bu kurallarla, cihazında kontrol edilir.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Filtre, Ayarlar'da Spam Shield seçili değilse çalışmaz.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
            Text("Yeni kurallar GitHub'daki açık listeden otomatik indirilir. Değiştirdiğin kurallar korunur.")
        }
    }

    private func enabledCount(for action: FilterAction) -> Int {
        model.rules.filter { $0.isEnabled && $0.action == action }.count
    }

    private func shortcut(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    SettingsIcon(systemImage: systemImage, tint: tint)
                }
                Spacer()
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .tint(.primary)
    }

    private func info(_ title: String, systemImage: String, @ViewBuilder content: () -> some View) -> some View {
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

/// White symbol on a colored rounded square, like the rows in the Settings app.
struct SettingsIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 29, height: 29)
            .background(tint.gradient, in: .rect(cornerRadius: 7))
    }
}
