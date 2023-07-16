import Foundation
import UIKit

final class ApiSettingsViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet private var highToggle: UISwitch!
    @IBOutlet private var highInfo: UILabel!

    @IBOutlet private var defaultToggle: UISwitch!
    @IBOutlet private var defaultInfo: UILabel!

    @IBOutlet private var safeToggle: UISwitch!
    @IBOutlet private var safeInfo: UILabel!

    @IBOutlet private var threadToggle: UISwitch!
    @IBOutlet private var threadInfo: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        threadInfo.text = Settings.threadedSyncHelp
        updateUI()
    }

    @IBAction func toggleSelected(_ sender: UISwitch) {
        if sender === highToggle {
            Settings.syncProfile = GraphQL.Profile.high.rawValue
        } else if sender === defaultToggle {
            Settings.syncProfile = GraphQL.Profile.normal.rawValue
        } else if sender === safeToggle {
            Settings.syncProfile = GraphQL.Profile.cautious.rawValue
        }
        updateUI()
    }

    @IBAction func defaultsSelected(_: UIBarButtonItem) {
        Settings.syncProfile = GraphQL.Profile.normal.rawValue
        Settings.threadedSync = false
        updateUI()
    }

    private func updateUI() {
        let profile = GraphQL.Profile(settingsValue: Settings.syncProfile)
        highToggle.isOn = profile == .high
        defaultToggle.isOn = profile == .normal
        safeToggle.isOn = profile == .cautious
        threadToggle.isOn = Settings.threadedSync
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if highToggle.isOn {
            Settings.syncProfile = GraphQL.Profile.high.rawValue
        } else if defaultToggle.isOn {
            Settings.syncProfile = GraphQL.Profile.normal.rawValue
        } else {
            Settings.syncProfile = GraphQL.Profile.cautious.rawValue
        }
        Settings.threadedSync = threadToggle.isOn
    }
}
