
import UIKit
import CoreData

final class ServersViewController: UITableViewController {

	private var selectedServerId: NSManagedObjectID?
	private var allServers: [ApiServer]!
	private var resetFormatter: NSDateFormatter!

	@IBAction func doneSelected() {
		if app.preferencesDirty {
			app.startRefresh()
		}
		dismissViewControllerAnimated(true, completion: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		
		resetFormatter = NSDateFormatter()
		resetFormatter.doesRelativeDateFormatting = true
		resetFormatter.timeStyle = NSDateFormatterStyle.ShortStyle
		resetFormatter.dateStyle = NSDateFormatterStyle.ShortStyle

		clearsSelectionOnViewWillAppear = true
		NSNotificationCenter.defaultCenter().addObserver(tableView, selector: Selector("reloadData"), name: REFRESH_ENDED_NOTIFICATION, object: nil)
	}

	deinit {
		if tableView != nil {
			NSNotificationCenter.defaultCenter().removeObserver(tableView)
		}
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		allServers = ApiServer.allApiServersInMoc(mainObjectContext)
		tableView.reloadData()
	}

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return allServers.count
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("ServerCell", forIndexPath: indexPath) 
		let a = allServers[indexPath.row]
		if (a.authToken ?? "").isEmpty {
			cell.textLabel?.textColor = UIColor.redColor()
			cell.textLabel?.text = (a.label ?? "") + " (needs token!)"
		} else if !a.syncIsGood {
			cell.textLabel?.textColor = UIColor.redColor()
			cell.textLabel?.text = (a.label ?? "") + " (last sync failed)"
		} else {
			cell.textLabel?.textColor = UIColor.darkTextColor()
			cell.textLabel?.text = a.label
		}
		if a.requestsLimit==nil || a.requestsLimit!.doubleValue==0.0 {
			cell.detailTextLabel?.text = nil
		} else
		{
			let total = a.requestsLimit?.doubleValue ?? 0
			let used = total - (a.requestsRemaining?.doubleValue ?? 0)
			if a.resetDate != nil {
				cell.detailTextLabel?.text = String(format:"%.01f%% API used (%.0f / %.0f requests)\nNext reset: %@", 100*used/total, used, total, resetFormatter.stringFromDate(a.resetDate!))
			} else {
				cell.detailTextLabel?.text = String(format:"%.01f%% API used (%.0f / %.0f requests)", 100*used/total, used, total)
			}
		}
		return cell
	}

	override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
		return true
	}

	override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
		if editingStyle == UITableViewCellEditingStyle.Delete {
			let a = allServers[indexPath.row]
			allServers.removeAtIndex(indexPath.row)
			mainObjectContext.deleteObject(a)
			DataManager.saveDB()
			tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Fade)
		}
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		let a = allServers[indexPath.row]
		selectedServerId = a.objectID
		performSegueWithIdentifier("editServer", sender: self)
	}

	@IBAction func newServer() {
		performSegueWithIdentifier("editServer", sender: self)
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let sd = segue.destinationViewController as? ServerDetailViewController {
			sd.serverId = selectedServerId
			selectedServerId = nil
		}
	}
}
