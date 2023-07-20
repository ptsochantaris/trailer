import Cocoa

extension Notification.Name {
    static let LogMessagePosted = Notification.Name("LogMessagePosted")
}

extension NSAttributedString: @unchecked Sendable {}

final class ApiMonitorWindow: NSWindow, NSWindowDelegate {
    @IBOutlet private var textView: NSTextView!
    @IBOutlet private var scrollView: NSScrollView!

    weak var prefs: PreferencesWindow?

    private var autoScroll = true
    private var textStorage: NSMutableAttributedString!

    override func awakeFromNib() {
        super.awakeFromNib()
        delegate = self

        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(newMessage(_:)), name: .LogMessagePosted, object: nil)

        monitoringLog = true

        textStorage = textView.textStorage
    }

    func windowWillClose(_: Notification) {
        monitoringLog = false
        prefs?.closedApiMonitorWindow()
    }

    private let dateFormatter: DateFormatter = {
        let d = DateFormatter()
        d.dateFormat = "yyyyMMdd HH:mm:ss:SSS"
        return d
    }()

    @IBAction private func autoScrollSelected(_ sender: NSButton) {
        autoScroll = sender.integerValue != 0
    }

    @IBAction private func copySelected(_: NSButton) {
        if let log = textView.textStorage?.string {
            NSPasteboard.general.setString(log, forType: .string)
        }
    }

    @objc private func newMessage(_ notification: Notification) {
        guard let message = notification.object as? (() -> String) else {
            return
        }

        let now = Date()

        Task.detached(priority: .utility) {
            let date = self.dateFormatter.string(from: now)
            let logString = NSAttributedString(string: ">>> \(date) - \(message())\n\n", attributes: [
                .foregroundColor: NSColor.textColor
            ])
            Task { @MainActor in
                self.textStorage.append(logString)
                if self.autoScroll {
                    self.textView.scrollToEndOfDocument(nil)
                }
            }
        }
    }
}
