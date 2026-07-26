import Foundation
import UIKit

final class HiddenItemScan: UIViewController {
    @IBOutlet private var textView: UITextView!
    @IBOutlet private var scanButton: UIButton!

    @IBAction private func rescanSelected(sender: UIButton) {
        sender.isEnabled = false
        Task {
            defer {
                sender.isEnabled = true
            }

            let settings = Settings.cache

            textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: "")
            writeText("Scanning...\n\n")

            // The report lines are built on the child context's own queue, where these managed objects
            // actually live, and only strings come back. Previously each line was assembled inside a
            // `Task { @MainActor }`, which read `item.repo` from the main queue while the object
            // belonged to the private one — and meant the count was read before any of those tasks had
            // run, so "Done - n hidden items" was reliably wrong.
            let lines: [String] = await withCheckedContinuation { continuation in
                let moc = DataManager.main.buildChildContext()
                moc.perform {
                    var lines = [String]()

                    func report(for item: ListableItem) {
                        guard case let .hidden(cause) = item.postProcess(settings: settings) else {
                            return
                        }
                        let title = item.title ?? "<no title>"
                        lines.append("[\(item.repo.fullName.orEmpty) #\(item.number)]: \(title) -- \(cause.description)\n\n")
                    }

                    for p in PullRequest.allItems(in: moc, prefetchRelationships: ["comments", "reactions", "reviews"]) {
                        report(for: p)
                    }

                    for i in Issue.allItems(in: moc, prefetchRelationships: ["comments", "reactions"]) {
                        report(for: i)
                    }

                    continuation.resume(returning: lines)
                }
            }

            for line in lines {
                writeText(line)
            }
            writeText("Done - \(lines.count) hidden items\n")
        }
    }

    @IBAction private func copySelected(_: UIBarButtonItem) {
        if let log = textStorage?.string {
            UIPasteboard.general.string = log
        }
    }

    @IBAction private func syncNowSelected(_: UIButton) {
        Task {
            await app.startRefresh()
        }
    }

    private var textStorage: NSTextStorage!

    @MainActor
    private func writeText(_ message: String) {
        textStorage.append(NSAttributedString(string: message))
        let textCount = textStorage.length
        textView.scrollRangeToVisible(NSRange(location: textCount - 1, length: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        textStorage = textView.textStorage
        rescanSelected(sender: scanButton)
    }
}
