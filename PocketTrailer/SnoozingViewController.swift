import PopTimer
import UIKit

final class PreferencesTabBarController: UITabBarController {
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if preferencesDirty {
            Task {
                await app.startRefresh()
            }
        }
    }
}

final class SnoozingViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, PickerViewControllerDelegate {
    @IBOutlet private var table: UITableView!

    private var settingsChangedTimer: PopTimer!

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.largeTitleDisplayMode = .automatic
        settingsChangedTimer = PopTimer(timeInterval: 1.0) { @MainActor in
            await DataManager.postProcessAllItems(in: DataManager.main)
            await DataManager.saveDB()
        }
    }

    @IBAction private func done(_: UIBarButtonItem) {
        dismiss(animated: true)
    }

    @IBAction private func addNew(_: UIBarButtonItem) {
        performSegue(withIdentifier: "showSnoozeEditor", sender: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        table.reloadData()
    }

    func numberOfSections(in _: UITableView) -> Int {
        if SnoozePreset.allSnoozePresets(in: DataManager.main).isEmpty {
            return 2
        } else {
            return 3
        }
    }

    func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 || section == 1 {
            return 1
        } else {
            return SnoozePreset.allSnoozePresets(in: DataManager.main).count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SnoozeOptionCell", for: indexPath)
        if indexPath.section == 0 {
            cell.textLabel?.text = "Hide snoozed items"
            cell.accessoryType = Settings.hideSnoozedItems ? .checkmark : .none
        } else if indexPath.section == 1 {
            let d = Settings.autoSnoozeDuration
            if d > 0 {
                cell.textLabel?.text = "Auto-snooze items after \(d) days"
            } else {
                cell.textLabel?.text = "Do not auto-snooze items"
            }
            cell.accessoryType = .disclosureIndicator
        } else {
            let s = SnoozePreset.allSnoozePresets(in: DataManager.main)[indexPath.row]
            cell.textLabel?.text = s.listDescription
            cell.accessoryType = .disclosureIndicator
        }
        return cell
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "You can create presets here that can be used to 'snooze' items for a specific time duration, until a date, or if a specific event occurs."
        } else if section == 1 {
            return "Automatically snooze items after a specific amount of time…"
        } else {
            return "Existing presets:"
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            Settings.hideSnoozedItems = !Settings.hideSnoozedItems
            tableView.reloadData()
            settingsChangedTimer.push()

        } else if indexPath.section == 1 {
            let count = stride(from: 2, to: 9000, by: 1).map { "\($0) days" }
            let values = ["Never", "1 day"] + count
            let v = PickerViewController.Info(title: "Auto Snooze Items After", values: values, selectedIndex: Settings.autoSnoozeDuration, sourceIndexPath: indexPath)
            performSegue(withIdentifier: "showPicker", sender: v)

        } else {
            let s = SnoozePreset.allSnoozePresets(in: DataManager.main)[indexPath.row]
            performSegue(withIdentifier: "showSnoozeEditor", sender: s)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let d = segue.destination as? PickerViewController, let i = sender as? PickerViewController.Info {
            d.delegate = self
            d.info = i
        } else if let d = segue.destination as? SnoozingEditorViewController {
            if let s = sender as? SnoozePreset {
                d.isNew = false
                d.snoozeItem = s
            } else {
                d.isNew = true
                d.snoozeItem = SnoozePreset.newSnoozePreset(in: DataManager.main)
            }
        }
    }

    func pickerViewController(picker _: PickerViewController, didSelectIndexPath: IndexPath, info _: PickerViewController.Info) {
        Settings.autoSnoozeDuration = didSelectIndexPath.row
        table.reloadData()
        for p in PullRequest.allItems(in: DataManager.main) {
            p.wakeIfAutoSnoozed()
        }
        for i in Issue.allItems(in: DataManager.main) {
            i.wakeIfAutoSnoozed()
        }
        Task {
            await DataManager.postProcessAllItems(in: DataManager.main)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let i = table.indexPathForSelectedRow {
            table.deselectRow(at: i, animated: true)
        }
    }
}
