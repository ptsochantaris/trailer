import Foundation
import UIKit

final class ApiSettingsViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet private var prSizeLabel: UILabel!
    @IBOutlet private var issueSizeLabel: UILabel!

    @IBOutlet private var prSizeField: UITextField!
    @IBOutlet private var issueSizeField: UITextField!

    @IBOutlet private var threadToggle: UISwitch!

    override func viewDidLoad() {
        super.viewDidLoad()
        updateUI()
    }

    @IBAction func defaultsSelected(_: UIBarButtonItem) {
        Settings.prSyncPageSize = 20
        Settings.issueSyncPageSize = 20
        Settings.threadedSync = false
        updateUI()
    }

    private func updateUI() {
        prSizeField.text = String(Settings.prSyncPageSize)
        issueSizeField.text = String(Settings.issueSyncPageSize)
        threadToggle.isOn = Settings.threadedSync
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        Settings.prSyncPageSize = min(100, max(1, Int(prSizeField.text ?? "") ?? 20))
        Settings.issueSyncPageSize = min(100, max(1, Int(issueSizeField.text ?? "") ?? 20))
        Settings.threadedSync = threadToggle.isOn
    }
}
