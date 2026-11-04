import FilterCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Messages › long press › Share › Spam Shield. Shows the Check tab's suggestions for the shared message
/// and saves the picked rules to the App Group, where the filter extension and the app pick them up.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let host = UIHostingController(rootView: ShareView(items: items) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

struct ShareView: View {
    let items: [NSExtensionItem]
    let onDone: () -> Void

    @State private var model = RuleListModel()
    @State private var sender = ""
    @State private var messageText = ""

    var body: some View {
        NavigationStack {
            CheckForm(sender: $sender, messageText: $messageText)
                .safeAreaInset(edge: .top) {
                    if let errorMessage = model.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.bar)
                    }
                }
                .navigationTitle("Spam bildir")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Bitti", action: onDone)
                    }
                }
        }
        .environment(model)
        .task {
            messageText = await Self.sharedText(from: items)
        }
    }

    /// Messages shares a message as plain text; other apps may share a link as a URL.
    /// A link that is already in the text isn't added twice.
    static func sharedText(from items: [NSExtensionItem]) async -> String {
        var texts: [String] = []
        var links: [String] = []

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                   let text = string(from: loaded) {
                    texts.append(text)
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                          let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                          let link = string(from: loaded) {
                    links.append(link)
                }
            }
            if texts.isEmpty, let text = item.attributedContentText?.string, !text.isEmpty {
                texts.append(text)
            }
        }

        let text = texts.joined(separator: "\n")
        let newLinks = links.filter { !text.contains($0) }
        return ([text] + newLinks).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func string(from item: NSSecureCoding) -> String? {
        switch item {
        case let text as String:
            return text
        case let url as URL:
            return url.isFileURL ? try? String(contentsOf: url, encoding: .utf8) : url.absoluteString
        case let data as Data:
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }
}
