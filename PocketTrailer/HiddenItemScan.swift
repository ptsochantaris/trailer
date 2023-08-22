//
//  HiddenItemScan.swift
//  PocketTrailer
//
//  Created by Paul Tsochantaris on 22/08/2023.
//

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
        let textCount = self.textStorage.length
        textView.scrollRangeToVisible(NSRange(location: textCount - 1, length: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        textStorage = textView.textStorage
        rescanSelected(sender: scanButton)
    }
}
