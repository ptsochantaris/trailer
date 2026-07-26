import Cocoa
import Foundation

final class HiddenItemWindow: NSWindow, NSWindowDelegate {
    @IBOutlet private var textView: NSTextView!
    @IBOutlet private var reScanButton: NSButton!

    weak var prefs: PreferencesWindow?

    private var textStorage: NSTextStorage!

    @MainActor
    private func writeText(_ message: String) {
        textStorage.append(NSAttributedString(string: message, attributes: ApiMonitorWindow.logAttributes))
    }

    override nonisolated func awakeFromNib() {
        // AppKit loads nibs on the main thread; the real work is main-actor isolated.
        MainActor.assumeIsolated { awakeFromNibOnMain() }
    }

    @MainActor
    private func awakeFromNibOnMain() {
        super.awakeFromNib()
        delegate = self
        textStorage = textView.textStorage
        scan(reScanButton)
    }

    @IBAction private func scan(_ sender: NSButton) {
        sender.isEnabled = false
        Task {
            defer {
                sender.isEnabled = true
            }

            let settings = Settings.cache

            textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: "")
            writeText("Scanning...\n\n")

            // This is a read-only "what would be hidden" scan, so it runs in a throwaway
            // child context which is deliberately never saved. Everything that touches a
            // managed object stays on that context's own queue; only plain strings come back.
            let moc = DataManager.main.buildChildContext()
            let lines = await moc.perform {
                var lines = [String]()

                func report(for item: ListableItem) {
                    guard case let .hidden(cause) = item.postProcess(settings: settings) else {
                        return
                    }
                    let title = item.title ?? "<no title>"
                    lines.append("[\(item.repo.fullName.orEmpty) #\(String(item.number))]: \(title) -- \(cause.description)\n\n")
                }

                for p in PullRequest.allItems(in: moc, prefetchRelationships: ["comments", "reactions", "reviews"]) {
                    report(for: p)
                }

                for i in Issue.allItems(in: moc, prefetchRelationships: ["comments", "reactions"]) {
                    report(for: i)
                }

                return lines
            }

            writeText(lines.joined())
            writeText("Done - \(lines.count) hidden items\n")
        }
    }

    func windowWillClose(_: Notification) {
        prefs?.closedHiddenItemMonitorWindow()
    }

    @IBAction private func copySelected(_: NSButton) {
        if let log = textStorage?.string {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.declareTypes([.string], owner: nil)
            NSPasteboard.general.setString(log, forType: .string)
        }
    }
}
