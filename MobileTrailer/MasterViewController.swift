
import UIKit
import CoreData

class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate, UITextFieldDelegate, UIActionSheetDelegate, UITabBarControllerDelegate {

	private var detailViewController: DetailViewController!
	private var _fetchedResultsController: NSFetchedResultsController?

	// Filtering
	private let searchField: UITextField
	private let searchTimer: PopTimer?

	// Refreshing
	private var refreshOnRelease: Bool

	@IBAction func editSelected(sender: UIBarButtonItem ) {
		if traitCollection.userInterfaceIdiom==UIUserInterfaceIdiom.Pad && UIInterfaceOrientationIsPortrait(UIApplication.sharedApplication().statusBarOrientation) {
			let a = UIAlertController(title: "Action", message: nil, preferredStyle: UIAlertControllerStyle.Alert)

			a.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: { action in
				a.dismissViewControllerAnimated(true, completion: nil)
			}))

			a.addAction(UIAlertAction(title: "Mark all as read", style: UIAlertActionStyle.Destructive, handler: { [weak self] action in
				self!.markAllAsRead()
			}))
			a.addAction(UIAlertAction(title: "Remove all merged", style:UIAlertActionStyle.Default, handler: { [weak self] action in
				self!.removeAllMerged()
			}))
			a.addAction(UIAlertAction(title: "Remove all closed", style:UIAlertActionStyle.Default, handler: { [weak self] action in
				self!.removeAllClosed()
			}))
			presentViewController(a, animated: true, completion: nil)
		}
		else
		{
			let a = UIActionSheet(title: "Action",
				delegate:self,
				cancelButtonTitle: "Cancel",
				destructiveButtonTitle: "Mark all as read",
				otherButtonTitles: "Remove all merged",  "Remove all closed")

			a.showFromBarButtonItem(sender, animated: true)
		}
	}

	func actionSheet(actionSheet: UIActionSheet, willDismissWithButtonIndex buttonIndex: Int) {
		switch buttonIndex {
		case 0:
			markAllAsRead()
		case 2:
			removeAllMerged()
		case 3:
			removeAllClosed()
		default:
			break
		}
	}

	private func tryRefresh() {
		refreshOnRelease = false

		if api.reachability.currentReachabilityStatus()==NetworkStatus.NotReachable {
			UIAlertView(title: "No Network", message: "There is no network connectivity, please try again later", delegate: nil, cancelButtonTitle: "OK").show()
		} else {
			if !app.startRefresh() {
				updateStatus()
			}
		}
	}

	func removeAllMerged()
	{
		dispatch_async(dispatch_get_main_queue(), { [weak self] in
			if Settings.dontAskBeforeWipingMerged {
				self!.removeAllMergedConfirmed()
			} else {
				let a = UIAlertController(title: "Sure?", message: "Remove all PRs in the Merged section?", preferredStyle: UIAlertControllerStyle.Alert)
				a.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style: UIAlertActionStyle.Destructive, handler: { [weak self] action in
					self!.removeAllMergedConfirmed()
				}))
				self!.presentViewController(a, animated: true, completion: nil)
			}
		})
	}

	func removeAllClosed() {
		dispatch_async(dispatch_get_main_queue(), { [weak self] in
			if Settings.dontAskBeforeWipingClosed {
				self!.removeAllClosedConfirmed()
			} else {
				let a = UIAlertController(title: "Sure?", message: "Remove all PRs in the Closed section?", preferredStyle: UIAlertControllerStyle.Alert)
				a.addAction(UIAlertAction(title: "Cancel", style:UIAlertActionStyle.Cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style:UIAlertActionStyle.Destructive, handler: { [weak self] action in
					self!.removeAllClosedConfirmed()
				}))
				self!.presentViewController(a, animated: true, completion: nil)
			}
		})
	}

	func removeAllClosedConfirmed() {
		for p in PullRequest.allClosedRequestsInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(p)
		}
		DataManager.saveDB()
	}

	func removeAllMergedConfirmed() {
		for p in PullRequest.allMergedRequestsInMoc(mainObjectContext) {
			mainObjectContext.deleteObject(p)
		}
		DataManager.saveDB()
	}

	func markAllAsRead() {
		for p in fetchedResultsController.fetchedObjects as [PullRequest] {
			p.catchUpWithComments()
		}
		DataManager.saveDB()
	}

	func refreshControlChanged() {
		refreshOnRelease = !app.isRefreshing
	}

	override func scrollViewDidEndDragging(scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		if refreshOnRelease && !decelerate {
			tryRefresh()
		}
	}

	override func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
		if refreshOnRelease {
			tryRefresh()
		}
	}

	required init(coder aDecoder: NSCoder) {
		searchField = UITextField(frame: CGRectMake(10, 10, 300, 31))
		searchField.autoresizingMask = UIViewAutoresizing.FlexibleWidth
		searchField.setTranslatesAutoresizingMaskIntoConstraints(true)
		searchField.placeholder = "Filter..."
		searchField.returnKeyType = UIReturnKeyType.Done
		searchField.font = UIFont.systemFontOfSize(17)
		searchField.borderStyle = UITextBorderStyle.RoundedRect
		searchField.contentVerticalAlignment = UIControlContentVerticalAlignment.Center
		searchField.clearButtonMode = UITextFieldViewMode.Always
		searchField.autocapitalizationType = UITextAutocapitalizationType.None
		searchField.autocorrectionType = UITextAutocorrectionType.No

		refreshOnRelease = false

		super.init(coder: aDecoder)

		searchTimer = PopTimer(timeInterval: 0.5, callback: { [weak self] in
			self!.reloadDataWithAnimation(true)
		})
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		refreshControl?.addTarget(self, action: Selector("refreshControlChanged"), forControlEvents: UIControlEvents.ValueChanged)

		searchField.delegate = self;

		let searchHolder = UIView(frame: CGRectMake(0, 0, 320, 41))
		searchHolder.addSubview(searchField)
		tableView.tableHeaderView = searchHolder
		tableView.contentOffset = CGPointMake(0, searchHolder.frame.size.height)
		tableView.estimatedRowHeight = 110
		tableView.rowHeight = UITableViewAutomaticDimension

		detailViewController = splitViewController?.viewControllers.last?.topViewController as DetailViewController

		let n = NSNotificationCenter.defaultCenter()

		n.addObserver(self, selector: Selector("updateStatus"), name:REFRESH_STARTED_NOTIFICATION, object: nil)
		n.addObserver(self, selector: Selector("updateStatus"), name:REFRESH_ENDED_NOTIFICATION, object: nil)
		n.addObserver(self, selector: Selector("localNotification:"), name:RECEIVED_NOTIFICATION_KEY, object: nil)
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		updateStatus()
	}

	func reloadDataWithAnimation(animated: Bool) {
		if(animated) {
			let currentIndexes = NSIndexSet(indexesInRange: NSMakeRange(0, fetchedResultsController.sections?.count ?? 0))

			_fetchedResultsController = nil
			updateStatus()

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

		} else {
			tableView.reloadData()
		}
	}

	func localNotification(notification: NSNotification) {
		//DLog("local notification: %@", notification.userInfo)
		var urlToOpen = notification.userInfo?[NOTIFICATION_URL_KEY] as? String

		var pullRequest: PullRequest?

		if let commentId = DataManager.idForUriPath(notification.userInfo?[COMMENT_ID_KEY] as? String) {
			if let c = mainObjectContext.existingObjectWithID(commentId, error:nil) as? PRComment {
				pullRequest = c.pullRequest
				if urlToOpen == nil {
					urlToOpen = c.webUrl
				}
			}
		}
		else if let pullRequestId = DataManager.idForUriPath(notification.userInfo?[PULL_REQUEST_ID_KEY] as? String) {
			pullRequest = mainObjectContext.existingObjectWithID(pullRequestId, error:nil) as? PullRequest
			if pullRequest == nil {
				UIAlertView(title: "PR not found", message: "Could not locale the PR related to this notification", delegate: nil, cancelButtonTitle: "OK").show()
			} else if urlToOpen == nil {
				urlToOpen = pullRequest!.webUrl
			}
		}

		if urlToOpen != nil && !(searchField.text ?? "").isEmpty {
			searchField.text = nil
			searchField.resignFirstResponder()
			reloadDataWithAnimation(false)
		}

		if let p = pullRequest {
			if let ip = fetchedResultsController.indexPathForObject(p) {
				detailViewController.catchupWithPrWhenLoaded = p.objectID
				tableView.selectRowAtIndexPath(ip, animated: false, scrollPosition: UITableViewScrollPosition.Middle)
			}
		}

		if let u = urlToOpen {
			detailViewController.detailItem = NSURL(string: u)
			if !detailViewController.isVisible {
				showDetailViewController(detailViewController.navigationController!, sender: self)
			}
		}
	}

	deinit {
		NSNotificationCenter.defaultCenter().removeObserver(self)
	}

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return fetchedResultsController.sections?.count ?? 0
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		let sectionInfo = fetchedResultsController.sections?[section] as? NSFetchedResultsSectionInfo
		return sectionInfo?.numberOfObjects ?? 0
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as UITableViewCell
		configureCell(cell, atIndexPath: indexPath)
		return cell
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		let pullRequest = fetchedResultsController.objectAtIndexPath(indexPath) as PullRequest
		if let p = pullRequest.urlForOpening() {
			detailViewController.detailItem = NSURL(string: p)
			detailViewController.catchupWithPrWhenLoaded = pullRequest.objectID
			showDetailViewController(detailViewController.navigationController!, sender: self)
		}
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		let sectionInfo = fetchedResultsController.sections?[section] as? NSFetchedResultsSectionInfo
		return sectionInfo?.name ?? "Unknown Section"
	}

	override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
		if let sectionInfo = fetchedResultsController.sections?[indexPath.section] as? NSFetchedResultsSectionInfo {
			let sectionName = sectionInfo.name
			return sectionName == PullRequestSection.Merged.name() || sectionName == PullRequestSection.Closed.name()
		} else {
			return false
		}
	}

	override func tableView(tableView: UITableView, editingStyleForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCellEditingStyle {
		return UITableViewCellEditingStyle.Delete
	}

	override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
		if editingStyle == UITableViewCellEditingStyle.Delete {
			let pr = fetchedResultsController.objectAtIndexPath(indexPath) as NSManagedObject
			mainObjectContext.deleteObject(pr)
			DataManager.saveDB()
		}
	}

	private var fetchedResultsController: NSFetchedResultsController {
		if let c = _fetchedResultsController {
			return c
		}

		let fetchRequest = PullRequest.requestForPullRequestsWithFilter(searchField.text)

		let aFetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: mainObjectContext, sectionNameKeyPath: "sectionName", cacheName: nil)
		aFetchedResultsController.delegate = self
		_fetchedResultsController = aFetchedResultsController

		var error: NSError?
		if !aFetchedResultsController.performFetch(&error) {
			if let e = error {
				DLog( "Fetch request error %@, %@", e, e.userInfo)
				abort()
			}
		}

		return aFetchedResultsController
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
		updateStatus()
	}

	private func configureCell(cell: UITableViewCell, atIndexPath: NSIndexPath) {
		let pr = fetchedResultsController.objectAtIndexPath(atIndexPath) as PullRequest
		(cell as PRCell).setPullRequest(pr)
	}

	func updateStatus() {
		if app.isRefreshing {
			title = "Refreshing..."
			tableView.tableFooterView = EmptyView(message: DataManager.reasonForEmptyWithFilter(searchField.text), parentWidth: view.bounds.size.width)
			if !(refreshControl?.refreshing ?? false) {
				dispatch_async(dispatch_get_main_queue(), { [weak self] in
					self!.refreshControl!.beginRefreshing()
				})
			}
		} else {
			let count = fetchedResultsController.fetchedObjects?.count ?? 0
			if count>0 {
				title = count == 1 ? "1 Pull Request" : "\(count) Pull Requests"
				tableView.tableFooterView = nil
			}
			else
			{
				title = "No PRs"
				tableView.tableFooterView = EmptyView(message: DataManager.reasonForEmptyWithFilter(searchField.text), parentWidth: view.bounds.size.width)
			}

			dispatch_async(dispatch_get_main_queue(), { [weak self] in
				self!.refreshControl!.endRefreshing()
			})
		}

		refreshControl?.attributedTitle = NSAttributedString(string: api.lastUpdateDescription(), attributes: nil)

		UIApplication.sharedApplication().applicationIconBadgeNumber = PullRequest.badgeCountInMoc(mainObjectContext)

		if splitViewController?.displayMode != UISplitViewControllerDisplayMode.AllVisible {
			detailViewController.navigationItem.leftBarButtonItem?.title = title
		}
	}

		///////////////////////////// filtering

	override func scrollViewWillBeginDragging(scrollView: UIScrollView) {
		if searchField.isFirstResponder() {
			searchField.resignFirstResponder()
		}
	}

	func textFieldShouldClear(textField: UITextField) -> Bool {
		searchTimer!.push()
		return true
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			textField.resignFirstResponder()
		} else {
			searchTimer!.push()
		}
		return true
	}

	////////////////// opening prefs

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		var allServersHaveTokens = true
		for a in ApiServer.allApiServersInMoc(mainObjectContext) {
			if !a.goodToGo {
				allServersHaveTokens = false
				break
			}
		}

		if let destination = segue.destinationViewController as? UITabBarController {
			if allServersHaveTokens {
				destination.selectedIndex = min(Settings.lastPreferencesTabSelected, (destination.viewControllers?.count ?? 1)-1);
				destination.delegate = self
			}
		}
	}

	func tabBarController(tabBarController: UITabBarController, didSelectViewController viewController: UIViewController) {
		Settings.lastPreferencesTabSelected = indexOfObject(tabBarController.viewControllers!, viewController) ?? 0
	}

	private func indexOfObject(array: [AnyObject], _ value: AnyObject) -> Int? {
		for (index, element) in enumerate(array) {
			if element === value {
				return index
			}
		}
		return nil
	}
}
