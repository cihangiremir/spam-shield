import SwiftUI

/// Shown on first launch and from the home screen: what the app does, how to turn the filter on, privacy.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0
    @ScaledMetric(relativeTo: .largeTitle) private var iconHeight = 104.0

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                let isLastPage = page == pageCount - 1
                Button("Geç", action: onFinish)
                    .opacity(isLastPage ? 0 : 1)
                    .disabled(isLastPage)
                    .accessibilityHidden(isLastPage)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            TabView(selection: $page) {
                welcomePage.tag(0)
                setupPage.tag(1)
                privacyPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if page == 1 {
                    MessagesSettingsButton()
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                Button {
                    if page < pageCount - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page < pageCount - 1 ? LocalizedStringKey("Devam") : LocalizedStringKey("Başla"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
    }

    private var welcomePage: some View {
        pageContent(
            icon: Image("BrandMark").resizable().scaledToFit(),
            title: "Spam SMS'lere karşı kalkan",
            text: "Bahis, kredi ve dolandırıcılık mesajlarını Gereksiz'e ayırır. Kodları ve kargo bildirimlerini kendi klasörlerine koyar."
        )
    }

    private var setupPage: some View {
        pageContent(icon: symbol("gearshape.fill"), title: "Filtreyi aç", text: nil) {
            VStack(alignment: .leading, spacing: 14) {
                step(1, "Ayarlar uygulamasını aç.")
                step(2, "Uygulamalar › Mesajlar'a gir (iOS 17'de doğrudan Mesajlar).")
                step(3, "Bilinmeyen ve Spam bölümüne gir.")
                step(4, "SMS Filtreleme altında Spam Shield'ı seç.")
            }
            .padding(20)
            .background(.background.secondary, in: .rect(cornerRadius: 16))
        }
    }

    private var privacyPage: some View {
        pageContent(
            icon: symbol("lock.shield.fill"),
            title: "Mesajların sende kalır",
            text: "Filtre tamamen iPhone'unda çalışır. Hiçbir mesaj bir sunucuya gönderilmez."
        )
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
    }

    private func pageContent(
        icon: some View,
        title: LocalizedStringKey,
        text: LocalizedStringKey?,
        @ViewBuilder extra: () -> some View = { EmptyView() }
    ) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                icon
                    .frame(height: iconHeight)
                    .padding(.top, 40)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                if let text {
                    Text(text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                extra()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 48)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "\(number).circle.fill")
                .foregroundStyle(Color.accentColor)
                .font(.title3)
        }
    }
}

/// Opens Settings › Apps › Messages. Apple has no public link to that page (the public one opens this app's
/// own settings), so this uses the undocumented "App-prefs:" URL and falls back to Settings' own page for
/// this app when iOS refuses it. App Review may reject it; fine for installing from Xcode.
struct MessagesSettingsButton: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button("Mesajlar ayarlarını aç") {
            guard let url = URL(string: "App-prefs:com.apple.MobileSMS") else { return }
            openURL(url) { accepted in
                if !accepted, let fallback = URL(string: UIApplication.openSettingsURLString) { openURL(fallback) }
            }
        }
    }
}
