import Cocoa

final class ApiOptionsWindow: NSWindow, NSWindowDelegate {
    weak var prefs: PreferencesWindow?

    @IBOutlet var highRadio: NSButton!
    @IBOutlet var moderateRadio: NSButton!
    @IBOutlet var lightRadio: NSButton!
    @IBOutlet var safeRadio: NSButton!

    @IBOutlet private var threadCheckbox: NSButton!

    @MainActor
    override func awakeFromNib() {
        super.awakeFromNib()
        delegate = self

        highRadio.toolTip = Settings.syncProfileHelp
        moderateRadio.toolTip = Settings.syncProfileHelp
        lightRadio.toolTip = Settings.syncProfileHelp
        safeRadio.toolTip = Settings.syncProfileHelp

        threadCheckbox.toolTip = Settings.threadedSyncHelp

        updateUI()
    }

    @IBAction func radioButtonSelected(_ sender: NSButton) {
        if sender === lightRadio {
            Settings.syncProfile = GraphQL.Profile.cautious.rawValue
        } else if sender === moderateRadio {
            Settings.syncProfile = GraphQL.Profile.moderate.rawValue
        } else if sender === highRadio {
            Settings.syncProfile = GraphQL.Profile.high.rawValue
        } else if sender === safeRadio {
            Settings.syncProfile = GraphQL.Profile.light.rawValue
        }
    }

    private func updateUI() {
        threadCheckbox.integerValue = Settings.threadedSync ? 1 : 0
        let profile = GraphQL.Profile(settingsValue: Settings.syncProfile)
        highRadio.integerValue = profile == .high ? 1 : 0
        moderateRadio.integerValue = profile == .moderate ? 1 : 0
        lightRadio.integerValue = profile == .cautious ? 1 : 0
        safeRadio.integerValue = profile == .light ? 1 : 0
    }

    @IBAction private func threadingToggled(_ sender: NSButton) {
        Settings.threadedSync = sender.integerValue == 1
    }

    @IBAction private func resetSelected(_: NSButton) {
        Settings.syncProfile = GraphQL.Profile.cautious.rawValue
        Settings.threadedSync = false
        updateUI()
    }

    func windowWillClose(_: Notification) {
        prefs?.closedApiOptionsWindow()
    }
}
