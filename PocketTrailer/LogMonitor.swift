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

        Task {
            await Logging.shared.setupMonitorCallback { [weak self] logString in
                guard let self else { return }
                textStorage.append(logString)
                if autoScrollSwitch.isOn {
                    let textCount = textStorage.length
                    textView.scrollRangeToVisible(NSRange(location: textCount - 1, length: 1))
                }
            }
        }
    }

    deinit {
        Task {
            await Logging.shared.setupMonitorCallback(nil)
        }
    }
}
