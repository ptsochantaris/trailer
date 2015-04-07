
import UIKit
import CoreData

class RespositoriesViewController: UITableViewController, UITextFieldDelegate, NSFetchedResultsControllerDelegate {

	// Filtering
	private var searchField: UITextField?
	private var searchTimer: PopTimer?
	private var _fetchedResultsController: NSFetchedResultsController?

	@IBOutlet weak var actionsButton: UIBarButtonItem!

	@IBAction func done(sender: UIBarButtonItem) {
		if app.preferencesDirty {
			app.startRefresh()
		}
		dismissViewControllerAnimated(true, completion: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		searchField = UITextField(frame: CGRectMake(10, 10, view.bounds.size.width-20, 31))
		searchField!.placeholder = "Filter..."
		searchField!.returnKeyType = UIReturnKeyType.Search
		searchField!.font = UIFont.systemFontOfSize(18)
		searchField!.borderStyle = UITextBorderStyle.RoundedRect
		searchField!.contentVerticalAlignment = UIControlContentVerticalAlignment.Center
		searchField!.clearButtonMode = UITextFieldViewMode.Always
		searchField!.autocapitalizationType = UITextAutocapitalizationType.None
		searchField!.autocorrectionType = UITextAutocorrectionType.No
		searchField!.delegate = self
		searchField!.autoresizingMask = UIViewAutoresizing.FlexibleWidth

		searchTimer = PopTimer(timeInterval: 0.5, callback: { [weak self] in
			self!.reloadData()
		})

		let searchHolder = UIView(frame: CGRectMake(0, 0, view.bounds.size.width, 51))
		searchHolder.addSubview(searchField!)
		searchHolder.autoresizesSubviews = true
		searchHolder.autoresizingMask = UIViewAutoresizing.FlexibleWidth
		tableView.tableHeaderView = searchHolder
	}

	override func viewDidAppear(animated: Bool) {
		actionsButton.enabled = ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext)
		if actionsButton.enabled && fetchedResultsController.fetchedObjects?.count==0 {
			refreshList()
		}
		super.viewDidAppear(animated)
	}

	@IBAction func actionSelected(sender: UIBarButtonItem) {
		let a = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.ActionSheet)
		a.addAction(UIAlertAction(title: "Refresh List", style: UIAlertActionStyle.Destructive, handler: { [weak self] action in
			self!.refreshList()
		}))
		a.addAction(UIAlertAction(title: "Hide All", style: UIAlertActionStyle.Default, handler: { [weak self] action in
			for r in self!.fetchedResultsController.fetchedObjects as! [Repo] {
				r.hidden = true
				r.dirty = false
			}
			app.preferencesDirty = true
		}))
		a.addAction(UIAlertAction(title: "Show All", style: UIAlertActionStyle.Default, handler: { [weak self] action in
			for r in self!.fetchedResultsController.fetchedObjects as! [Repo] {
				r.hidden = false
				r.resetSyncState()
			}
			app.preferencesDirty = true
		}))
		a.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: nil))
		a.popoverPresentationController?.barButtonItem = sender
		presentViewController(a, animated: true, completion: nil)
	}
	
	private func refreshList() {
		let originalName = navigationItem.title
		navigationItem.title = "Loading..."
		actionsButton.enabled = false
		tableView.userInteractionEnabled = false
		tableView.alpha = 0.5

		let tempContext = DataManager.tempContext()
		api.fetchRepositoriesToMoc(tempContext, callback: { [weak self] in
			if ApiServer.shouldReportRefreshFailureInMoc(tempContext) {
				var errorServers = [String]()
				for apiServer in ApiServer.allApiServersInMoc(tempContext) {
					if apiServer.goodToGo && !apiServer.syncIsGood {
						errorServers.append(apiServer.label ?? "Untitled Server")
					}
				}
				let serverNames = ", ".join(errorServers)
				let message = "Could not refresh repository list from \(serverNames), please ensure that the tokens you are using are valid"
				UIAlertView(title: "Error", message: message, delegate: nil, cancelButtonTitle: "OK").show()
			} else {
				tempContext.save(nil)
			}
			self!.navigationItem.title = originalName
			self!.actionsButton.enabled = ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext)
			self!.tableView.alpha = 1.0
			self!.tableView.userInteractionEnabled = true
			app.preferencesDirty = true
		})
	}

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return fetchedResultsController.sections?.count ?? 0
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		let sectionInfo = fetchedResultsController.sections?[section] as? NSFetchedResultsSectionInfo
		return sectionInfo?.numberOfObjects ?? 0
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! UITableViewCell
		configureCell(cell, atIndexPath: indexPath)
		return cell
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		if let repo = fetchedResultsController.objectAtIndexPath(indexPath) as? Repo {
			let hideNow = !(repo.hidden?.boolValue ?? false)
			repo.hidden = hideNow
			repo.dirty = !hideNow
			DataManager.saveDB()
		}
		tableView.deselectRowAtIndexPath(indexPath, animated: false)
		app.preferencesDirty = true
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section==1 {
			return "Forked Repos"
		} else {
			let repo = fetchedResultsController.objectAtIndexPath(NSIndexPath(forRow: 0, inSection: section)) as! Repo
			if (repo.fork?.boolValue ?? false) {
				return "Forked Repos"
			} else {
				return "Parent Repos"
			}
		}
	}

	private var fetchedResultsController: NSFetchedResultsController {
		if let f = _fetchedResultsController {
			return f
		}

		let fetchRequest = NSFetchRequest(entityName: "Repo")
		if !(searchField!.text.isEmpty) {
			fetchRequest.predicate = NSPredicate(format: "fullName contains [cd] %@", searchField!.text)
		}
		fetchRequest.fetchBatchSize = 20
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "fork", ascending: true), NSSortDescriptor(key: "fullName", ascending: true)]

		let fc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: mainObjectContext, sectionNameKeyPath: "fork", cacheName: nil)
		fc.delegate = self
		_fetchedResultsController = fc

		var error: NSError?
		if !fc.performFetch(&error) {
			DLog("Fetch error %@, %@", error!, error!.userInfo)
			abort()
		}

		return fc
	}

	func controllerWillChangeContent(controller: NSFetchedResultsController) {
		tableView.beginUpdates()
	}

	func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
		switch(type) {
		case .Insert:
			tableView.insertSections(NSIndexSet(index: sectionIndex), withRowAnimation: UITableViewRowAnimation.Automatic)
		case .Delete:
			tableView.deleteSections(NSIndexSet(index: sectionIndex), withRowAnimation: UITableViewRowAnimation.Automatic)
		case .Update:
			tableView.reloadSections(NSIndexSet(index: sectionIndex), withRowAnimation: UITableViewRowAnimation.Automatic)
		default:
			break
		}
	}

	func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {

		switch(type) {
		case .Insert:
			tableView.insertRowsAtIndexPaths([newIndexPath ?? indexPath!], withRowAnimation: UITableViewRowAnimation.Automatic)
		case .Delete:
			tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation:UITableViewRowAnimation.Automatic)
		case .Update:
			if let cell = tableView.cellForRowAtIndexPath(newIndexPath ?? indexPath!) {
				configureCell(cell, atIndexPath: newIndexPath ?? indexPath!)
			}
		case .Move:
			tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation:UITableViewRowAnimation.Automatic)
			if let n = newIndexPath {
				tableView.insertRowsAtIndexPaths([n], withRowAnimation:UITableViewRowAnimation.Automatic)
			}
		}
	}

	func controllerDidChangeContent(controller: NSFetchedResultsController) {
		tableView.endUpdates()
	}

	private func configureCell(cell: UITableViewCell, atIndexPath: NSIndexPath) {
		let repo = fetchedResultsController.objectAtIndexPath(atIndexPath) as! Repo
		let fullName = repo.fullName ?? "(Untitled Repo)"
		let text = (repo.inaccessible?.boolValue ?? false) ? (fullName + " (inaccessible)") : fullName
		cell.textLabel?.text = text
		if (repo.hidden?.boolValue ?? false) {
			cell.accessoryView = makeX()
			cell.textLabel?.textColor = UIColor.lightGrayColor()
			cell.accessibilityLabel = "Hidden: " + text
		} else {
			cell.accessoryView = nil
			cell.textLabel?.textColor = UIColor.darkTextColor()
			cell.accessibilityLabel = text
		}
	}

	private func makeX() -> UIView {
		let x = UILabel(frame: CGRectMake(0, 0, 16, 16))
		x.textColor = UIColor.redColor()
		x.font = UIFont.systemFontOfSize(14)
		x.text = "X"
		return x
	}

	///////////////////////////// filtering

	private func reloadData() {
		let currentIndexes = NSIndexSet(indexesInRange: NSMakeRange(0, fetchedResultsController.sections?.count ?? 0))

		_fetchedResultsController = nil

		let dataIndexes = NSIndexSet(indexesInRange: NSMakeRange(0, fetchedResultsController.sections?.count ?? 0))

		let removedIndexes = currentIndexes.indexesPassingTest { (idx, _) -> Bool in
			return !dataIndexes.containsIndex(idx)
		}
		let addedIndexes = dataIndexes.indexesPassingTest { (idx, _) -> Bool in
			return !currentIndexes.containsIndex(idx)
		}
		let untouchedIndexes = dataIndexes.indexesPassingTest { (idx, _) -> Bool in
			return !(removedIndexes.containsIndex(idx) || addedIndexes.containsIndex(idx))
		}

		tableView.beginUpdates()
		if removedIndexes.count > 0 {
			tableView.deleteSections(removedIndexes, withRowAnimation:UITableViewRowAnimation.Automatic)
		}
		if untouchedIndexes.count > 0 {
			tableView.reloadSections(untouchedIndexes, withRowAnimation:UITableViewRowAnimation.Automatic)
		}
		if addedIndexes.count > 0 {
			tableView.insertSections(addedIndexes, withRowAnimation:UITableViewRowAnimation.Automatic)
		}
		tableView.endUpdates()
	}

	override func scrollViewWillBeginDragging(scrollView: UIScrollView) {
		if searchField!.isFirstResponder() {
			searchField!.resignFirstResponder()
		}
	}

	func textFieldShouldClear(textField: UITextField) -> Bool {
		searchTimer?.push()
		return true
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			textField.resignFirstResponder()
		} else {
			searchTimer?.push()
		}
		return true
	}
}
