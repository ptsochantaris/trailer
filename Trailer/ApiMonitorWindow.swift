import Cocoa
import Combine

final class ApiMonitorWindow: NSWindow, NSWindowDelegate {
    @IBOutlet private var textView: NSTextView!
    @IBOutlet private var scrollView: NSScrollView!

    weak var prefs: PreferencesWindow?

    private var autoScroll = true
    private var textStorage: NSMutableAttributedString!

    static let logParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.headIndent = 27
        return p
    }()

    static let logAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.textColor,
        .paragraphStyle: logParagraphStyle,
        .font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    ]

    override func awakeFromNib() {
        super.awakeFromNib()
        delegate = self
        textStorage = textView.textStorage

        let logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "yyyyMMdd HH:mm:ss:SSS"

        Logging.monitorObservation = Logging.logPublisher
            .sink { [weak self] message in
                guard let self else { return }

                let date = logDateFormatter.string(from: Date())
                let logString = NSAttributedString(string: ">>> \(date) - \(message())\n\n", attributes: ApiMonitorWindow.logAttributes)
                Task { @MainActor in
                    self.textStorage.append(logString)
                    if self.autoScroll {
                        self.textView.scrollToEndOfDocument(nil)
                    }
                }
            }
    }

    func windowWillClose(_: Notification) {
        Logging.monitorObservation = nil
        prefs?.closedApiMonitorWindow()
    }

    @IBAction private func autoScrollSelected(_ sender: NSButton) {
        autoScroll = sender.integerValue != 0
    }

    @IBAction private func copySelected(_: NSButton) {
        if let log = textStorage?.string {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.declareTypes([.string], owner: nil)
            NSPasteboard.general.setString(log, forType: .string)
        }
    }

    @IBAction private func clearSelected(_: NSButton) {
        textStorage.mutableString.deleteCharacters(in: NSRange(location: 0, length: textStorage.length))
    }
}
