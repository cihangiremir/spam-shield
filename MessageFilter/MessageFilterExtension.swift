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
        // Without the App Group (signing misconfigured) still filter with the built-in rules.
        let rules = RuleStore.shared()?.load() ?? DefaultRules.all
        let decision = FilterEngine(rules: rules).evaluate(sender: queryRequest.sender, body: queryRequest.messageBody)

        let response = ILMessageFilterQueryResponse()
        response.action = decision.action.messageFilterAction
        completion(response)
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
