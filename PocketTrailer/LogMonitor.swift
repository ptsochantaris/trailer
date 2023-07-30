import UIKit

final class LogMonitor: UIViewController {
    @IBOutlet private var autoScrollSwitch: UISwitch!
    @IBOutlet private var textView: UITextView!

    @IBAction private func clearSelected(_: UIBarButtonItem) {
        textStorage.mutableString.deleteCharacters(in: NSRange(location: 0, length: textStorage.length))
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

    override func viewDidLoad() {
        super.viewDidLoad()

        textStorage = textView.textStorage

        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyyMMdd HH:mm:ss:SSS"

        Logging.monitorObservation = Logging.logPublisher
            .sink { [weak self] message in
                guard let self else { return }

                let date = logDateFormatter.string(from: Date())
                let logString = NSAttributedString(string: ">>> \(date)\n\(message())\n\n")
                Task { @MainActor in
                    self.textStorage.append(logString)
                    if self.autoScrollSwitch.isOn {
                        let textCount = self.textStorage.length
                        self.textView.scrollRangeToVisible(NSRange(location: textCount - 1, length: 1))
                    }
                }
            }
    }

    deinit {
        Logging.monitorObservation = nil
    }
}
