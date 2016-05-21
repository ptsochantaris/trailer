
import UIKit
import CoreData

final class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate, UITextFieldDelegate, UITabBarControllerDelegate, UITabBarDelegate {

	private var detailViewController: DetailViewController!
	private var _fetchedResultsController: NSFetchedResultsController?

	// Filtering
	private var searchField: UITextField!
	private var searchTimer: PopTimer!

	// Refreshing
	private var refreshOnRelease: Bool = false

	private let pullRequestsItem = UITabBarItem()
	private let issuesItem = UITabBarItem()
	private var tabBar: UITabBar?

	@IBAction func editSelected(sender: UIBarButtonItem ) {

		let a = UIAlertController(title: "Action", message: nil, preferredStyle: UIAlertControllerStyle.Alert)

		a.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel) { action in
			a.dismissViewControllerAnimated(true, completion: nil)
		})
		a.addAction(UIAlertAction(title: "Mark all as read", style: UIAlertActionStyle.Destructive) { [weak self] action in
			self?.markAllAsRead()
		})
		a.addAction(UIAlertAction(title: "Remove merged", style:UIAlertActionStyle.Default) { [weak self] action in
			self?.removeAllMerged()
		})
		a.addAction(UIAlertAction(title: "Remove closed", style:UIAlertActionStyle.Default) { [weak self] action in
			self?.removeAllClosed()
		})
		presentViewController(a, animated: true, completion: nil)
	}

	private func tryRefresh() {
		refreshOnRelease = false

		if api.noNetworkConnection() {
			showMessage("No Network", "There is no network connectivity, please try again later")
		} else {
			if !app.startRefresh() {
				updateStatus()
			}
		}
	}

	func removeAllMerged() {
		atNextEvent(self) { S in
			if Settings.dontAskBeforeWipingMerged {
				S.removeAllMergedConfirmed()
			} else {
				let a = UIAlertController(title: "Sure?", message: "Remove all \(S.viewMode.namePlural()) in the Merged section?", preferredStyle: UIAlertControllerStyle.Alert)
				a.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style: UIAlertActionStyle.Destructive) { [weak S] action in
					S?.removeAllMergedConfirmed()
				})
				S.presentViewController(a, animated: true, completion: nil)
			}
		}
	}

	func removeAllClosed() {
		atNextEvent(self) { S in
			if Settings.dontAskBeforeWipingClosed {
				S.removeAllClosedConfirmed()
			} else {
				let a = UIAlertController(title: "Sure?", message: "Remove all \(S.viewMode.namePlural()) in the Closed section?", preferredStyle: UIAlertControllerStyle.Alert)
				a.addAction(UIAlertAction(title: "Cancel", style:UIAlertActionStyle.Cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style:UIAlertActionStyle.Destructive) { [weak S] action in
					S?.removeAllClosedConfirmed()
				})
				S.presentViewController(a, animated: true, completion: nil)
			}
		}
	}

	func removeAllClosedConfirmed() {
		if viewMode == .PullRequests {
			for p in PullRequest.allClosedInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
		} else {
			for p in Issue.allClosedInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
		}
		DataManager.saveDB()
	}

	func removeAllMergedConfirmed() {
		if viewMode == .PullRequests {
			for p in PullRequest.allMergedInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
			DataManager.saveDB()
		}
	}

	func markAllAsRead() {
		for i in fetchedResultsController.fetchedObjects as! [ListableItem] {
			i.catchUpWithComments()
		}
		DataManager.saveDB()
	}

	func refreshControlChanged() {
		refreshOnRelease = !appIsRefreshing
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

	override func viewDidLoad() {
		super.viewDidLoad()

		searchTimer = PopTimer(timeInterval: 0.5) { [weak self] in
			self?.reloadDataWithAnimation(true)
		}

		refreshControl?.addTarget(self, action: #selector(MasterViewController.refreshControlChanged), forControlEvents: UIControlEvents.ValueChanged)

		searchField = UITextField(frame: CGRectMake(10, 10, 300, 31))
		searchField.autoresizingMask = UIViewAutoresizing.FlexibleWidth
		searchField.translatesAutoresizingMaskIntoConstraints = true
		searchField.placeholder = "Filter..."
		searchField.returnKeyType = UIReturnKeyType.Done
		searchField.font = UIFont.systemFontOfSize(17)
		searchField.borderStyle = UITextBorderStyle.RoundedRect
		searchField.contentVerticalAlignment = UIControlContentVerticalAlignment.Center
		searchField.clearButtonMode = UITextFieldViewMode.Always
		searchField.autocapitalizationType = UITextAutocapitalizationType.None
		searchField.autocorrectionType = UITextAutocorrectionType.No
		searchField.delegate = self

		let cover = UIView(frame: CGRectMake(0, 41, 320, 30))
		cover.backgroundColor = UIColor.groupTableViewBackgroundColor()
		cover.autoresizingMask = UIViewAutoresizing.FlexibleWidth

		let searchHolder = UIView(frame: CGRectMake(0, 0, 320, 41))
		searchHolder.addSubview(cover)
		searchHolder.addSubview(searchField)
		tableView.tableHeaderView = searchHolder
		tableView.rowHeight = UITableViewAutomaticDimension
		tableView.estimatedRowHeight = 240

		if let detailNav = splitViewController?.viewControllers.last as? UINavigationController {
			detailViewController = detailNav.topViewController as? DetailViewController
		}

		let n = NSNotificationCenter.defaultCenter()

		n.addObserver(self, selector: #selector(MasterViewController.updateStatus), name:REFRESH_STARTED_NOTIFICATION, object: nil)
		n.addObserver(self, selector: #selector(MasterViewController.updateStatus), name:REFRESH_ENDED_NOTIFICATION, object: nil)

		pullRequestsItem.title = "Pull Requests"
		pullRequestsItem.image = UIImage(named: "prsTab")
		issuesItem.title = "Issues"
		issuesItem.image = UIImage(named: "issuesTab")
	}

	func tabBar(tabBar: UITabBar, didSelectItem item: UITabBarItem) {
		if tabBar.items?.indexOf(item) == 0 {
			showPullRequestsSelected(tabBar)
		} else {
			showIssuesSelected(tabBar)
		}
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		updateStatus()
        updateTabBarVisibility(animated)
	}

	func reloadDataWithAnimation(animated: Bool) {

		if !Repo.interestedInIssues() && Repo.interestedInPrs() && viewMode == .Issues {
			showTabBar(false, animated: animated)
			viewMode = .PullRequests
			return
		}

		if !Repo.interestedInPrs() && Repo.interestedInIssues() && viewMode == .PullRequests {
			showTabBar(false, animated: animated)
			viewMode = .Issues
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
				tableView.deleteSections(removedIndexes, withRowAnimation:.Automatic)
			}
			if untouchedIndexes.count > 0 {
				tableView.reloadSections(untouchedIndexes, withRowAnimation:.Automatic)
			}
			if addedIndexes.count > 0 {
				tableView.insertSections(addedIndexes, withRowAnimation:.Automatic)
			}
			tableView.endUpdates()

		} else {
			tableView.reloadData()
		}

        updateTabBarVisibility(animated)
	}

    func updateTabBarVisibility(animated: Bool) {
        showTabBar(Repo.interestedInPrs() && Repo.interestedInIssues(), animated: animated)
    }

	private func showTabBar(show: Bool, animated: Bool) {
		if show {

			if tabBar == nil {

				tableView.contentInset = UIEdgeInsetsMake(tableView.contentInset.top, 0, 49, 0)
				tableView.scrollIndicatorInsets = UIEdgeInsetsMake(tableView.scrollIndicatorInsets.top, 0, 49, 0)

				if let s = navigationController?.view {
					let t = UITabBar(frame: CGRectMake(0, s.bounds.size.height-49, s.bounds.size.width, 49))
					t.autoresizingMask = [.FlexibleTopMargin, .FlexibleBottomMargin, .FlexibleWidth]
					t.items = [pullRequestsItem, issuesItem]
					t.selectedItem = (viewMode == .PullRequests) ? pullRequestsItem : issuesItem
					t.delegate = self
					t.itemPositioning = .Fill
					s.addSubview(t)
					tabBar = t

					if animated {
						t.transform = CGAffineTransformMakeTranslation(0, 49)
						UIView.animateWithDuration(0.2,
							delay: 0.0,
							options: .CurveEaseInOut,
							animations: {
								t.transform = CGAffineTransformIdentity
							}, completion: nil)
					}
				}
			}
		} else {

			if !(Repo.interestedInPrs() && Repo.interestedInIssues()) {
				tableView.contentInset = UIEdgeInsetsMake(tableView.contentInset.top, 0, 0, 0)
				tableView.scrollIndicatorInsets = UIEdgeInsetsMake(tableView.scrollIndicatorInsets.top, 0, 0, 0)
				self.viewMode = Repo.interestedInIssues() ? .Issues : .PullRequests
			}

			if let t = tabBar {
				if animated {
					UIView.animateWithDuration(0.2,
						delay: 0.0,
						options: .CurveEaseInOut,
						animations: {
							t.transform = CGAffineTransformMakeTranslation(0, 49)
						}, completion: { [weak self] finished in
							t.removeFromSuperview()
							self?.tabBar = nil
						})
				} else {
					t.removeFromSuperview()
					tabBar = nil
				}
			}
		}
	}

	func localNotification(userInfo: [NSObject : AnyObject], action: String?) {
		var urlToOpen = userInfo[NOTIFICATION_URL_KEY] as? String
		var relatedItem: ListableItem?

		if let commentId = DataManager.idForUriPath(userInfo[COMMENT_ID_KEY] as? String), c = existingObjectWithID(commentId) as? PRComment {
			relatedItem = c.pullRequest ?? c.issue
			if urlToOpen == nil {
				urlToOpen = c.webUrl
			}
		} else if let pullRequestId = DataManager.idForUriPath(userInfo[PULL_REQUEST_ID_KEY] as? String) {
			relatedItem = existingObjectWithID(pullRequestId) as? ListableItem
			if relatedItem == nil {
				showMessage("PR not found", "Could not locate the PR related to this notification")
			} else if urlToOpen == nil {
				urlToOpen = relatedItem!.webUrl
			}
		} else if let issueId = DataManager.idForUriPath(userInfo[ISSUE_ID_KEY] as? String) {
			relatedItem = existingObjectWithID(issueId) as? ListableItem
			if relatedItem == nil {
				showMessage("Issue not found", "Could not locate the issue related to this notification")
			} else if urlToOpen == nil {
				urlToOpen = relatedItem!.webUrl
			}
		}

		if let a = action, i = relatedItem {
			if a == "mute" {
				i.setMute(true)
			} else if a == "read" {
				i.catchUpWithComments()
			}
			DataManager.saveDB()
			updateStatus()
			return
		}

		if urlToOpen != nil && !S(searchField.text).isEmpty {
			searchField.text = nil
			searchField.resignFirstResponder()
			reloadDataWithAnimation(false)
		}

		var oid: NSManagedObjectID?

		if let i = relatedItem {
			viewMode = i is PullRequest ? .PullRequests : .Issues
			oid = i.objectID
			if let ip = fetchedResultsController.indexPathForObject(i) {
				tableView.selectRowAtIndexPath(ip, animated: false, scrollPosition: .Middle)
			}
		}

		if let u = urlToOpen, url = NSURL(string: u) {
			showDetail(url, objectId: oid)
		} else {
			showDetail(nil, objectId: nil)
		}
	}

	func openItemWithUriPath(uriPath: String) {
		if let
			itemId = DataManager.idForUriPath(uriPath),
			item = existingObjectWithID(itemId) as? ListableItem,
			ip = fetchedResultsController.indexPathForObject(item)
		{
			viewMode = item is PullRequest ? .PullRequests : .Issues
			item.catchUpWithComments()
			tableView.selectRowAtIndexPath(ip, animated: false, scrollPosition: .Middle)
			tableView(tableView, didSelectRowAtIndexPath: ip)
		}
	}

	func openCommentWithId(cId: String) {
		if let
			itemId = DataManager.idForUriPath(cId),
			comment = existingObjectWithID(itemId) as? PRComment
		{
			if let url = comment.webUrl {
				var ip: NSIndexPath?
				if let pr = comment.pullRequest {
					viewMode = .PullRequests
					ip = fetchedResultsController.indexPathForObject(pr)
					pr.catchUpWithComments()
				} else if let issue = comment.issue {
					viewMode = .Issues
					ip = fetchedResultsController.indexPathForObject(issue)
					issue.catchUpWithComments()
				}
				if let i = ip {
					tableView.selectRowAtIndexPath(i, animated: false, scrollPosition: .Middle)
					showDetail(NSURL(string: url), objectId: nil)
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
		return fetchedResultsController.sections?[section].numberOfObjects ?? 0
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath)
		configureCell(cell, atIndexPath: indexPath)
		return cell
	}

	override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {

		func openItem(item: ListableItem, url: NSURL, oid: NSManagedObjectID) -> Bool {
			if Settings.openItemsDirectlyInSafari && !detailViewController.isVisible {
				item.catchUpWithComments()
				UIApplication.sharedApplication().openURL(url)
				return true
			} else {
				showDetail(url, objectId: oid)
				return false
			}
		}

		if viewMode == .PullRequests, let
			p = fetchedResultsController.objectAtIndexPath(indexPath) as? PullRequest,
			u = p.urlForOpening(),
			url = NSURL(string: u)
		{
			if openItem(p, url: url, oid: p.objectID) {
				tableView.deselectRowAtIndexPath(indexPath, animated: true)
			}
		} else if viewMode == .Issues, let
			i = fetchedResultsController.objectAtIndexPath(indexPath) as? Issue,
			u = i.urlForOpening(),
			url = NSURL(string: u)
		{
			if openItem(i, url: url, oid: i.objectID) {
				tableView.deselectRowAtIndexPath(indexPath, animated: true)
			}
		}
	}

	private func showDetail(url: NSURL?, objectId: NSManagedObjectID?) {
		detailViewController.catchupWithDataItemWhenLoaded = objectId
		detailViewController.detailItem = url
		if !detailViewController.isVisible, let n = detailViewController.navigationController {
			showTabBar(false, animated: true)
			showDetailViewController(n, sender: self)
		}
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		return S(fetchedResultsController.sections?[section].name)
	}

	override func tableView(tableView: UITableView, editActionsForRowAtIndexPath indexPath: NSIndexPath) -> [UITableViewRowAction]? {

		var actions = [UITableViewRowAction]()

		if let i = fetchedResultsController.objectAtIndexPath(indexPath) as? ListableItem, sectionName = fetchedResultsController.sections?[indexPath.section].name {

			if sectionName == Section.Merged.prMenuName() || sectionName == Section.Closed.prMenuName() || sectionName == Section.Closed.issuesMenuName() {
				let d = UITableViewRowAction(style: .Destructive, title: "Delete") { action, indexPath in
					mainObjectContext.deleteObject(i)
					DataManager.saveDB()
				}
				actions.append(d)
			} else if i.isSnoozing {
				let w = UITableViewRowAction(style: .Normal, title: "Wake") { action, indexPath in
					i.wakeUp()
					DataManager.saveDB()
				}
				w.backgroundColor = UIColor.darkGrayColor()
				actions.append(w)
			} else {

				let r: UITableViewRowAction
				if i.unreadComments?.longLongValue ?? 0 > 0 {
					r = UITableViewRowAction(style: .Normal, title: "Read") { action, indexPath in
						app.markItemAsRead(i.objectID.URIRepresentation().absoluteString, reloadView: false)
						tableView.setEditing(false, animated: true)
					}
				} else {
					r = UITableViewRowAction(style: .Normal, title: "Unread") { action, indexPath in
						app.markItemAsUnRead(i.objectID.URIRepresentation().absoluteString, reloadView: false)
						tableView.setEditing(false, animated: true)
					}
				}
				r.backgroundColor = view.tintColor
				actions.append(r)

				let m: UITableViewRowAction
				if i.muted?.boolValue ?? false {
					m = UITableViewRowAction(style: .Normal, title: "Unmute") { action, indexPath in
						i.setMute(false)
						DataManager.saveDB()
						tableView.setEditing(false, animated: true)
					}
				} else {
					m = UITableViewRowAction(style: .Normal, title: "Mute") { action, indexPath in
						i.setMute(true)
						DataManager.saveDB()
						tableView.setEditing(false, animated: true)
					}
				}
				actions.append(m)

				let s = UITableViewRowAction(style: .Normal, title: "Snooze") { [weak self] action, indexPath in
					self?.showSnoozeMenuFor(i)
				}
				s.backgroundColor = UIColor.darkGrayColor()
				actions.append(s)
			}
		}
		return actions
	}

	private func showSnoozeMenuFor(i: ListableItem) {
		let items = SnoozePreset.allSnoozePresetsInMoc(mainObjectContext)
		let hasPresets = items.count > 0
		let singleColumn = splitViewController?.collapsed ?? true
		let a = UIAlertController(title: hasPresets ? "Snooze" : nil,
		                          message: hasPresets ? S(i.title) : "You do not currently have any snoozing presets configured. Please add some in the relevant preferences tab.",
		                          preferredStyle: singleColumn ? .ActionSheet : .Alert)
		for item in items {
			a.addAction(UIAlertAction(title: item.listDescription, style: .Default) { action in
				i.snoozeUntil = item.wakeupDateFromNow
				i.muted = false
				i.postProcess()
				DataManager.saveDB()
			})
		}
		a.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
		presentViewController(a, animated: true, completion: nil)
	}

	private var fetchedResultsController: NSFetchedResultsController {
		if let c = _fetchedResultsController {
			return c
		}

		let type = viewMode == .PullRequests ? "PullRequest" : "Issue"
		let fetchRequest = ListableItem.requestForItemsOfType(type, withFilter: searchField.text, sectionIndex: -1)

		let c = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: mainObjectContext, sectionNameKeyPath: "sectionName", cacheName: nil)
		_fetchedResultsController = c
		c.delegate = self
		try! c.performFetch()
		return c
	}

	func controllerWillChangeContent(controller: NSFetchedResultsController) {
		if UIApplication.sharedApplication().applicationState != .Active { return }
		tableView.beginUpdates()
	}

	func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {

		if UIApplication.sharedApplication().applicationState != .Active { return }

		switch(type) {
		case .Insert:
			tableView.insertSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Automatic)
		case .Delete:
			tableView.deleteSections(NSIndexSet(index: sectionIndex), withRowAnimation: .Automatic)
		case .Update, .Move:
			break
		}
	}

	func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {

		if UIApplication.sharedApplication().applicationState != .Active { return }

		switch(type) {
		case .Insert:
			if let n = newIndexPath {
				tableView.insertRowsAtIndexPaths([n], withRowAnimation: .Automatic)
			}
		case .Delete:
			if let i = indexPath {
				tableView.deleteRowsAtIndexPaths([i], withRowAnimation:.Automatic)
			}
		case .Update:
			if let i = indexPath, cell = tableView.cellForRowAtIndexPath(i) {
				configureCell(cell, atIndexPath: i)
			}
		case .Move:
			if let i = indexPath {
				tableView.deleteRowsAtIndexPaths([i], withRowAnimation:.Automatic)
			}
			if let n = newIndexPath {
				tableView.insertRowsAtIndexPaths([n], withRowAnimation:.Automatic)
			}
		}
	}

	func controllerDidChangeContent(controller: NSFetchedResultsController) {
		if UIApplication.sharedApplication().applicationState != .Active {
			tableView.reloadData()
		} else {
			tableView.endUpdates()
		}
		updateStatus()
	}

	private func configureCell(cell: UITableViewCell, atIndexPath: NSIndexPath) {

		if let sections = fetchedResultsController.sections, c = cell as? PRCell {
			let r = atIndexPath.row
			let s = atIndexPath.section

			if s >= 0 && s < sections.count && r >= 0 && r < sections[s].numberOfObjects {
				let o = fetchedResultsController.objectAtIndexPath(atIndexPath)
				if viewMode == .PullRequests {
					c.setPullRequest(o as! PullRequest)
				} else {
					c.setIssue(o as! Issue)
				}
			}
		}
	}

	func updateStatus() {

		let prUnreadCount = PullRequest.badgeCountInMoc(mainObjectContext)
		pullRequestsItem.badgeValue = prUnreadCount > 0 ? "\(prUnreadCount)" : nil

		let issuesUnreadCount = Issue.badgeCountInMoc(mainObjectContext)
		issuesItem.badgeValue = issuesUnreadCount > 0 ? "\(issuesUnreadCount)" : nil

		if appIsRefreshing {
			title = "Refreshing..."
			if viewMode == .PullRequests {
				tableView.tableFooterView = EmptyView(message: PullRequest.reasonForEmptyWithFilter(searchField.text), parentWidth: view.bounds.size.width)
			} else {
				tableView.tableFooterView = EmptyView(message: Issue.reasonForEmptyWithFilter(searchField.text), parentWidth: view.bounds.size.width)
			}
			if let r = refreshControl {
				r.attributedTitle = NSAttributedString(string: api.lastUpdateDescription(), attributes: nil)
				if !r.refreshing {
					r.beginRefreshing()
				}
			}
		} else {

			let count = fetchedResultsController.fetchedObjects?.count ?? 0
			if viewMode == .PullRequests {
				title = pullRequestsTitle(true)
				tableView.tableFooterView = (count == 0) ? EmptyView(message: PullRequest.reasonForEmptyWithFilter(searchField.text), parentWidth: view.bounds.size.width) : nil
			} else {
				title = issuesTitle()
				tableView.tableFooterView = (count == 0) ? EmptyView(message: Issue.reasonForEmptyWithFilter(searchField.text), parentWidth: view.bounds.size.width) : nil
			}
			if let r = refreshControl {
				r.attributedTitle = NSAttributedString(string: api.lastUpdateDescription(), attributes: nil)
				if r.refreshing {
					r.endRefreshing()
				}
			}
		}

		app.updateBadge()

		if splitViewController?.displayMode != UISplitViewControllerDisplayMode.AllVisible {
			detailViewController.navigationItem.leftBarButtonItem?.title = title
		}

		tabBar?.selectedItem = (viewMode == .PullRequests) ? pullRequestsItem : issuesItem
	}

	private func unreadCommentCount(count: Int) -> String {
		return count == 0 ? "" : count == 1 ? " (1 new comment)" : " (\(count) new comments)"
	}

	private func pullRequestsTitle(long: Bool) -> String {

		let f = ListableItem.requestForItemsOfType("PullRequest", withFilter: nil, sectionIndex: -1)
		let count = mainObjectContext.countForFetchRequest(f, error: nil)
		let unreadCount = Int(pullRequestsItem.badgeValue ?? "0")!

		let pr = long ? "Pull Request" : "PR"
		if count == 0 {
			return "No \(pr)s"
		} else if count == 1 {
			return "1 " + (unreadCount > 0 ? "PR\(unreadCommentCount(unreadCount))" : pr)
		} else {
			return "\(count) " + (unreadCount > 0 ? "PRs\(unreadCommentCount(unreadCount))" : pr + "s")
		}
	}

	private func issuesTitle() -> String {
		let f = ListableItem.requestForItemsOfType("Issue", withFilter: nil, sectionIndex: -1)
		let count = mainObjectContext.countForFetchRequest(f, error: nil)
		let unreadCount = Int(issuesItem.badgeValue ?? "0")!

		if count == 0 {
			return "No Issues"
		} else if count == 1 {
			return "1 Issue\(unreadCommentCount(unreadCount))"
		} else {
			return "\(count) Issues\(unreadCommentCount(unreadCount))"
		}
	}

	///////////////////////////// filtering

	override func scrollViewWillBeginDragging(scrollView: UIScrollView) {
		if searchField.isFirstResponder() {
			searchField.resignFirstResponder()
		}
	}

	func textFieldShouldClear(textField: UITextField) -> Bool {
		searchTimer.push()
		return true
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			textField.resignFirstResponder()
		} else {
			searchTimer.push()
		}
		return true
	}

	////////////////// mode

	func showPullRequestsSelected(sender: AnyObject) {
		viewMode = .PullRequests
		safeScrollToTop()
	}

	func showIssuesSelected(sender: AnyObject) {
		viewMode = .Issues
		safeScrollToTop()
	}

	private func safeScrollToTop() {
		if self.numberOfSectionsInTableView(self.tableView) > 0 {
			self.tableView.scrollToRowAtIndexPath(NSIndexPath(forRow: 0, inSection: 0), atScrollPosition: .Top, animated: false)
		}
	}

	func focusFilter() {
		searchField.becomeFirstResponder()
	}

	private var _viewMode: MasterViewMode = .PullRequests
	var viewMode: MasterViewMode {
		set {
			if newValue != _viewMode {
				_viewMode = newValue
				_fetchedResultsController = nil
				tableView.reloadData()
				updateStatus()
			}
		}
		get {
			return _viewMode
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
		Settings.lastPreferencesTabSelected = tabBarController.viewControllers?.indexOf(viewController) ?? 0
	}
	
}
