import Foundation
import UIKit

final class ApiSettingsViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet private var highToggle: UISwitch!
    @IBOutlet private var moderateToggle: UISwitch!
    @IBOutlet private var defaultToggle: UISwitch!
    @IBOutlet private var lightToggle: UISwitch!

    @IBOutlet private var threadToggle: UISwitch!
    @IBOutlet private var threadInfo: UILabel!

    @IBOutlet private var migrationButton: UIButton!
    @IBOutlet private var migrationIndicator: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        threadInfo.text = Settings.threadedSyncHelp
        updateUI()
    }

    private func updateMigrationStatus() {
        switch Settings.V4IdMigrationPhase {
        case .done:
            migrationIndicator.text = "Status: Completed"
            migrationButton.isEnabled = true
        case .failedAnnounced, .failedPending:
            migrationIndicator.text = "Status: Failed"
            migrationButton.isEnabled = true
        case .inProgress:
            migrationIndicator.text = "Running…"
            migrationButton.isEnabled = false
        case .pending:
            migrationIndicator.text = "Not performed yet"
            migrationButton.isEnabled = true
        }
    }

    @IBAction private func migrationSelected(_: UIButton) {
        Settings.V4IdMigrationPhase = .inProgress
        updateMigrationStatus()
        Task {
            await API.attemptV4Migration()
            updateMigrationStatus()
        }
    }

    @IBAction private func toggleSelected(_ sender: UISwitch) {
        if sender === highToggle {
            Settings.syncProfile = GraphQL.Profile.high.rawValue
        } else if sender === moderateToggle {
            Settings.syncProfile = GraphQL.Profile.moderate.rawValue
        } else if sender === defaultToggle {
            Settings.syncProfile = GraphQL.Profile.cautious.rawValue
        } else if sender === lightToggle {
            Settings.syncProfile = GraphQL.Profile.light.rawValue
        }
        updateUI()
    }

    @IBAction private func defaultsSelected(_: UIBarButtonItem) {
        Settings.syncProfile = GraphQL.Profile.cautious.rawValue
        Settings.threadedSync = false
        updateUI()
    }

    private func updateUI() {
        let profile = GraphQL.Profile(settingsValue: Settings.syncProfile)
        highToggle.isOn = profile == .high
        moderateToggle.isOn = profile == .moderate
        defaultToggle.isOn = profile == .cautious
        lightToggle.isOn = profile == .light
        threadToggle.isOn = Settings.threadedSync
        updateMigrationStatus()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if highToggle.isOn {
            Settings.syncProfile = GraphQL.Profile.high.rawValue
        } else if moderateToggle.isOn {
            Settings.syncProfile = GraphQL.Profile.moderate.rawValue
        } else if defaultToggle.isOn {
            Settings.syncProfile = GraphQL.Profile.cautious.rawValue
        } else if lightToggle.isOn {
            Settings.syncProfile = GraphQL.Profile.light.rawValue
        }
        Settings.threadedSync = threadToggle.isOn
    }
}
