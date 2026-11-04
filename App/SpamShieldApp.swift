import BackgroundTasks
import SwiftUI

enum AppTab: String {
    case home
    case check
    case rules
}

@main
struct SpamShieldApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = RuleListModel()
    @AppStorage("selectedTab") private var selectedTab = AppTab.home
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            TabView(selection: $selectedTab) {
                HomeView(selectedTab: $selectedTab) { hasCompletedOnboarding = false }
                    .tabItem { Label("Koruma", systemImage: "checkmark.shield") }
                    .tag(AppTab.home)
                CheckView()
                    .tabItem { Label("Kontrol et", systemImage: "text.magnifyingglass") }
                    .tag(AppTab.check)
                RulesView()
                    .tabItem { Label("Kurallar", systemImage: "list.bullet.rectangle") }
                    .tag(AppTab.rules)
            }
            .environment(model)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    model.reload()
                    Task { await model.updateRules() }
                case .background:
                    Self.scheduleRulesRefresh()
                default:
                    break
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { !hasCompletedOnboarding },
                set: { hasCompletedOnboarding = !$0 }
            )) {
                OnboardingView { hasCompletedOnboarding = true }
            }
        }
        // iOS decides when this runs (usually when the phone is charging or used often), so it's a bonus:
        // the app also checks whenever it is opened.
        .backgroundTask(.appRefresh(Self.rulesRefreshTaskID)) { [model] in
            await Self.scheduleRulesRefresh()
            await model.updateRules()
        }
    }

    /// Must be listed in BGTaskSchedulerPermittedIdentifiers (project.yml).
    private static let rulesRefreshTaskID = "com.emirchngr.spamshield.rules-refresh"

    private static func scheduleRulesRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: rulesRefreshTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(RuleListModel.automaticCheckInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
