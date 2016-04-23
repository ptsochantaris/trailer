
import UIKit

final class SnoozingEditorViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, UIPickerViewDataSource, UIPickerViewDelegate {

	@IBOutlet weak var table: UITableView!
	@IBOutlet weak var descriptionLabel: UILabel!

	var snoozeItem: SnoozePreset?
	var isNew: Bool = false

	@IBOutlet weak var typeSelector: UISegmentedControl!

	@IBAction func deleteSelected(sender: UIBarButtonItem) {
		let a = UIAlertController(title: "Delete Snooze Preset",
		                          message: "Are you sure you want to remove this preset from your list?",
		                          preferredStyle: .Alert)

		a.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
		a.addAction(UIAlertAction(title: "Delete", style: .Destructive) { [weak self] action in
			self?.deletePreset()
		})

		presentViewController(a, animated: true, completion: nil)
	}

	private func deletePreset() {
		if let s = snoozeItem {
			mainObjectContext.deleteObject(s)
		}
		navigationController?.popViewControllerAnimated(true)
	}

	@IBAction func upSelected(sender: UIBarButtonItem) {
		if let this = snoozeItem {
			let all = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)
			if let index = all.indexOf(this) where index > 0 {
				let other = all[index-1]
				other.sortOrder = NSNumber(integer: index)
				this.sortOrder = NSNumber(integer: index-1)
				updateView()
			}
		}
	}

	override func viewDidDisappear(animated: Bool) {
		super.viewDidDisappear(animated)
		DataManager.saveDB()
	}

	@IBAction func downSelected(sender: UIBarButtonItem) {
		if let this = snoozeItem {
			let all = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)
			if let index = all.indexOf(this) where index < all.count-1 {
				let other = all[index+1]
				other.sortOrder = NSNumber(integer: index)
				this.sortOrder = NSNumber(integer: index+1)
				updateView()
			}
		}
	}

	@IBAction func typeSelectorChanged(sender: UISegmentedControl) {
		updateView()
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		title = isNew ? "New" : "Edit"
		typeSelector.selectedSegmentIndex = (snoozeItem?.duration.boolValue ?? false) ? 0 : 1
		updateView()
		hidePickerAnimated(false)
	}

	private func updateView() {
		table.reloadData()
		snoozeItem?.duration = NSNumber(bool: typeSelector.selectedSegmentIndex==0)
		let total = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext).count
		let desc = snoozeItem?.listDescription() ?? ""
		if total > 1 {
			let pos = (snoozeItem?.sortOrder.integerValue ?? 0)+1
			descriptionLabel.text = "\"\(desc)\"\n\(pos) of \(total) on the snooze menu"
		} else {
			descriptionLabel.text = "\"\(desc)\""
		}
	}

	//////////////////////// Table

	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		switch indexPath.row {
		case 0:
			showPicker(.Day)
		case 1:
			showPicker(.Hour)
		default:
			showPicker(.Minute)
		}
		tableView.deselectRowAtIndexPath(indexPath, animated: false)
	}

	func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 1
	}

	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return 3
	}

	func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("SnoozePresetElementCell", forIndexPath: indexPath)
		if let s = snoozeItem {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = dayLabel()
				cell.detailTextLabel?.text = dayValues()[s.day?.integerValue ?? 0]
				cell.detailTextLabel?.textColor = detailColor(s.day)
			case 1:
				cell.textLabel?.text = hourLabel()
				cell.detailTextLabel?.text = hourValues()[s.hour?.integerValue ?? 0]
				cell.detailTextLabel?.textColor = detailColor(s.hour)
			default:
				cell.textLabel?.text = minuteLabel()
				cell.detailTextLabel?.text = minuteValues()[s.minute?.integerValue ?? 0]
				cell.detailTextLabel?.textColor = detailColor(s.minute)
			}
		}
		return cell
	}

	private func detailColor(n: NSNumber?) -> UIColor {
		if typeSelector.selectedSegmentIndex==0 {
			if n?.integerValue ?? 0 == 0 {
				return UIColor.lightGrayColor()
			} else {
				return view.tintColor
			}
		} else {
			return view.tintColor
		}
	}

	private func hourLabel() -> String {
		if typeSelector.selectedSegmentIndex == 0 {
			return snoozeItem?.hour?.integerValue ?? 0 > 1 ? "Hours" : "Hour"
		} else {
			return "Hour"
		}
	}

	private func dayLabel() -> String {
		if typeSelector.selectedSegmentIndex == 0 {
			return snoozeItem?.day?.integerValue ?? 0 > 1 ? "Days" : "Day"
		} else {
			return "Day"
		}
	}

	private func minuteLabel() -> String {
		if typeSelector.selectedSegmentIndex == 0 {
			return snoozeItem?.minute?.integerValue ?? 0 > 1 ? "Minutes" : "Minute"
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
			res.appendContentsOf(["Any day", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
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

	@IBAction func pickerCancelSelected(sender: UIBarButtonItem) {
		hidePickerAnimated(true)
	}

	@IBAction func pickerDoneSelected(sender: UIBarButtonItem) {
		if let p = pickerMode {
			let s = picker.selectedRowInComponent(0)
			switch p {
			case .Day:
				snoozeItem?.day = (s>0) ? NSNumber(integer: s) : nil
			case .Hour:
				snoozeItem?.hour = (s>0) ? NSNumber(integer: s) : nil
			case .Minute:
				snoozeItem?.minute = (s>0) ? NSNumber(integer: s) : nil
			}
			updateView()
		}
		hidePickerAnimated(true)
	}

	func pickerView(pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
		return pickerValues[row]
	}

	func pickerView(pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
		return pickerValues.count
	}

	func numberOfComponentsInPickerView(pickerView: UIPickerView) -> Int {
		return 1
	}

	private func indexForPicker() -> Int {
		if let p = pickerMode {
			switch p {
			case .Day:
				return snoozeItem?.day?.integerValue ?? 0
			case .Hour:
				return snoozeItem?.hour?.integerValue ?? 0
			case .Minute:
				return snoozeItem?.minute?.integerValue ?? 0
			}
		} else {
			return 0
		}
	}

	private func showPicker() {
		picker.reloadAllComponents()
		picker.selectRow(indexForPicker(), inComponent: 0, animated: false)
		pickerBottom.constant = tabBarController?.tabBar.frame.size.height ?? 0
		UIView.animateWithDuration(0.3, delay: 0.0, options: .CurveEaseInOut, animations: { [weak self] in
			self?.pickerShield.alpha = 1.0
			self?.view.layoutIfNeeded()
		}) { [weak self] finished in
			self?.pickerShield.userInteractionEnabled = true
		}
	}

	private func hidePickerAnimated(animate: Bool) {
		pickerBottom.constant = -(picker.frame.size.height+pickerNavBar.frame.size.height)

		if animate {
			UIView.animateWithDuration(0.3, delay: 0.0, options: .CurveEaseInOut, animations: { [weak self] in
				self?.pickerShield.alpha = 0.0
				self?.view.layoutIfNeeded()
			}) { [weak self] finished in
				self?.pickerShield.userInteractionEnabled = false
			}
		} else {
			pickerShield.alpha = 0.0
			pickerShield.userInteractionEnabled = false
		}
	}

}
