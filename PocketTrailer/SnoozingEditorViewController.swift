
import UIKit

final class SnoozingEditorViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIPickerViewDataSource, UIPickerViewDelegate {

	@IBOutlet weak var table: UITableView!
	@IBOutlet weak var descriptionLabel: UILabel!

	var snoozeItem: SnoozePreset?
	var isNew = false

	@IBOutlet weak var typeSelector: UISegmentedControl!

	@IBAction func deleteSelected(_ sender: UIBarButtonItem) {

		if let s = snoozeItem {
			let appliedCount = s.appliedToIssues.count + s.appliedToPullRequests.count
			if appliedCount > 0 {

				let a = UIAlertController(title: "Delete Snooze Preset",
				                          message: "You have \(appliedCount) items that have been snoozed using this preset. What would you like to do with them after deleting this preset?",
				                          preferredStyle: .alert)

				a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Wake Them Up", style: .destructive) { [weak self] action in
					s.wakeUpAllAssociatedItems()
					self?.deletePreset()
				})
				a.addAction(UIAlertAction(title: "Keep Them Snoozed", style: .destructive) { [weak self] action in
					self?.deletePreset()
				})

				present(a, animated: true, completion: nil)

			} else {

				let a = UIAlertController(title: "Delete Snooze Preset",
				                          message: "Are you sure you want to remove this preset from your list?",
				                          preferredStyle: .alert)

				a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] action in
					self?.deletePreset()
				})
				
				present(a, animated: true, completion: nil)
				
			}
		}
	}

	private func deletePreset() {
		if let s = snoozeItem {
			mainObjectContext.delete(s)
		}
		_ = navigationController?.popViewController(animated: true)
	}

	@IBAction func upSelected(_ sender: UIBarButtonItem) {
		if let this = snoozeItem {
			let all = SnoozePreset.allSnoozePresets(in: mainObjectContext)
			if let index = all.index(of: this), index > 0 {
				let other = all[index-1]
				other.sortOrder = Int64(index)
				this.sortOrder = Int64(index-1)
				updateView()
			}
		}
	}

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		DataManager.saveDB()
	}

	@IBAction func downSelected(_ sender: UIBarButtonItem) {
		if let this = snoozeItem {
			let all = SnoozePreset.allSnoozePresets(in: mainObjectContext)
			if let index = all.index(of: this), index < all.count-1 {
				let other = all[index+1]
				other.sortOrder = Int64(index)
				this.sortOrder = Int64(index+1)
				updateView()
			}
		}
	}

	@IBAction func typeSelectorChanged(_ sender: UISegmentedControl) {
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
		let total = SnoozePreset.allSnoozePresets(in: mainObjectContext).count
		let desc = S(snoozeItem?.listDescription)
		if total > 1 {
			let pos = (snoozeItem?.sortOrder ?? 0)+1
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
				snoozeItem?.wakeOnComment = !(snoozeItem?.wakeOnComment ?? false)
			case 1:
				snoozeItem?.wakeOnMention = !(snoozeItem?.wakeOnMention ?? false)
			default:
				snoozeItem?.wakeOnStatusChange = !(snoozeItem?.wakeOnStatusChange ?? false)
			}
			tableView.reloadData()
		}
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		return 2
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 3
	}

	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		if indexPath.section == 0 {
			let cell = tableView.dequeueReusableCell(withIdentifier: "SnoozePresetElementCell", for: indexPath)
			if let s = snoozeItem {
				switch indexPath.row {
				case 0:
					cell.textLabel?.text = dayLabel()
					cell.detailTextLabel?.text = dayValues()[Int(s.day)]
					cell.detailTextLabel?.textColor = detailColor(s.day)
				case 1:
					cell.textLabel?.text = hourLabel()
					cell.detailTextLabel?.text = hourValues()[Int(s.hour)]
					cell.detailTextLabel?.textColor = detailColor(s.hour)
				default:
					cell.textLabel?.text = minuteLabel()
					cell.detailTextLabel?.text = minuteValues()[Int(s.minute)]
					cell.detailTextLabel?.textColor = detailColor(s.minute)
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

	private func detailColor(_ n: Int64) -> UIColor {
		if typeSelector.selectedSegmentIndex==0 {
			if n == 0 {
				return UIColor.lightGray
			} else {
				return view.tintColor
			}
		} else {
			return view.tintColor
		}
	}

	private func hourLabel() -> String {
		if typeSelector.selectedSegmentIndex == 0 {
			return snoozeItem?.hour ?? 0 > 1 ? "Hours" : "Hour"
		} else {
			return "Hour"
		}
	}

	private func dayLabel() -> String {
		if typeSelector.selectedSegmentIndex == 0 {
			return snoozeItem?.day ?? 0 > 1 ? "Days" : "Day"
		} else {
			return "Day"
		}
	}

	private func minuteLabel() -> String {
		if typeSelector.selectedSegmentIndex == 0 {
			return snoozeItem?.minute ?? 0 > 1 ? "Minutes" : "Minute"
		} else {
			return "Minute"
		}
	}

	private func dayValues() -> [String] {
		var res = [String]()
		if typeSelector.selectedSegmentIndex==0 {
			res.append("No days")
			res.append("1 day")
			for f in 2..<400 {
				res.append("\(f) days")
			}
		} else {
			res.append(contentsOf: ["Any day", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
		}
		return res
	}

	private func hourValues() -> [String] {
		var res = [String]()
		if typeSelector.selectedSegmentIndex==0 {
			res.append("No hours")
			res.append("1 hour")
			for f in 2..<24 {
				res.append("\(f) hours")
			}
		} else {
			for f in 0..<24 {
				res.append(String(format: "%02d", f))
			}
		}
		return res
	}

	private func minuteValues() -> [String] {
		var res = [String]()
		if typeSelector.selectedSegmentIndex==0 {
			res.append("No minutes")
			res.append("1 minute")
			for f in 2..<60 {
				res.append("\(f) minutes")
			}
		} else {
			for f in 0..<60 {
				res.append(String(format: "%02d", f))
			}
		}
		return res
	}

	////////////////////////// Picker

	@IBOutlet weak var pickerBottom: NSLayoutConstraint!
	@IBOutlet weak var pickerShield: UIView!
	@IBOutlet weak var pickerNavBar: UINavigationBar!
	@IBOutlet weak var picker: UIPickerView!

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
			pickerValues = dayValues()
		case .Hour:
			pickerValues = hourValues()
		case .Minute:
			pickerValues = minuteValues()
		}
		showPicker()
	}

	@IBAction func pickerCancelSelected(_ sender: UIBarButtonItem) {
		hidePickerAnimated(animate: true)
	}

	@IBAction func pickerDoneSelected(_ sender: UIBarButtonItem) {
		if let p = pickerMode {
			let s = picker.selectedRow(inComponent: 0)
			switch p {
			case .Day:
				snoozeItem?.day = Int64(s)
			case .Hour:
				snoozeItem?.hour = Int64(s)
			case .Minute:
				snoozeItem?.minute = Int64(s)
			}
			updateView()
		}
		hidePickerAnimated(animate: true)
	}

	func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return pickerValues[row]
	}

	func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
		return pickerValues.count
	}

	func numberOfComponents(in pickerView: UIPickerView) -> Int {
		return 1
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == 0 {
			return typeSelector.selectedSegmentIndex == 0 ? "Snooze an item for a specific duration of time" : "Snooze an item until a specific time or day"
		} else {
			return "Wake up an item snoozed by this preset if any of these occur..."
		}
	}

	private func indexForPicker() -> Int {
		if let p = pickerMode {
			switch p {
			case .Day:
				return Int(snoozeItem?.day ?? 0)
			case .Hour:
				return Int(snoozeItem?.hour ?? 0)
			case .Minute:
				return Int(snoozeItem?.minute ?? 0)
			}
		} else {
			return 0
		}
	}

	private func showPicker() {
		picker.reloadAllComponents()
		picker.selectRow(indexForPicker(), inComponent: 0, animated: false)
		pickerBottom.constant = tabBarController?.tabBar.frame.size.height ?? 0
		UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseInOut, animations: { [weak self] in
			self?.pickerShield.alpha = 1.0
			self?.view.layoutIfNeeded()
		}) { [weak self] finished in
			self?.pickerShield.isUserInteractionEnabled = true
		}
	}

	private func hidePickerAnimated(animate: Bool) {
		pickerBottom.constant = -(picker.frame.size.height+pickerNavBar.frame.size.height)

		if animate {
			UIView.animate(withDuration: 0.3, delay: 0.0, options: .curveEaseInOut, animations: { [weak self] in
				self?.pickerShield.alpha = 0.0
				self?.view.layoutIfNeeded()
			}) { [weak self] finished in
				self?.pickerShield.isUserInteractionEnabled = false
			}
		} else {
			pickerShield.alpha = 0.0
			pickerShield.isUserInteractionEnabled = false
		}
	}

}
