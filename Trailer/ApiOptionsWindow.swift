import Cocoa

final class ApiOptionsWindow: NSWindow, NSWindowDelegate {
    weak var prefs: PreferencesWindow?

    @IBOutlet private var highRadio: NSButton!
    @IBOutlet private var moderateRadio: NSButton!
    @IBOutlet private var lightRadio: NSButton!
    @IBOutlet private var safeRadio: NSButton!
    @IBOutlet private var threadCheckbox: NSButton!

    @IBOutlet private var migrationIndicator: NSTextField!
    @IBOutlet private var migrationbutton: NSButton!

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
            Settings.syncProfile = GraphQL.Profile.cautious
        } else if sender === moderateRadio {
            Settings.syncProfile = GraphQL.Profile.moderate
        } else if sender === highRadio {
            Settings.syncProfile = GraphQL.Profile.high
        } else if sender === safeRadio {
            Settings.syncProfile = GraphQL.Profile.light
        }
    }

    private func updateUI() {
        threadCheckbox.integerValue = Settings.threadedSync ? 1 : 0
        let profile = Settings.syncProfile
        highRadio.integerValue = profile == .high ? 1 : 0
        moderateRadio.integerValue = profile == .moderate ? 1 : 0
        lightRadio.integerValue = profile == .cautious ? 1 : 0
        safeRadio.integerValue = profile == .light ? 1 : 0

        updateMigrationStatus()
    }

    @IBAction private func threadingToggled(_ sender: NSButton) {
        Settings.threadedSync = sender.integerValue == 1
    }

    @IBAction private func resetSelected(_: NSButton) {
        Settings.syncProfile = GraphQL.Profile.cautious
        Settings.threadedSync = false
        updateUI()
    }

    private func updateMigrationStatus() {
        switch Settings.V4IdMigrationPhase {
        case .done:
            migrationIndicator.stringValue = "Status: Completed"
            migrationbutton.isEnabled = true
        case .failedAnnounced, .failedPending:
            migrationIndicator.stringValue = "Status: Failed"
            migrationbutton.isEnabled = true
        case .inProgress:
            migrationIndicator.stringValue = "Running…"
            migrationbutton.isEnabled = false
        case .pending:
            migrationIndicator.stringValue = "Not performed yet"
            migrationbutton.isEnabled = true
        }
    }

    @IBAction private func migrationSelected(_: NSButton) {
        Settings.V4IdMigrationPhase = .inProgress
        updateMigrationStatus()
        Task {
            await API.attemptV4Migration()
            updateMigrationStatus()
        }
    }

    func windowWillClose(_: Notification) {
        prefs?.closedApiOptionsWindow()
    }
}
