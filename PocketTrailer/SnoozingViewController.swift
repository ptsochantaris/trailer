
import UIKit

final class SnoozingViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

	@IBOutlet weak var table: UITableView!

	private var settingsChangedTimer: PopTimer!

	override func viewDidLoad() {
		super.viewDidLoad()
		settingsChangedTimer = PopTimer(timeInterval: 1.0) {
			DataManager.postProcessAllItems()
			DataManager.saveDB()
		}
	}

	@IBAction func done(sender: UIBarButtonItem) {
		if preferencesDirty { app.startRefresh() }
		dismissViewControllerAnimated(true, completion: nil)
	}

	@IBAction func addNew(sender: UIBarButtonItem) {
		performSegueWithIdentifier("showSnoozeEditor", sender: nil)
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		table.reloadData()
	}

	func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		if SnoozePreset.allSnoozePresetsInMoc(mainObjectContext).count > 0 {
			return 3
		} else {
			return 2
		}
	}

	func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		if section == 0 {
			return 1
		} else if section == 1 {
			return 3
		} else {
			return SnoozePreset.allSnoozePresetsInMoc(mainObjectContext).count
		}
	}

	func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("SnoozeOptionCell", forIndexPath: indexPath)
		if indexPath.section == 0 {
			cell.textLabel?.text = "Hide snoozed items"
			cell.accessoryType = Settings.hideSnoozedItems ? .Checkmark : .None
		} else if indexPath.section == 1 {
			switch indexPath.row {
			case 0:
				cell.textLabel?.text = "New comment"
				cell.accessoryType = Settings.snoozeWakeOnComment ? .Checkmark : .None
			case 1:
				cell.textLabel?.text = "Mentioned in a new comment"
				cell.accessoryType = Settings.snoozeWakeOnMention ? .Checkmark : .None
			default:
				cell.textLabel?.text = "Status item update"
				cell.accessoryType = Settings.snoozeWakeOnStatusUpdate ? .Checkmark : .None
			}
		} else {
			let s = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)[indexPath.row]
			cell.textLabel?.text = s.listDescription
			cell.accessoryType = .DisclosureIndicator
		}
		return cell
	}

	func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section == 0 {
			return nil
		} else if section == 1 {
			return "Wake up a snoozing item immediately if any of these occur..."
		} else {
			return "Existing presets:"
		}
	}

	func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		if indexPath.section == 0 {
			Settings.hideSnoozedItems = !Settings.hideSnoozedItems
			tableView.reloadData()
			settingsChangedTimer.push()			
		} else if indexPath.section == 1 {
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
			performSegueWithIdentifier("showSnoozeEditor", sender: s)
		}
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let d = segue.destinationViewController as? SnoozingEditorViewController {
			if let s = sender as? SnoozePreset {
				d.isNew = false
				d.snoozeItem = s
			} else {
				d.isNew = true
				d.snoozeItem = SnoozePreset.newSnoozePresetInMoc(mainObjectContext)
			}
		}
	}

	override func viewDidAppear(animated: Bool) {
		super.viewDidAppear(animated)
		if let i = table.indexPathForSelectedRow {
			table.deselectRowAtIndexPath(i, animated: true)
		}
	}
}
