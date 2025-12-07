import UIKit

final class SnoozingEditorViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIPickerViewDataSource, UIPickerViewDelegate {
    @IBOutlet private var table: UITableView!
    @IBOutlet private var descriptionLabel: UILabel!

    var snoozeItem: SnoozePreset?
    var isNew = false

    @IBOutlet private var typeSelector: UISegmentedControl!

    @IBAction private func deleteSelected(_: UIBarButtonItem) {
        if let snoozeItem {
            let appliedCount = snoozeItem.appliedToIssues.count + snoozeItem.appliedToPullRequests.count
            if appliedCount > 0 {
                let a = UIAlertController(title: "Delete Snooze Preset",
                                          message: "You have \(appliedCount) items that have been snoozed using this preset. What would you like to do with them after deleting this preset?",
                                          preferredStyle: .alert)

                a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                a.addAction(UIAlertAction(title: "Wake Them Up", style: .destructive) { _ in
                    snoozeItem.wakeUpAllAssociatedItems(settings: Settings.cache)
                    self.deletePreset()
                })
                a.addAction(UIAlertAction(title: "Keep Them Snoozed", style: .destructive) { _ in
                    self.deletePreset()
                })

                present(a, animated: true)

            } else {
                let a = UIAlertController(title: "Delete Snooze Preset",
                                          message: "Are you sure you want to remove this preset from your list?",
                                          preferredStyle: .alert)

                a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                a.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
                    self.deletePreset()
                })

                present(a, animated: true)
            }
        }
    }

    private func deletePreset() {
        if let snoozeItem {
            DataManager.main.delete(snoozeItem)
        }
        _ = navigationController?.popViewController(animated: true)
    }

    @IBAction private func upSelected(_: UIBarButtonItem) {
        if let snoozeItem {
            let all = SnoozePreset.allSnoozePresets(in: DataManager.main)
            if let index = all.firstIndex(of: snoozeItem), index > 0 {
                let other = all[index - 1]
                other.sortOrder = index
                snoozeItem.sortOrder = index - 1
                updateView()
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Task {
            await DataManager.saveDB()
        }
    }

    @IBAction private func downSelected(_: UIBarButtonItem) {
        if let snoozeItem {
            let all = SnoozePreset.allSnoozePresets(in: DataManager.main)
            if let index = all.firstIndex(of: snoozeItem), index < all.count - 1 {
                let other = all[index + 1]
                other.sortOrder = index
                snoozeItem.sortOrder = index + 1
                updateView()
            }
        }
    }

    @IBAction private func typeSelectorChanged(_: UISegmentedControl) {
        updateView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew ? "New" : "Edit"
        typeSelector.selectedSegmentIndex = (snoozeItem?.duration ?? false) ? 0 : 1
        updateView()
        hidePickerAnimated(animate: false)
    }

    private func updateView() {
        table.reloadData()
        snoozeItem?.duration = typeSelector.selectedSegmentIndex == 0
        let total = SnoozePreset.allSnoozePresets(in: DataManager.main).count
        let desc = (snoozeItem?.listDescription).orEmpty
        if total > 1 {
            let pos = (snoozeItem?.sortOrder ?? 0) + 1
            descriptionLabel.text = "\"\(desc)\"\n\(pos) of \(total) on the snooze menu"
        } else {
            descriptionLabel.text = "\"\(desc)\""
        }
    }

    //////////////////////// Table

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                showPicker(mode: .Day)
            case 1:
                showPicker(mode: .Hour)
            default:
                showPicker(mode: .Minute)
            }
            tableView.deselectRow(at: indexPath, animated: false)

        } else {
            switch indexPath.row {
            case 0:
                snoozeItem?.wakeOnComment.toggle()
            case 1:
                snoozeItem?.wakeOnMention.toggle()
            default:
                snoozeItem?.wakeOnStatusChange.toggle()
            }
            tableView.reloadData()
        }
    }

    func numberOfSections(in _: UITableView) -> Int {
        2
    }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        3
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SnoozePresetElementCell", for: indexPath)
            if let snoozeItem {
                switch indexPath.row {
                case 0:
                    cell.textLabel?.text = dayLabel
                    cell.detailTextLabel?.text = dayValues[Int(snoozeItem.day)]
                    cell.detailTextLabel?.textColor = detailColor(for: snoozeItem.day)
                case 1:
                    cell.textLabel?.text = hourLabel
                    cell.detailTextLabel?.text = hourValues[Int(snoozeItem.hour)]
                    cell.detailTextLabel?.textColor = detailColor(for: snoozeItem.hour)
                default:
                    cell.textLabel?.text = minuteLabel
                    cell.detailTextLabel?.text = minuteValues[Int(snoozeItem.minute)]
                    cell.detailTextLabel?.textColor = detailColor(for: snoozeItem.minute)
                }
            }
            return cell

        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SnoozePresetWakeupCell", for: indexPath)
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "New comment"
                cell.accessoryType = snoozeItem?.wakeOnComment ?? false ? .checkmark : .none
            case 1:
                cell.textLabel?.text = "Mentioned in a new comment"
                cell.accessoryType = snoozeItem?.wakeOnMention ?? false ? .checkmark : .none
            default:
                cell.textLabel?.text = "Status item update"
                cell.accessoryType = snoozeItem?.wakeOnStatusChange ?? false ? .checkmark : .none
            }
            return cell
        }
    }

    private func detailColor(for number: Int) -> UIColor {
        if typeSelector.selectedSegmentIndex == 0 {
            if number == 0 {
                UIColor.tertiaryLabel
            } else {
                view.tintColor
            }
        } else {
            view.tintColor
        }
    }

    private var hourLabel: String {
        if typeSelector.selectedSegmentIndex == 0 {
            snoozeItem?.hour ?? 0 > 1 ? "Hours" : "Hour"
        } else {
            "Hour"
        }
    }

    private var dayLabel: String {
        if typeSelector.selectedSegmentIndex == 0 {
            snoozeItem?.day ?? 0 > 1 ? "Days" : "Day"
        } else {
            "Day"
        }
    }

    private var minuteLabel: String {
        if typeSelector.selectedSegmentIndex == 0 {
            snoozeItem?.minute ?? 0 > 1 ? "Minutes" : "Minute"
        } else {
            "Minute"
        }
    }

    private var dayValues: [String] {
        var res = [String]()
        if typeSelector.selectedSegmentIndex == 0 {
            res.append("No days")
            res.append("1 day")
            for f in 2 ..< 400 {
                res.append("\(f) days")
            }
        } else {
            res.append(contentsOf: ["Any day", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        }
        return res
    }

    private var hourValues: [String] {
        var res = [String]()
        if typeSelector.selectedSegmentIndex == 0 {
            res.append("No hours")
            res.append("1 hour")
            for f in 2 ..< 24 {
                res.append("\(f) hours")
            }
        } else {
            for f in 0 ..< 24 {
                res.append(String(format: "%02d", f))
            }
        }
        return res
    }

    private var minuteValues: [String] {
        var res = [String]()
        if typeSelector.selectedSegmentIndex == 0 {
            res.append("No minutes")
            res.append("1 minute")
            for f in 2 ..< 60 {
                res.append("\(f) minutes")
            }
        } else {
            for f in 0 ..< 60 {
                res.append(String(format: "%02d", f))
            }
        }
        return res
    }

    ////////////////////////// Picker

    @IBOutlet private var pickerBottom: NSLayoutConstraint!
    @IBOutlet private var pickerShield: UIView!
    @IBOutlet private var pickerNavBar: UINavigationBar!
    @IBOutlet private var picker: UIPickerView!

    private enum SnoozePickerMode {
        case Day
        case Hour
        case Minute
    }

    private var pickerMode: SnoozePickerMode?
    private var pickerValues = [String]()

    private func showPicker(mode: SnoozePickerMode) {
        pickerMode = mode
        switch mode {
        case .Day:
            pickerValues = dayValues
        case .Hour:
            pickerValues = hourValues
        case .Minute:
            pickerValues = minuteValues
        }
        showPicker()
    }

    @IBAction private func pickerCancelSelected(_: UIBarButtonItem) {
        hidePickerAnimated(animate: true)
    }

    @IBAction private func pickerDoneSelected(_: UIBarButtonItem) {
        if let pickerMode {
            let s = picker.selectedRow(inComponent: 0)
            switch pickerMode {
            case .Day:
                snoozeItem?.day = s
            case .Hour:
                snoozeItem?.hour = s
            case .Minute:
                snoozeItem?.minute = s
            }
            updateView()
        }
        hidePickerAnimated(animate: true)
    }

    func pickerView(_: UIPickerView, titleForRow row: Int, forComponent _: Int) -> String? {
        pickerValues[row]
    }

    func pickerView(_: UIPickerView, numberOfRowsInComponent _: Int) -> Int {
        pickerValues.count
    }

    func numberOfComponents(in _: UIPickerView) -> Int {
        1
    }

    func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            typeSelector.selectedSegmentIndex == 0 ? "Snooze an item for a specific duration of time" : "Snooze an item until a specific time or day"
        } else {
            "Wake up an item snoozed by this preset if any of these occur…"
        }
    }

    private var indexForPicker: Int {
        if let pickerMode {
            switch pickerMode {
            case .Day:
                Int(snoozeItem?.day ?? 0)
            case .Hour:
                Int(snoozeItem?.hour ?? 0)
            case .Minute:
                Int(snoozeItem?.minute ?? 0)
            }
        } else {
            0
        }
    }

    private func showPicker() {
        picker.reloadAllComponents()
        picker.selectRow(indexForPicker, inComponent: 0, animated: false)
        pickerBottom.constant = tabBarController?.tabBar.frame.height ?? 0
        UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseInOut) {
            self.pickerShield.alpha = 1.0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.pickerShield.isUserInteractionEnabled = true
        }
    }

    private func hidePickerAnimated(animate: Bool) {
        pickerBottom.constant = -(picker.frame.height + pickerNavBar.frame.height)

        if animate {
            UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseInOut) {
                self.pickerShield.alpha = 0.0
                self.view.layoutIfNeeded()
            } completion: { _ in
                self.pickerShield.isUserInteractionEnabled = false
            }
        } else {
            pickerShield.alpha = 0.0
            pickerShield.isUserInteractionEnabled = false
        }
    }
}
