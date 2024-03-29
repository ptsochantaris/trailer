import Cocoa
import Combine
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

    override func awakeFromNib() {
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

            var hiddenCount = 0

            let settings = Settings.cache
            func report(for item: ListableItem) {
                let section = item.postProcess(settings: settings)
                switch section {
                case let .hidden(cause):
                    let title = item.title ?? "<no title>"
                    let numberString = String(item.number)
                    Task { @MainActor in
                        writeText("[\(item.repo.fullName.orEmpty) #\(numberString)]: \(title) -- \(cause.description)\n\n")
                        hiddenCount += 1
                    }
                default:
                    break
                }
            }

            textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: "")
            writeText("Scanning...\n\n")

            await withCheckedContinuation { continuation in
                let moc = DataManager.main.buildChildContext()
                moc.perform {
                    for p in PullRequest.allItems(in: moc, prefetchRelationships: ["comments", "reactions", "reviews"]) {
                        report(for: p)
                    }

                    for i in Issue.allItems(in: moc, prefetchRelationships: ["comments", "reactions"]) {
                        report(for: i)
                    }

                    continuation.resume()
                }
            }

            writeText("Done - \(hiddenCount) hidden items\n")
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
