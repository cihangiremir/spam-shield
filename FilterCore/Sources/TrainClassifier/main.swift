import FilterCore
import Foundation

/// Trains the bundled classifier on TrainingData/messages.json, prints how well it does on messages it
/// didn't see, and writes Sources/FilterCore/Resources/classifier.json.
///
/// The file holds the Mac junk folder's messages in the order they arrived ("mac-junk"), then the datasets'
/// messages and the legitimate samples, labelled junk or not (see the README).

struct Message: Decodable {
    let text: String
    let isJunk: Bool
    let source: String
}

/// Tokens seen in fewer messages are dropped: little signal, and they could be names or codes from one message.
let minimumCount = 3

let packageURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let messages = try JSONDecoder().decode(
    [Message].self,
    from: Data(contentsOf: packageURL.appendingPathComponent("TrainingData/messages.json"))
)

func train(_ messages: [Message]) -> SpamClassifier {
    var classifier = SpamClassifier()
    for message in messages { classifier.learn(message.text, isJunk: message.isJunk) }
    return classifier.pruned(minimumCount: minimumCount)
}

/// How many messages of each source were called spam, and the non-junk ones that were.
func report(_ title: String, _ scored: [(message: Message, score: Double)]) {
    print(title)
    for (source, group) in Dictionary(grouping: scored, by: \.message.source).sorted(by: { $0.key < $1.key }) {
        print("  \(source): \(group.filter { $0.score > SpamClassifier.threshold }.count)/\(group.count) spam")
    }
    for (message, score) in scored where !message.isJunk && score > SpamClassifier.threshold {
        print("  not junk but spam (\(String(format: "%.1f", score))): \(message.text.prefix(100).replacingOccurrences(of: "\n", with: " "))")
    }
}

// Every fifth message is held out in turn, so each one is scored by a model that didn't see it.
var crossValidated: [(message: Message, score: Double)] = []
for fold in 0..<5 {
    let held = messages.indices.filter { $0 % 5 == fold }
    let classifier = train(messages.indices.filter { $0 % 5 != fold }.map { messages[$0] })
    crossValidated += held.map { (messages[$0], classifier.score(messages[$0].text)) }
}
report("Cross-validation (5 folds)", crossValidated)

// Closer to real use: learn from older junk, judge the junk that came later.
let junkFolder = messages.filter { $0.source == "mac-junk" }
let others = messages.filter { $0.source != "mac-junk" }
let cut = junkFolder.count * 6 / 10
let older = train(Array(junkFolder[..<cut]) + others.enumerated().filter { $0.offset % 5 != 0 }.map(\.element))
let later = Array(junkFolder[cut...]) + others.enumerated().filter { $0.offset % 5 == 0 }.map(\.element)
report("Older junk → later junk", later.map { ($0, older.score($0.text)) })

let classifier = train(messages)
let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
let outputURL = packageURL.appendingPathComponent("Sources/FilterCore/Resources/classifier.json")
try encoder.encode(classifier).write(to: outputURL)
print("Wrote \(outputURL.path): \(classifier.junkMessages) junk, \(classifier.otherMessages) other messages")
