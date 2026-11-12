import FilterCore
import Foundation

/// Trains the bundled classifier, prints how well it does on messages it didn't see, and writes
/// Sources/FilterCore/Resources/classifier.json.
///
/// Training data (see the README): TrainingData/messages.json holds real messages, TrainingData/synthetic.json
/// generated ones. Each message is labelled personal, transaction, promotion or junk and belongs to a split
/// (`scripts/split_training_data.py`). The model is trained on `train`, the margins in `SpamClassifier` are
/// chosen on `validation`, and `test` is only looked at to report the result. Real messages are reported apart
/// from synthetic ones: how the filter does on real messages is what counts.
/// The model written to the app is then trained on every split.

struct Message: Decodable {
    let text: String
    let label: MessageKind
    let source: String
    let split: String

    var origin: String {
        guard source.hasPrefix("synthetic-") else { return "real" }
        // "synthetic-claude-tr-personal" → "synthetic-claude-tr"
        return source.split(separator: "-").prefix(3).joined(separator: "-")
    }
}

/// Tokens seen in fewer messages are dropped: little signal, and they could be names or codes from one message.
let minimumCount = 3

let dataURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("TrainingData")
let messages = try ["messages.json", "synthetic.json"].flatMap { name in
    try JSONDecoder().decode([Message].self, from: Data(contentsOf: dataURL.appendingPathComponent(name)))
}

func train(_ messages: [Message]) -> SpamClassifier {
    var classifier = SpamClassifier()
    for message in messages { classifier.learn(message.text, as: message.label) }
    return classifier.pruned(minimumCount: minimumCount)
}

// The classifier only sees messages no rule matched, so only those are scored.
let rules = FilterEngine(rules: DefaultRules.all)
let unmatched = messages.filter { rules.evaluate(sender: nil, body: $0.text).matchedRule == nil }

let model = train(messages.filter { $0.split == "train" })
func scored(_ split: String) -> [(message: Message, scores: [MessageKind: Double])] {
    unmatched.filter { $0.split == split }.map { ($0, model.scores($0.text)) }
}
let validation = scored("validation")
let test = scored("test")

/// Folder counts per label: inbox / Transactions / Promotions.
func row(_ group: [(message: Message, scores: [MessageKind: Double])], _ label: MessageKind,
         hidingMargin: Double = SpamClassifier.hidingMargin,
         promotionMargin: Double = SpamClassifier.promotionMargin) -> (inbox: Int, transaction: Int, promotion: Int) {
    var counts = (inbox: 0, transaction: 0, promotion: 0)
    for item in group where item.message.label == label {
        switch SpamClassifier.verdict(for: item.scores, hidingMargin: hidingMargin, promotionMargin: promotionMargin) {
        case .transaction: counts.transaction += 1
        case .promotion: counts.promotion += 1
        default: counts.inbox += 1
        }
    }
    return counts
}

func report(_ title: String, _ items: [(message: Message, scores: [MessageKind: Double])]) {
    print("\(title) (messages no rule matched; inbox / Transactions / Promotions)")
    for (origin, group) in Dictionary(grouping: items, by: \.message.origin).sorted(by: { $0.key < $1.key }) {
        let cells = MessageKind.allCases.map { label -> String in
            let counts = row(group, label)
            return "\(label.rawValue) \(counts.inbox)/\(counts.transaction)/\(counts.promotion)"
        }
        print("  \(origin): " + cells.joined(separator: "  "))
    }
    for item in items where item.message.origin == "real" {
        let verdict = SpamClassifier.verdict(for: item.scores)
        let wrong = (item.message.label == .personal && verdict != nil)
            || (item.message.label == .transaction && verdict == .promotion)
        if wrong {
            let text = item.message.text.prefix(100).replacingOccurrences(of: "\n", with: " ")
            print("  real \(item.message.label.rawValue) → \(verdict?.rawValue ?? "inbox"): \(text)")
        }
    }
}

// For choosing the margins (see `SpamClassifier.hidingMargin`). Pick them here, never on the test messages.
print("Margins on validation: personal moved, notices → Promotions, campaigns+spam → Promotions")
for hiding in [4.0, 6.0, 8.0, 10.0, 12.0] {
    for promotion in [0.0, 2.0, 4.0] {
        let personal = row(validation, .personal, hidingMargin: hiding, promotionMargin: promotion)
        let notices = row(validation, .transaction, hidingMargin: hiding, promotionMargin: promotion)
        let campaigns = [MessageKind.promotion, .junk].map { row(validation, $0, hidingMargin: hiding, promotionMargin: promotion) }
        let caught = campaigns.map(\.promotion).reduce(0, +)
        let all = campaigns.map { $0.inbox + $0.transaction + $0.promotion }.reduce(0, +)
        print("  \(hiding)/\(promotion): \(personal.transaction + personal.promotion)  \(notices.promotion)  \(caught)/\(all)")
    }
}
report("Validation", validation)
report("Test", test)

let classifier = train(messages)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
let outputURL = dataURL.deletingLastPathComponent().appendingPathComponent("Sources/FilterCore/Resources/classifier.json")
try encoder.encode(classifier).write(to: outputURL)
let counts = MessageKind.allCases.map { "\(classifier.messages[$0, default: 0]) \($0.rawValue)" }.joined(separator: ", ")
print("Wrote \(outputURL.path): \(counts)")
