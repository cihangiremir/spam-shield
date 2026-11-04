import Foundation
import FilterCore
import IdentityLookup

/// iOS starts this extension for each SMS/MMS from an unknown sender (not in Contacts and never replied to)
/// and moves the message to the folder we answer with.
final class MessageFilterExtension: ILMessageFilterExtension {}

extension MessageFilterExtension: ILMessageFilterQueryHandling {
    func handle(
        _ queryRequest: ILMessageFilterQueryRequest,
        context: ILMessageFilterExtensionContext,
        completion: @escaping (ILMessageFilterQueryResponse) -> Void
    ) {
        let decision = EngineCache.engine().evaluate(sender: queryRequest.sender, body: queryRequest.messageBody)

        let response = ILMessageFilterQueryResponse()
        response.action = decision.action.messageFilterAction
        completion(response)
    }
}

/// iOS often keeps the extension running for several messages in a row. Reading the rule files and compiling
/// every regex only when a file changed keeps each message cheap.
private enum EngineCache {
    private static let lock = NSLock()
    private static var cached: (engine: FilterEngine, fileDates: [Date?])?

    static func engine() -> FilterEngine {
        lock.lock()
        defer { lock.unlock() }

        // Without the App Group (signing misconfigured) still filter with the built-in rules.
        guard let store = RuleStore.shared() else {
            if let cached { return cached.engine }
            let engine = FilterEngine(rules: DefaultRules.all)
            cached = (engine, [])
            return engine
        }

        let fileDates = [store.fileURL, store.catalogURL].map { url in
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        }
        if let cached, cached.fileDates == fileDates { return cached.engine }

        let engine = FilterEngine(rules: store.load())
        cached = (engine, fileDates)
        return engine
    }
}

private extension FilterAction {
    var messageFilterAction: ILMessageFilterAction {
        switch self {
        case .allow: return .allow
        case .junk: return .junk
        case .promotion: return .promotion
        case .transaction: return .transaction
        }
    }
}
