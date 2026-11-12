import Foundation
import Testing
@testable import FilterCore

/// Runs the real messages in TrainingData/messages.json (see the README) through the built-in rules and checks
/// which folder each label ends up in. The hand-written samples in the other tests show that a rule works;
/// these thousands of real messages show what else a change catches, e.g. campaigns sent to Transactions.
/// The classifier is checked on the test messages, which the model checked here never saw.
struct TrainingDataTests {
    private struct Message: Decodable {
        let text: String
        let label: String
        let source: String
        let split: String
    }

    private static func load(_ name: String) -> [Message] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TrainingData/\(name).json")
        return try! JSONDecoder().decode([Message].self, from: Data(contentsOf: url))
    }

    private static let realMessages = load("messages")

    /// Messages per label and folder.
    private static let table: [String: [FilterAction: Int]] = {
        let engine = FilterEngine(rules: DefaultRules.all)

        var table: [String: [FilterAction: Int]] = [:]
        for message in realMessages {
            table[message.label, default: [:]][engine.evaluate(sender: nil, body: message.text).action, default: 0] += 1
        }
        return table
    }()

    private static var printedTable: String {
        table.sorted { $0.key < $1.key }.map { label, row in
            "\(label): " + FilterAction.allCases.map { "\($0.rawValue) \(row[$0] ?? 0)" }.joined(separator: ", ")
        }.joined(separator: "\n")
    }

    private func count(_ label: String, _ action: FilterAction) -> Int {
        Self.table[label]?[action] ?? 0
    }

    @Test func personalMessagesAreNeverHidden() {
        #expect(count("personal", .junk) == 0, "\(Self.printedTable)")
        #expect(count("personal", .promotion) == 0, "\(Self.printedTable)")
    }

    @Test func noticesAreNeverHidden() {
        #expect(count("transaction", .junk) == 0, "\(Self.printedTable)")
        #expect(count("transaction", .promotion) == 0, "\(Self.printedTable)")
    }

    /// Limits at today's counts: a rise means a rule started misfiling real messages. Lower them when a rule improves.
    /// The campaigns still in Transactions are card campaigns ("kartınızla 150 TL ve üzeri alımınıza puan");
    /// the ones in Junk are mostly older campaigns whose opt-out is a short link ("SMS iptali için http://j.mp/...").
    @Test func campaignsStayOutOfTransactionsAndJunk() {
        #expect(count("promotion", .transaction) <= 8, "\(Self.printedTable)")
        #expect(count("promotion", .junk) <= 344, "\(Self.printedTable)")
    }

    /// Few of the `ds-spam` messages (sex pills, paid subscriptions, call-this-number prizes) have a rule yet.
    @Test func spamIsCaught() {
        #expect(count("junk", .junk) >= 240, "\(Self.printedTable)")
    }

    // MARK: Classifier

    /// Folder counts per label for real / synthetic test messages no rule matched, from a model trained only
    /// on the `train` messages, like `swift run TrainClassifier` prints it.
    private static let classifierTable: [String: [String: [FilterAction: Int]]] = {
        let messages = realMessages + load("synthetic")
        var classifier = SpamClassifier()
        for message in messages where message.split == "train" {
            classifier.learn(message.text, as: MessageKind(rawValue: message.label)!)
        }
        classifier = classifier.pruned(minimumCount: 3)

        let rules = FilterEngine(rules: DefaultRules.all)
        var table: [String: [String: [FilterAction: Int]]] = [:]
        for message in messages where message.split == "test" && rules.evaluate(sender: nil, body: message.text).matchedRule == nil {
            let origin = message.source.hasPrefix("synthetic-") ? "synthetic" : "real"
            table[origin, default: [:]][message.label, default: [:]][classifier.verdict(message.text) ?? .allow, default: 0] += 1
        }
        return table
    }()

    private func classified(_ origin: String, _ label: String, _ action: FilterAction? = nil) -> Int {
        let row = Self.classifierTable[origin]?[label] ?? [:]
        return action.map { row[$0] ?? 0 } ?? row.values.reduce(0, +)
    }

    /// At most 0.5% of personal messages leave the inbox, and no notice goes to Promotions.
    /// The one real personal message it moves today is Finansbank's "şifreniz blokelenmiştir ... tıklayın" warning.
    @Test(arguments: ["real", "synthetic"])
    func classifierLeavesPersonalMessagesAndNoticesAlone(origin: String) {
        let moved = classified(origin, "personal") - classified(origin, "personal", .allow)
        #expect(Double(moved) <= 0.005 * Double(classified(origin, "personal")), "\(Self.classifierTable)")
        #expect(classified(origin, "transaction", .promotion) == 0, "\(Self.classifierTable)")
    }

    /// Limits at today's counts, like the rule limits above. Synthetic campaigns are caught less often: they share
    /// more words with notices, and the margins are set to leave a message alone when in doubt.
    @Test func classifierMovesCampaignsToPromotions() {
        #expect(classified("real", "promotion", .promotion) >= 185, "\(Self.classifierTable)")
        let synthetic = classified("synthetic", "promotion", .promotion) + classified("synthetic", "junk", .promotion)
        #expect(synthetic >= 120, "\(Self.classifierTable)")
        #expect(classified("synthetic", "transaction", .transaction) >= 65, "\(Self.classifierTable)")
    }

    /// Real legitimate messages (`legitimate-samples` in the data) with the bundled model switched on.
    @Test func legitimateSamplesStayOutOfPromotionsWithTheClassifier() {
        let engine = FilterEngine(rules: DefaultRules.all, classifier: .bundled)
        for message in Self.realMessages where message.source == "legit-samples" && message.label != "promotion" {
            let action = engine.evaluate(sender: nil, body: message.text).action
            #expect(action != .promotion && action != .junk, "\(message.text)")
        }
    }
}
