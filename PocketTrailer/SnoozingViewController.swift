
import UIKit

final class SnoozingViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, PickerViewControllerDelegate {

	@IBOutlet weak var table: UITableView!

	private var settingsChangedTimer: PopTimer!

	override func viewDidLoad() {
		super.viewDidLoad()
		settingsChangedTimer = PopTimer(timeInterval: 1.0) {
			DataManager.postProcessAllItems()
			DataManager.saveDB()
		}
	}

	@IBAction func done(_ sender: UIBarButtonItem) {
		if preferencesDirty { _ = app.startRefresh() }
		dismiss(animated: true, completion: nil)
	}

	@IBAction func addNew(_ sender: UIBarButtonItem) {
		performSegue(withIdentifier: "showSnoozeEditor", sender: nil)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		table.reloadData()
	}

	func numberOfSections(in tableView: UITableView) -> Int {
		if SnoozePreset.allSnoozePresetsInMoc(mainObjectContext).count > 0 {
			return 4
		} else {
			return 3
		}
	}

	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == 0 || section == 1 {
			return 1
		} else if section == 2 {
			return 3
		} else {
			return SnoozePreset.allSnoozePresetsInMoc(mainObjectContext).count
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
		} else if indexPath.section == 2 {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "New comment"
				cell.accessoryType = Settings.snoozeWakeOnComment ? .checkmark : .none
			case 1:
				cell.textLabel?.text = "Mentioned in a new comment"
				cell.accessoryType = Settings.snoozeWakeOnMention ? .checkmark : .none
			default:
				cell.textLabel?.text = "Status item update"
				cell.accessoryType = Settings.snoozeWakeOnStatusUpdate ? .checkmark : .none
			}
		} else {
			let s = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)[indexPath.row]
			cell.textLabel?.text = s.listDescription
			cell.accessoryType = .disclosureIndicator
		}
		return cell
	}

	func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == 0 {
			return "You can create presets here that can be used to 'snooze' items for a specific time duration, until a date, or if a specific event occurs."
		} else if section == 1 {
			return "Automatically snooze items after a specific amount of time..."
		} else if section == 2 {
			return "Wake up a snoozing item immediately if any of these occur..."
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
			performSegue(withIdentifier: "showPicker", sender: self)
		} else if indexPath.section == 2 {
			switch indexPath.row {
			case 0:
				Settings.snoozeWakeOnComment = !Settings.snoozeWakeOnComment
			case 1:
				Settings.snoozeWakeOnMention = !Settings.snoozeWakeOnMention
			default:
				Settings.snoozeWakeOnStatusUpdate = !Settings.snoozeWakeOnStatusUpdate
			}
			tableView.reloadData()
		} else {
			let s = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)[indexPath.row]
			performSegue(withIdentifier: "showSnoozeEditor", sender: s)
		}
	}

	override func prepare(for segue: UIStoryboardSegue, sender: AnyObject?) {
		if let d = segue.destination as? PickerViewController {
			d.delegate = self
			d.title = "Auto Snooze Items After"
			let count = stride(from: 2, to: 9000, by: 1).map { "\($0) days" }
			d.values = ["Never", "1 day"] + count
			d.previousValue = Settings.autoSnoozeDuration
		} else if let d = segue.destination as? SnoozingEditorViewController {
			if let s = sender as? SnoozePreset {
				d.isNew = false
				d.snoozeItem = s
			} else {
				d.isNew = true
				d.snoozeItem = SnoozePreset.newSnoozePresetInMoc(mainObjectContext)
			}
		}
	}

	func pickerViewController(picker: PickerViewController, didSelectIndexPath: IndexPath) {
		Settings.autoSnoozeDuration = didSelectIndexPath.row
		table.reloadData()
		for p in DataItem.allItemsOfType("PullRequest", inMoc: mainObjectContext) as! [PullRequest] {
			p.wakeIfAutoSnoozed()
		}
		for i in DataItem.allItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue] {
			i.wakeIfAutoSnoozed()
		}
		DataManager.postProcessAllItems()
		DataManager.saveDB()
		popupManager.getMasterController().updateStatus()
	}

	override func viewDidAppear(_ animated: Bool) {
		super.viewDidAppear(animated)
		if let i = table.indexPathForSelectedRow {
			table.deselectRow(at: i, animated: true)
		}
	}
}
