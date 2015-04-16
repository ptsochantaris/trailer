
import UIKit
import CoreData

final class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate, UITextFieldDelegate, UIActionSheetDelegate, UITabBarControllerDelegate, UITabBarDelegate {

	private var detailViewController: DetailViewController!
	private var _fetchedResultsController: NSFetchedResultsController?

	// Filtering
	private let searchField: UITextField
	private var searchTimer: PopTimer?

	// Refreshing
	private var refreshOnRelease: Bool
	private var blueTint: UIColor!

	private let pullRequestsItem = UITabBarItem()
	private let issuesItem = UITabBarItem()
	private var tabBar: UITabBar?

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
			a.addAction(UIAlertAction(title: "Refresh Now", style:UIAlertActionStyle.Default, handler: { action in
				app.startRefresh()
			}))
			presentViewController(a, animated: true, completion: nil)
		}
		else
		{
			let a = UIActionSheet(title: "Action",
				delegate:self,
				cancelButtonTitle: "Cancel",
				destructiveButtonTitle: "Mark all as read",
				otherButtonTitles: "Remove all merged",  "Remove all closed", "Refresh Now")

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
		case 4:
			app.startRefresh()
		default:
			break
		}
	}

	private func tryRefresh() {
		refreshOnRelease = false

		if api.currentNetworkStatus == NetworkStatus.NotReachable {
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
				let a = UIAlertController(title: "Sure?", message: "Remove all \(self!.viewMode.namePlural()) in the Merged section?", preferredStyle: UIAlertControllerStyle.Alert)
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
				let a = UIAlertController(title: "Sure?", message: "Remove all \(self!.viewMode.namePlural()) in the Closed section?", preferredStyle: UIAlertControllerStyle.Alert)
				a.addAction(UIAlertAction(title: "Cancel", style:UIAlertActionStyle.Cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style:UIAlertActionStyle.Destructive, handler: { [weak self] action in
					self!.removeAllClosedConfirmed()
					}))
				self!.presentViewController(a, animated: true, completion: nil)
			}
			})
	}

	func removeAllClosedConfirmed() {
		if viewMode == MasterViewMode.PullRequests {
			for p in PullRequest.allClosedRequestsInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
		} else {
			for p in Issue.allClosedIssuesInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
		}
		DataManager.saveDB()
	}

	func removeAllMergedConfirmed() {
		if viewMode == MasterViewMode.PullRequests {
			for p in PullRequest.allMergedRequestsInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
			DataManager.saveDB()
		}
	}

	func markAllAsRead() {
		if viewMode == MasterViewMode.PullRequests {
			for p in fetchedResultsController.fetchedObjects as! [PullRequest] {
				p.catchUpWithComments()
			}
		} else {
			for p in fetchedResultsController.fetchedObjects as! [Issue] {
				p.catchUpWithComments()
			}
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

		searchTimer = PopTimer(timeInterval: 0.5) { [weak self] in
			self!.reloadDataWithAnimation(true)
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		refreshControl?.addTarget(self, action: Selector("refreshControlChanged"), forControlEvents: UIControlEvents.ValueChanged)

		searchField.delegate = self

		blueTint = view.tintColor

		let searchHolder = UIView(frame: CGRectMake(0, 0, 320, 41))
		searchHolder.addSubview(searchField)
		tableView.tableHeaderView = searchHolder
		tableView.contentOffset = CGPointMake(0, searchHolder.frame.size.height)
		tableView.estimatedRowHeight = 110
		tableView.rowHeight = UITableViewAutomaticDimension

		detailViewController = splitViewController?.viewControllers.last?.topViewController as! DetailViewController

		let n = NSNotificationCenter.defaultCenter()

		n.addObserver(self, selector: Selector("updateStatus"), name:REFRESH_STARTED_NOTIFICATION, object: nil)
		n.addObserver(self, selector: Selector("updateStatus"), name:REFRESH_ENDED_NOTIFICATION, object: nil)
		n.addObserver(self, selector: Selector("localNotification:"), name:RECEIVED_NOTIFICATION_KEY, object: nil)

		pullRequestsItem.title = "Pull Requests"
		pullRequestsItem.image = UIImage(named: "prsTab")
		issuesItem.title = "Issues"
		issuesItem.image = UIImage(named: "issuesTab")
	}

	func tabBar(tabBar: UITabBar, didSelectItem item: UITabBarItem!) {
		viewMode = indexOfObject(tabBar.items!, item)==0 ? MasterViewMode.PullRequests : MasterViewMode.Issues
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		updateStatus()
		showTabBar(Settings.showIssuesMenu, animated: animated)
	}

	func reloadDataWithAnimation(animated: Bool) {

		if !Settings.showIssuesMenu && viewMode == MasterViewMode.Issues {
			showTabBar(Settings.showIssuesMenu, animated: animated)
			viewMode = MasterViewMode.PullRequests
			return
		}

		if animated {
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

		showTabBar(Settings.showIssuesMenu, animated: animated)
	}

	private func showTabBar(show: Bool, animated: Bool) {
		if show==true {

			tableView.contentInset = UIEdgeInsetsMake(tableView.contentInset.top, 0, 49, 0)
			tableView.scrollIndicatorInsets = UIEdgeInsetsMake(tableView.contentInset.top, 0, 49, 0)

			if tabBar == nil {
				if let s = navigationController?.view {
					let t = UITabBar(frame: CGRectMake(0, s.bounds.size.height-49, s.bounds.size.width, 49))
					t.autoresizingMask = UIViewAutoresizing.FlexibleTopMargin | UIViewAutoresizing.FlexibleBottomMargin | UIViewAutoresizing.FlexibleWidth
					t.items = [pullRequestsItem, issuesItem]
					t.selectedItem = viewMode==MasterViewMode.PullRequests ? pullRequestsItem : issuesItem
					t.delegate = self
					t.tintColor = blueTint
					t.itemPositioning = UITabBarItemPositioning.Fill
					s.addSubview(t)
					tabBar = t

					if animated {
						t.transform = CGAffineTransformMakeTranslation(0, 49)
						UIView.animateWithDuration(0.2,
							delay: 0.0,
							options: UIViewAnimationOptions.CurveEaseInOut,
							animations: {
								t.transform = CGAffineTransformIdentity
							}, completion: nil);
					}
				}
			}
		} else {

			if !Settings.showIssuesMenu {
				tableView.contentInset = UIEdgeInsetsMake(tableView.contentInset.top, 0, 0, 0)
				tableView.scrollIndicatorInsets = UIEdgeInsetsMake(tableView.contentInset.top, 0, 0, 0)
			}

			if let t = tabBar {
				if animated {
					UIView.animateWithDuration(0.2,
						delay: 0.0,
						options: UIViewAnimationOptions.CurveEaseInOut,
						animations: {
							t.transform = CGAffineTransformMakeTranslation(0, 49)
						}, completion: { [weak self] finished in
							t.removeFromSuperview()
							self!.tabBar = nil
						})
				} else {
					t.removeFromSuperview()
					tabBar = nil
				}
			}
		}
	}

	func localNotification(notification: NSNotification) {
		var urlToOpen = notification.userInfo?[NOTIFICATION_URL_KEY] as? String
		var relatedItem: ListableItem?

		if let commentId = DataManager.idForUriPath(notification.userInfo?[COMMENT_ID_KEY] as? String), c = mainObjectContext.existingObjectWithID(commentId, error:nil) as? PRComment {
				relatedItem = c.pullRequest ?? c.issue
				if urlToOpen == nil {
					urlToOpen = c.webUrl
				}
		} else if let pullRequestId = DataManager.idForUriPath(notification.userInfo?[PULL_REQUEST_ID_KEY] as? String) {
			relatedItem = mainObjectContext.existingObjectWithID(pullRequestId, error:nil) as? ListableItem
			if relatedItem == nil {
				UIAlertView(title: "PR not found", message: "Could not locale the PR related to this notification", delegate: nil, cancelButtonTitle: "OK").show()
			} else if urlToOpen == nil {
				urlToOpen = relatedItem!.webUrl
			}
		} else if let issueId = DataManager.idForUriPath(notification.userInfo?[ISSUE_ID_KEY] as? String) {
			relatedItem = mainObjectContext.existingObjectWithID(issueId, error:nil) as? ListableItem
			if relatedItem == nil {
				UIAlertView(title: "Issue not found", message: "Could not locale the issue related to this notification", delegate: nil, cancelButtonTitle: "OK").show()
			} else if urlToOpen == nil {
				urlToOpen = relatedItem!.webUrl
			}
		}

		if urlToOpen != nil && !(searchField.text ?? "").isEmpty {
			searchField.text = nil
			searchField.resignFirstResponder()
			reloadDataWithAnimation(false)
		}

		if let p = relatedItem as? PullRequest {
			viewMode = MasterViewMode.PullRequests
			detailViewController.catchupWithDataItemWhenLoaded = p.objectID
			if let ip = fetchedResultsController.indexPathForObject(p) {
				tableView.selectRowAtIndexPath(ip, animated: false, scrollPosition: UITableViewScrollPosition.Middle)
			}
		} else if let i = relatedItem as? Issue where Settings.showIssuesMenu {
			viewMode = MasterViewMode.Issues
			detailViewController.catchupWithDataItemWhenLoaded = i.objectID
			if let ip = fetchedResultsController.indexPathForObject(i) {
				tableView.selectRowAtIndexPath(ip, animated: false, scrollPosition: UITableViewScrollPosition.Middle)
			}
		}

		if let u = urlToOpen {
			detailViewController.detailItem = NSURL(string: u)
			if !detailViewController.isVisible {
				showTabBar(false, animated: true)
				showDetailViewController(detailViewController.navigationController!, sender: self)
			}
		}
	}

	func openPrWithId(prId: String) {
		viewMode = MasterViewMode.PullRequests
		if let
			pullRequestId = DataManager.idForUriPath(prId),
			pr = mainObjectContext.existingObjectWithID(pullRequestId, error:nil) as? PullRequest,
			ip = fetchedResultsController.indexPathForObject(pr)
		{
			pr.catchUpWithComments()
			tableView.selectRowAtIndexPath(ip, animated: false, scrollPosition: UITableViewScrollPosition.Middle)
			tableView(tableView, didSelectRowAtIndexPath: ip)
		}
	}

	func openIssueWithId(iId: String) {
		viewMode = MasterViewMode.Issues
		if let
			issueId = DataManager.idForUriPath(iId),
			issue = mainObjectContext.existingObjectWithID(issueId, error:nil) as? Issue,
			ip = fetchedResultsController.indexPathForObject(issue)
		{
			issue.catchUpWithComments()
			tableView.selectRowAtIndexPath(ip, animated: false, scrollPosition: UITableViewScrollPosition.Middle)
			tableView(tableView, didSelectRowAtIndexPath: ip)
		}
	}

	func openCommentWithId(cId: String) {
		if let
			itemId = DataManager.idForUriPath(cId),
			comment = mainObjectContext.existingObjectWithID(itemId, error:nil) as? PRComment
		{
			if let url = comment.webUrl {
				var ip: NSIndexPath?
				if let pr = comment.pullRequest {
					viewMode = MasterViewMode.PullRequests
					ip = fetchedResultsController.indexPathForObject(pr)
					detailViewController.catchupWithDataItemWhenLoaded = nil
					pr.catchUpWithComments()
				} else if let issue = comment.issue {
					viewMode = MasterViewMode.Issues
					ip = fetchedResultsController.indexPathForObject(issue)
					detailViewController.catchupWithDataItemWhenLoaded = nil
					issue.catchUpWithComments()
				}
				if let i = ip {
					tableView.selectRowAtIndexPath(i, animated: false, scrollPosition: UITableViewScrollPosition.Middle)
					detailViewController.detailItem = NSURL(string: url)
					if !detailViewController.isVisible {
						showTabBar(false, animated: true)
						showDetailViewController(detailViewController.navigationController!, sender: self)
					}
				}
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
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! UITableViewCell
		configureCell(cell, atIndexPath: indexPath)
		return cell
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
		if let
			p = fetchedResultsController.objectAtIndexPath(indexPath) as? PullRequest,
			u = p.urlForOpening()
			where viewMode == MasterViewMode.PullRequests
		{
			detailViewController.detailItem = NSURL(string: u)
			detailViewController.catchupWithDataItemWhenLoaded = p.objectID
		} else if let
			i = fetchedResultsController.objectAtIndexPath(indexPath) as? Issue,
			u = i.urlForOpening()
			where viewMode == MasterViewMode.Issues
		{
			detailViewController.detailItem = NSURL(string: u)
			detailViewController.catchupWithDataItemWhenLoaded = i.objectID
		}

		if !detailViewController.isVisible {
			showTabBar(false, animated: true)
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
			return sectionName == PullRequestSection.Merged.prMenuName() || sectionName == PullRequestSection.Closed.prMenuName()
		} else {
			return false
		}
	}

	override func tableView(tableView: UITableView, editingStyleForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCellEditingStyle {
		return UITableViewCellEditingStyle.Delete
	}

	override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
		if editingStyle == UITableViewCellEditingStyle.Delete {
			let pr = fetchedResultsController.objectAtIndexPath(indexPath) as! NSManagedObject
			mainObjectContext.deleteObject(pr)
			DataManager.saveDB()
		}
	}

	private var fetchedResultsController: NSFetchedResultsController {
		if let c = _fetchedResultsController {
			return c
		}

		var fetchRequest: NSFetchRequest

		if viewMode == MasterViewMode.PullRequests {
			fetchRequest = PullRequest.requestForPullRequestsWithFilter(searchField.text, sectionIndex: -1)
		} else {
			fetchRequest = Issue.requestForIssuesWithFilter(searchField.text, sectionIndex: -1)
		}

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
		if viewMode == MasterViewMode.PullRequests {
			let pr = fetchedResultsController.objectAtIndexPath(atIndexPath) as! PullRequest
			(cell as! PRCell).setPullRequest(pr)
		} else {
			let i = fetchedResultsController.objectAtIndexPath(atIndexPath) as! Issue
			(cell as! PRCell).setIssue(i)
		}
	}

	func updateStatus() {

		let prUnreadCount = PullRequest.badgeCountInMoc(mainObjectContext)
		pullRequestsItem.badgeValue = prUnreadCount > 0 ? "\(prUnreadCount)" : nil

		let issuesUnreadCount = Issue.badgeCountInMoc(mainObjectContext)
		issuesItem.badgeValue = issuesUnreadCount > 0 ? "\(issuesUnreadCount)" : nil

		if app.isRefreshing {
			title = "Refreshing..."
			tableView.tableFooterView = EmptyView(message: DataManager.reasonForEmptyWithFilter(searchField.text), parentWidth: view.bounds.size.width)
			if !(refreshControl?.refreshing ?? false) {
				dispatch_async(dispatch_get_main_queue(), { [weak self] in
					self!.refreshControl!.beginRefreshing()
					})
			}
		} else {

			title = viewMode == MasterViewMode.PullRequests ? pullRequestsTitle(true) : issuesTitle()

			let count = fetchedResultsController.fetchedObjects?.count ?? 0
			tableView.tableFooterView = (count == 0) ? EmptyView(message: DataManager.reasonForEmptyIssuesWithFilter(searchField.text), parentWidth: view.bounds.size.width) : nil

			dispatch_async(dispatch_get_main_queue(), { [weak self] in
				self!.refreshControl!.endRefreshing()
				})
		}

		refreshControl?.attributedTitle = NSAttributedString(string: api.lastUpdateDescription(), attributes: nil)

		UIApplication.sharedApplication().applicationIconBadgeNumber = PullRequest.badgeCountInMoc(mainObjectContext) + Issue.badgeCountInMoc(mainObjectContext)

		if splitViewController?.displayMode != UISplitViewControllerDisplayMode.AllVisible {
			detailViewController.navigationItem.leftBarButtonItem?.title = title
		}

		tabBar?.selectedItem = (viewMode==MasterViewMode.PullRequests) ? pullRequestsItem : issuesItem
	}

	private func pullRequestsTitle(long: Bool) -> String {

		let f = PullRequest.requestForPullRequestsWithFilter(nil, sectionIndex: -1)
		let count = mainObjectContext.countForFetchRequest(f, error: nil)
		let unreadCount = pullRequestsItem.badgeValue?.toInt() ?? 0

		let pr = long ? "Pull Request" : "PR"
		if count == 0 {
			return "No \(pr)s"
		} else if count == 1 {
			return "1 " + (unreadCount > 0 ? "PR (unread)" : pr)
		} else {
			return "\(count) " + (unreadCount > 0 ? "PRs (\(unreadCount) unread)" : pr + "s")
		}
	}

	private func issuesTitle() -> String {
		let f = Issue.requestForIssuesWithFilter(nil, sectionIndex: -1)
		let count = mainObjectContext.countForFetchRequest(f, error: nil)
		let unreadCount = issuesItem.badgeValue?.toInt() ?? 0

		if count == 0 {
			return "No Issues"
		} else if count == 1 {
			return "1 Issue" + (unreadCount > 0 ? " (unread)" : "")
		} else {
			return "\(count) Issues" + (unreadCount > 0 ? " (\(unreadCount) unread)" : "")
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

	////////////////// mode

	func showPullRequestsSelected(sender: AnyObject) {
		viewMode = MasterViewMode.PullRequests
	}

	func showIssuesSelected(sender: AnyObject) {
		viewMode = MasterViewMode.Issues
	}

	var viewMode: MasterViewMode = .PullRequests {
		didSet {
			_fetchedResultsController = nil
			tableView.reloadData()
			updateStatus()
		}
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
				destination.selectedIndex = min(Settings.lastPreferencesTabSelected, (destination.viewControllers?.count ?? 1)-1)
				destination.delegate = self
			}
		}
	}

	func tabBarController(tabBarController: UITabBarController, didSelectViewController viewController: UIViewController) {
		Settings.lastPreferencesTabSelected = indexOfObject(tabBarController.viewControllers!, viewController) ?? 0
	}
	
}
