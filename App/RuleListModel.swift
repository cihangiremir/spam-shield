import FilterCore
import Foundation
import Observation

/// Holds the rule list for the UI and saves every change to the shared App Group,
/// where the filter extension picks it up for the next message.
@MainActor
@Observable
final class RuleListModel {
    private(set) var rules: [Rule] {
        didSet {
            // Coming back to the foreground reloads the same rules; no need to compile them again.
            if rules != oldValue { engine = FilterEngine(rules: rules) }
        }
    }
    /// Built once per rule change, so the Check screen doesn't compile every regex on each keystroke.
    private(set) var engine: FilterEngine
    var errorMessage: String?

    /// Version of the built-in rule list in use (bundled or downloaded from GitHub).
    private(set) var catalogVersion = RuleCatalog.bundled.version
    private(set) var isUpdating = false
    var updateError: String?
    /// Last time the rule list was checked successfully, so opening the app doesn't download it every time.
    private(set) var lastUpdateCheck = UserDefaults.standard.object(forKey: "lastRulesUpdateCheck") as? Date {
        didSet { UserDefaults.standard.set(lastUpdateCheck, forKey: "lastRulesUpdateCheck") }
    }

    private let store: RuleStore?
    /// Set when the saved file can't be read, so the defaults shown instead aren't saved over it.
    /// Resetting or importing clears it, because then the user chose to replace the file.
    private var isSavingBlocked = false

    init(store: RuleStore? = RuleStore.shared()) {
        self.store = store
        rules = DefaultRules.all
        engine = FilterEngine(rules: DefaultRules.all)
        reload()
        // `didSet` doesn't run during init.
        if rules != DefaultRules.all { engine = FilterEngine(rules: rules) }
    }

    /// Reads the saved rules again. The app calls this when it comes to the foreground, because the share
    /// extension may have added rules meanwhile, and saving the old list would drop them.
    func reload() {
        guard let store else {
            errorMessage = String(localized: "App Group bulunamadı. Kurallar kaydedilemez, filtre sadece varsayılan kurallarla çalışır. Xcode'da hedeflerin Signing ayarlarını kontrol et.")
            return
        }
        catalogVersion = store.loadCatalog().version
        do {
            rules = try store.loadForEditing()
            unblockSaving()
        } catch {
            isSavingBlocked = true
            errorMessage = String(localized: "Kayıtlı kurallar okunamadı, filtre varsayılan kurallarla çalışıyor. Kayıtlı dosyanın üzerine yazılmasın diye değişiklikler kaydedilmiyor. Varsayılanlara dönebilir ya da kuralları içe aktarabilirsin.")
        }
    }

    /// Downloads the rule list from GitHub (`RulesUpdateURL` in Info.plist) and uses it if it is newer.
    /// A list that doesn't pass `RuleCatalog`'s checks or junks a legitimate sample is ignored, so a bad
    /// commit can't break filtering. Without `force` (automatic checks), does nothing if the last check was less than 2 days ago and skips
    /// Low Data Mode, so it costs almost no battery or data.
    func updateRules(force: Bool = false) async {
        guard let store, !isUpdating,
              let url = (Bundle.main.object(forInfoDictionaryKey: "RulesUpdateURL") as? String).flatMap(URL.init(string:))
        else { return }
        if !force, let lastUpdateCheck, Date.now.timeIntervalSince(lastUpdateCheck) < Self.automaticCheckInterval { return }

        isUpdating = true
        defer { isUpdating = false }
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            if force {
                request.cachePolicy = .reloadIgnoringLocalCacheData
            } else {
                // Lets URLSession revalidate with GitHub's ETag, so an unchanged list isn't downloaded again.
                request.allowsConstrainedNetworkAccess = false
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            // The real list is a few tens of KB; anything this big isn't it.
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000 else {
                throw URLError(.badServerResponse)
            }
            let catalog = try RuleCatalog(data: data)
            if catalog.version > catalogVersion {
                try catalog.checkNoJunk()
                try store.saveCatalog(data)
                reload()
            }
            lastUpdateCheck = .now
            updateError = nil
        } catch let error as RuleCatalogError {
            updateError = String(localized: "İndirilen liste kullanılmadı, mevcut kurallar çalışmaya devam ediyor. \(error.localizedDescription)")
        } catch {
            updateError = String(localized: "Kural listesi güncellenemedi: \(error.localizedDescription)")
        }
    }

    /// How often the app checks for new rules on its own (on opening and in the background).
    static let automaticCheckInterval: TimeInterval = 2 * 24 * 60 * 60

    func rules(for action: FilterAction) -> [Rule] {
        rules.filter { $0.action == action }
    }

    func upsert(_ rule: Rule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        save()
    }

    /// Saves a rule from the editor. Once a built-in rule is edited, app updates stop replacing it.
    func saveEdited(_ rule: Rule) {
        var rule = rule
        if rule.builtInID != nil, var previous = rules.first(where: { $0.id == rule.id }) {
            previous.isEnabled = rule.isEnabled // Turning a rule on or off isn't an edit.
            if previous != rule { rule.isCustomized = true }
        }
        upsert(rule)
    }

    /// Adds rules from the report screen, skipping ones the list already has. Returns how many were added.
    func addReportedRules(_ newRules: [Rule]) -> Int {
        let fresh = newRules.filter { new in
            !rules.contains { existing in
                existing.target == new.target
                    && existing.matchType == new.matchType
                    && existing.action == new.action
                    && TextNormalizer.normalize(existing.pattern) == TextNormalizer.normalize(new.pattern)
            }
        }
        guard !fresh.isEmpty else { return 0 }
        rules += fresh
        save()
        return fresh.count
    }

    func setEnabled(_ isEnabled: Bool, for rule: Rule) {
        var updated = rule
        updated.isEnabled = isEnabled
        upsert(updated)
    }

    func delete(_ rule: Rule) {
        rules.removeAll { $0.id == rule.id }
        save()
    }

    func resetToDefaults() {
        rules = store?.loadCatalog().rules ?? DefaultRules.all
        unblockSaving()
        save()
    }

    /// Replaces all rules with the ones in the file, brought up to date with the built-in rules
    /// the same way the filter extension loads them.
    func importRules(from url: URL) {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer { if isScoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let latest = store?.loadCatalog().rules ?? DefaultRules.all
            rules = DefaultRules.merged(with: try RuleStore.decode(Data(contentsOf: url)), latest: latest)
            unblockSaving()
            save()
        } catch {
            errorMessage = String(localized: "Dosya okunamadı: \(error.localizedDescription)")
        }
    }

    private func unblockSaving() {
        guard isSavingBlocked else { return }
        isSavingBlocked = false
        errorMessage = nil
    }

    private func save() {
        guard let store, !isSavingBlocked else { return }
        do {
            try store.save(rules)
        } catch {
            errorMessage = String(localized: "Kurallar kaydedilemedi: \(error.localizedDescription)")
        }
    }
}
