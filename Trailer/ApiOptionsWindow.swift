import Cocoa

final class ApiOptionsWindow: NSWindow, NSWindowDelegate {
    weak var prefs: PreferencesWindow?

    @IBOutlet private var prPageLabel: NSTextField!
    @IBOutlet private var issuePageLabel: NSTextField!

    @IBOutlet private var prPageSlider: NSSlider!
    @IBOutlet private var issuePageSlider: NSSlider!

    @IBOutlet private var threadCheckbox: NSButton!

    @MainActor
    override func awakeFromNib() {
        super.awakeFromNib()
        delegate = self

        prPageLabel.toolTip = Settings.prSyncPageSizeHelp
        prPageSlider.toolTip = Settings.prSyncPageSizeHelp

        issuePageLabel.toolTip = Settings.issueSyncPageSizeHelp
        issuePageSlider.toolTip = Settings.issueSyncPageSizeHelp

        threadCheckbox.toolTip = Settings.threadedSyncHelp

        updateUI()
    }

    private func updateUI() {
        threadCheckbox.integerValue = Settings.threadedSync ? 1 : 0
        prPageSlider.integerValue = Settings.prSyncPageSize
        issuePageSlider.integerValue = Settings.issueSyncPageSize
        prPageLabel.stringValue = "PR results page size: \(Settings.prSyncPageSize)"
        issuePageLabel.stringValue = "Issue results page size: \(Settings.issueSyncPageSize)"
    }

    @IBAction private func prSliderChanged(_ sender: NSSlider) {
        let value = sender.integerValue
        Settings.prSyncPageSize = value
        prPageLabel.stringValue = "PR results page size: \(value)"
    }

    @IBAction private func issueSliderChanged(_ sender: NSSlider) {
        let value = sender.integerValue
        Settings.issueSyncPageSize = value
        issuePageLabel.stringValue = "Issue results page size: \(value)"
    }

    @IBAction private func threadingToggled(_ sender: NSButton) {
        Settings.threadedSync = sender.integerValue == 1
    }

    @IBAction private func resetSelected(_: NSButton) {
        Settings.prSyncPageSize = 20
        Settings.issueSyncPageSize = 20
        Settings.threadedSync = false
        updateUI()
    }

    func windowWillClose(_: Notification) {
        prefs?.closedApiOptionsWindow()
    }
}
