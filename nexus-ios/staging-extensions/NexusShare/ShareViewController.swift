// ShareViewController.swift
// Share Sheet extension — appears in the system Share Sheet from any app.
// User shares text, a URL, or images; we hand them to Eve via the same
// App Group container that the widget reads from. The main app picks up
// the queued payload on next launch and feeds it into a fresh Eve
// conversation thread.
//
// Why this pattern (App Group container, not a deep link): URLs work but
// stop ugly when the system kills the source app mid-share. App Group
// queueing means the share completes synchronously — Eve gets it on the
// main app's next foreground.
//
// Add this file to a new Share Extension target in Xcode. Set the same
// App Group entitlement (`group.io.talkcircles.nexus`) on both this
// extension and the main app.

import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices

class ShareViewController: SLComposeServiceViewController {
    private let appGroup = "group.io.talkcircles.nexus"
    private let queueKey = "share.queue"

    override func isContentValid() -> Bool {
        true   // accept anything; Eve will figure out what to do
    }

    override func didSelectPost() {
        Task { [weak self] in
            guard let self else { return }
            let bodyText = self.contentText ?? ""
            var capturedItems: [SharedItem] = []
            if !bodyText.isEmpty {
                capturedItems.append(SharedItem(kind: .text, value: bodyText))
            }

            // Pull every attachment off the input items.
            for item in self.extensionContext?.inputItems ?? [] {
                guard let extItem = item as? NSExtensionItem,
                      let attachments = extItem.attachments else { continue }
                for provider in attachments {
                    if let captured = await self.capture(provider) {
                        capturedItems.append(captured)
                    }
                }
            }

            self.enqueue(capturedItems)
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    override func configurationItems() -> [Any]! { [] }

    // MARK: - Capture

    private struct SharedItem: Codable {
        enum Kind: String, Codable { case text, url, image }
        let kind: Kind
        let value: String
        let imageData: Data?

        init(kind: Kind, value: String, imageData: Data? = nil) {
            self.kind = kind
            self.value = value
            self.imageData = imageData
        }
    }

    private func capture(_ provider: NSItemProvider) async -> SharedItem? {
        // Order matters — check URL before plain text so a Safari share
        // resolves as URL, not the page title.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return SharedItem(kind: .url, value: url.absoluteString)
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier) as? URL,
               let data = try? Data(contentsOf: url) {
                // Cap at 5MB so the queue stays light. Larger images can
                // be sent from the main app later.
                if data.count <= 5 * 1024 * 1024 {
                    return SharedItem(kind: .image, value: url.lastPathComponent, imageData: data)
                }
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.text.identifier) as? String {
                return SharedItem(kind: .text, value: text)
            }
        }
        return nil
    }

    // MARK: - Queue

    private func enqueue(_ items: [SharedItem]) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        var queue: [SharedItem] = []
        if let data = defaults.data(forKey: queueKey),
           let existing = try? JSONDecoder().decode([SharedItem].self, from: data) {
            queue = existing
        }
        queue.append(contentsOf: items)
        if let encoded = try? JSONEncoder().encode(queue) {
            defaults.set(encoded, forKey: queueKey)
        }
    }
}
