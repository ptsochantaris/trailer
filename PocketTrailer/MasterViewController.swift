
import UIKit
import CoreData

final class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate, UISearchBarDelegate, UITabBarControllerDelegate, UITabBarDelegate {

	private var detailViewController: DetailViewController!
	private var _fetchedResultsController: NSFetchedResultsController?

	// Filtering
	@IBOutlet weak var searchBar: UISearchBar!
	private var searchTimer: PopTimer!

	// Refreshing
	@IBOutlet var refreshLabel: UILabel!
	private var refreshOnRelease = false

	private let pullRequestsItem = UITabBarItem()
	private let issuesItem = UITabBarItem()
	private var tabBar: UITabBar?
	private var forceSafari = false

	@IBAction func editSelected(sender: UIBarButtonItem ) {

		let a = UIAlertController(title: "Mark all \(viewMode.namePlural().lowercaseString) as read?", message: nil, preferredStyle: .Alert)
		a.addAction(UIAlertAction(title: "No", style: .Cancel) { action in
		})
		a.addAction(UIAlertAction(title: "Yes", style: .Default) { [weak self] action in
			self?.markAllAsRead()
		})
		presentViewController(a, animated: true, completion: nil)
	}

	private func tryRefresh() {
		refreshOnRelease = false

		if api.noNetworkConnection() {
			showMessage("No Network", "There is no network connectivity, please try again later")
			updateStatus()
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
				let a = UIAlertController(title: "Sure?", message: "Remove all \(S.viewMode.namePlural().lowercaseString) in the Merged section?", preferredStyle: .Alert)
				a.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style: .Destructive) { [weak S] action in
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
				let a = UIAlertController(title: "Sure?", message: "Remove all \(S.viewMode.namePlural().lowercaseString) in the Closed section?", preferredStyle: .Alert)
				a.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style: .Destructive) { [weak S] action in
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
		if refreshOnRelease {
			tryRefresh()
		}
	}

	override func scrollViewDidEndDecelerating(scrollView: UIScrollView) {
		if refreshOnRelease {
			tryRefresh()
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		refreshLabel.center = CGPointMake(CGRectGetMidX(view.bounds), refreshControl!.center.y+36)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		view.addSubview(refreshLabel)

		searchTimer = PopTimer(timeInterval: 0.5) { [weak self] in
			self?.reloadDataWithAnimation(true)
		}

		refreshControl?.addTarget(self, action: #selector(MasterViewController.refreshControlChanged), forControlEvents: .ValueChanged)

		tableView.rowHeight = UITableViewAutomaticDimension
		tableView.estimatedRowHeight = 240
		tableView.registerNib(UINib(nibName: "SectionHeaderView", bundle: nil), forHeaderFooterViewReuseIdentifier: "SectionHeaderView")
		tableView.contentOffset = CGPointMake(0, 44)

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

		updateStatus()
		updateTabBarVisibility(false)
	}

	override func canBecomeFirstResponder() -> Bool {
		return true
	}

	override var keyCommands: [UIKeyCommand]? {
		let f = UIKeyCommand(input: "f", modifierFlags: .Command, action: #selector(MasterViewController.focusFilter), discoverabilityTitle: "Filter items")
		let o = UIKeyCommand(input: "o", modifierFlags: .Command, action: #selector(MasterViewController.keyOpenInSafari), discoverabilityTitle: "Open in Safari")
		let a = UIKeyCommand(input: "a", modifierFlags: .Command, action: #selector(MasterViewController.keyToggleRead), discoverabilityTitle: "Mark item read/unread")
		let m = UIKeyCommand(input: "m", modifierFlags: .Command, action: #selector(MasterViewController.keyToggleMute), discoverabilityTitle: "Set item mute/unmute")
		let s = UIKeyCommand(input: "s", modifierFlags: .Command, action: #selector(MasterViewController.keyToggleSnooze), discoverabilityTitle: "Snooze/wake item")
		let r = UIKeyCommand(input: "r", modifierFlags: .Command, action: #selector(MasterViewController.keyForceRefresh), discoverabilityTitle: "Refresh now")
		let t = UIKeyCommand(input: "\t", modifierFlags: .Alternate, action: #selector(MasterViewController.keyFlipPrsAndIssues), discoverabilityTitle: "Switch between PRs and issues")
		let sp = UIKeyCommand(input: " ", modifierFlags: [], action: #selector(MasterViewController.keyShowSelectedItem), discoverabilityTitle: "Display current item")
		let d = UIKeyCommand(input: UIKeyInputDownArrow, modifierFlags: [], action: #selector(MasterViewController.keyMoveToNextItem), discoverabilityTitle: "Next item")
		let u = UIKeyCommand(input: UIKeyInputUpArrow, modifierFlags: [], action: #selector(MasterViewController.keyMoveToPreviousItem), discoverabilityTitle: "Previous item")
		let dd = UIKeyCommand(input: UIKeyInputDownArrow, modifierFlags: .Alternate, action: #selector(MasterViewController.keyMoveToNextSection), discoverabilityTitle: "Move to the next section")
		let uu = UIKeyCommand(input: UIKeyInputUpArrow, modifierFlags: .Alternate, action: #selector(MasterViewController.keyMoveToPreviousSection), discoverabilityTitle: "Move to the previous section")
		let fd = UIKeyCommand(input: UIKeyInputRightArrow, modifierFlags: .Command, action: #selector(MasterViewController.keyFocusDetailView), discoverabilityTitle: "Focus keyboard on detail view")
		let fm = UIKeyCommand(input: UIKeyInputLeftArrow, modifierFlags: .Command, action: #selector(MasterViewController.becomeFirstResponder), discoverabilityTitle: "Focus keyboard on list view")
		return [u,d,uu,dd,t,fd,fm,sp,f,r,a,m,o,s]
	}

	private func canIssueKeyForIndexPath(actionTitle: String, _ i: NSIndexPath) -> Bool {
		if let actions = tableView(tableView, editActionsForRowAtIndexPath: i) {
			for a in actions {
				if a.title == actionTitle {
					return true
				}
			}
		}
		showMessage("\(actionTitle) not available", "This command cannot be used on this item")
		return false
	}

	func keyToggleSnooze() {
		if let ip = tableView.indexPathForSelectedRow, i = fetchedResultsController.objectAtIndexPath(ip) as? ListableItem {
			if i.isSnoozing {
				if canIssueKeyForIndexPath("Wake", ip) {
					i.wakeUp()
					DataManager.saveDB()
					updateStatus()
				}
			} else {
				if canIssueKeyForIndexPath("Snooze", ip) {
					showSnoozeMenuFor(i)
				}
			}
		}
	}

	func keyToggleRead() {
		if let ip = tableView.indexPathForSelectedRow, i = fetchedResultsController.objectAtIndexPath(ip) as? ListableItem {
			if i.unreadComments?.integerValue ?? 0 > 0 {
				if canIssueKeyForIndexPath("Read", ip) {
					i.catchUpWithComments()
					DataManager.saveDB()
				}
			} else {
				if canIssueKeyForIndexPath("Unread", ip) {
					app.markItemAsUnRead(i.objectID.URIRepresentation().absoluteString, reloadView: false)
				}
			}
			updateStatus()
		}
	}

	func keyToggleMute() {
		if let ip = tableView.indexPathForSelectedRow, i = fetchedResultsController.objectAtIndexPath(ip) as? ListableItem {
			let isMuted = i.muted?.boolValue ?? false
			if (!isMuted && canIssueKeyForIndexPath("Mute", ip)) || (isMuted && canIssueKeyForIndexPath("Unmute", ip)) {
				i.setMute(!isMuted)
				DataManager.saveDB()
				updateStatus()
			}
		}
	}

	func keyForceRefresh() {
		if !appIsRefreshing {
			tryRefresh()
		}
	}

	func keyFocusDetailView() {
		showDetailViewController(detailViewController.navigationController ?? detailViewController, sender: self)
		detailViewController.becomeFirstResponder()
	}

	func keyOpenInSafari() {
		if let ip = tableView.indexPathForSelectedRow {
			forceSafari = true
			tableView(tableView, didSelectRowAtIndexPath: ip)
		}
	}

	func keyShowSelectedItem() {
		if let ip = tableView.indexPathForSelectedRow {
			tableView(tableView, didSelectRowAtIndexPath: ip)
		}
	}

	func keyMoveToNextItem() {
		if let ip = tableView.indexPathForSelectedRow {
			var newRow = ip.row+1
			var newSection = ip.section
			if newRow >= tableView.numberOfRowsInSection(ip.section) {
				newSection += 1
				if newSection >= tableView.numberOfSections {
					return; // end of the table
				}
				newRow = 0
			}
			tableView.selectRowAtIndexPath(NSIndexPath(forRow: newRow, inSection: newSection), animated: true, scrollPosition: .Middle)
		} else if numberOfSectionsInTableView(tableView) > 0 {
			tableView.selectRowAtIndexPath(NSIndexPath(forRow: 0, inSection: 0), animated: true, scrollPosition: .Top)
		}
	}

	func keyMoveToPreviousItem() {
		if let ip = tableView.indexPathForSelectedRow {
			var newRow = ip.row-1
			var newSection = ip.section
			if newRow < 0 {
				newSection -= 1
				if newSection < 0 {
					return; // start of the table
				}
				newRow = tableView.numberOfRowsInSection(newSection)-1
			}
			tableView.selectRowAtIndexPath(NSIndexPath(forRow: newRow, inSection: newSection), animated: true, scrollPosition: .Middle)
		} else if numberOfSectionsInTableView(tableView) > 0 {
			tableView.selectRowAtIndexPath(NSIndexPath(forRow: 0, inSection: 0), animated: true, scrollPosition: .Top)
		}
	}

	func keyMoveToPreviousSection() {
		if let ip = tableView.indexPathForSelectedRow {
			let newSection = ip.section-1
			if newSection < 0 {
				return; // start of table
			}
			tableView.selectRowAtIndexPath(NSIndexPath(forRow: 0, inSection: newSection), animated: true, scrollPosition: .Middle)
		} else if numberOfSectionsInTableView(tableView) > 0 {
			tableView.selectRowAtIndexPath(NSIndexPath(forRow: 0, inSection: 0), animated: true, scrollPosition: .Top)
		}
	}

	func keyMoveToNextSection() {
		if let ip = tableView.indexPathForSelectedRow {
			let newSection = ip.section+1
			if newSection >= tableView.numberOfSections {
				return; // end of table
			}
			tableView.selectRowAtIndexPath(NSIndexPath(forRow: 0, inSection: newSection), animated: true, scrollPosition: .Middle)
		} else if numberOfSectionsInTableView(tableView) > 0 {
			tableView.selectRowAtIndexPath(NSIndexPath(forRow: 0, inSection: 0), animated: true, scrollPosition: .Top)
		}
	}

	func keyFlipPrsAndIssues() {
		if tabBar != nil {
			viewMode = (viewMode == .PullRequests) ? .Issues : .PullRequests
		}
	}

	func tabBar(tabBar: UITabBar, didSelectItem item: UITabBarItem) {
		if tabBar.items?.indexOf(item) == 0 {
			showPullRequestsSelected(tabBar)
		} else {
			showIssuesSelected(tabBar)
		}
	}

	override func scrollViewDidScroll(scrollView: UIScrollView) {
		updateRefreshControls()
	}

	private func updateRefreshControls() {
		let ra = min(1.0, max(0, (-84-tableView.contentOffset.y)/32.0))
		if ra > 0.0 && refreshLabel.alpha == 0 {
			refreshLabel.text = api.lastUpdateDescription()
		}
		refreshLabel.alpha = ra
		refreshControl?.alpha = ra
		searchBar.alpha = min(1.0, max(0, ((116+tableView.contentOffset.y)/32.0)))
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

		if urlToOpen != nil && !S(searchBar.text).isEmpty {
			searchBar.text = nil
			searchBar.resignFirstResponder()
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

		if !isFirstResponder() {
			becomeFirstResponder()
		}

		let fs = forceSafari
		forceSafari = false

		func openItem(item: ListableItem, url: NSURL, oid: NSManagedObjectID) {
			if forceSafari || (Settings.openItemsDirectlyInSafari && !detailViewController.isVisible) {
				item.catchUpWithComments()
				UIApplication.sharedApplication().openURL(url)
			} else {
				showDetail(url, objectId: oid)
			}
		}

		if viewMode == .PullRequests, let
			p = fetchedResultsController.objectAtIndexPath(indexPath) as? PullRequest,
			u = p.urlForOpening(),
			url = NSURL(string: u)
		{
			openItem(p, url: url, oid: p.objectID)
		} else if viewMode == .Issues, let
			i = fetchedResultsController.objectAtIndexPath(indexPath) as? Issue,
			u = i.urlForOpening(),
			url = NSURL(string: u)
		{
			openItem(i, url: url, oid: i.objectID)
		}
	}

	private func showDetail(url: NSURL?, objectId: NSManagedObjectID?) {
		detailViewController.catchupWithDataItemWhenLoaded = objectId
		detailViewController.detailItem = url
		if !detailViewController.isVisible {
			showTabBar(false, animated: true)
			showDetailViewController(detailViewController.navigationController ?? detailViewController, sender: self)
		}
	}

	override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		let v = tableView.dequeueReusableHeaderFooterViewWithIdentifier("SectionHeaderView") as! SectionHeaderView
		let name = S(fetchedResultsController.sections?[section].name)
		v.title.text = name.uppercaseString
		if viewMode == .PullRequests {
			if name == Section.Closed.prMenuName() {
				v.action.hidden = false
				v.callback = { [weak self] in
					self?.removeAllClosed()
				}
			} else if name == Section.Merged.prMenuName() {
				v.action.hidden = false
				v.callback = { [weak self] in
					self?.removeAllMerged()
				}
			} else {
				v.action.hidden = true
			}
		} else {
			if name == Section.Closed.issuesMenuName() {
				v.action.hidden = false
				v.callback = { [weak self] in
					self?.removeAllClosed()
				}
			} else {
				v.action.hidden = true
			}
		}
		return v
	}

	override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 64
	}

	override func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		if section==numberOfSectionsInTableView(tableView)-1 {
			return tabBar == nil ? 20 : 20+49
		}
		return 1
	}

	override func tableView(tableView: UITableView, editActionsForRowAtIndexPath indexPath: NSIndexPath) -> [UITableViewRowAction]? {

		var actions = [UITableViewRowAction]()

		func appendReadUnread(i: ListableItem) {
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
		}

		func appendMuteUnmute(i: ListableItem) {
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
		}

		if let i = fetchedResultsController.objectAtIndexPath(indexPath) as? ListableItem, sectionName = fetchedResultsController.sections?[indexPath.section].name {

			if sectionName == Section.Merged.prMenuName() || sectionName == Section.Closed.prMenuName() || sectionName == Section.Closed.issuesMenuName() {

				appendReadUnread(i)
				let d = UITableViewRowAction(style: .Destructive, title: "Remove") { action, indexPath in
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

				appendReadUnread(i)
				appendMuteUnmute(i)
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
		let fetchRequest = ListableItem.requestForItemsOfType(type, withFilter: searchBar.text, sectionIndex: -1)

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
				tableView.tableFooterView = EmptyView(message: PullRequest.reasonForEmptyWithFilter(searchBar.text), parentWidth: view.bounds.size.width)
			} else {
				tableView.tableFooterView = EmptyView(message: Issue.reasonForEmptyWithFilter(searchBar.text), parentWidth: view.bounds.size.width)
			}
			if let r = refreshControl {
				refreshLabel.text = api.lastUpdateDescription()
				updateRefreshControls()
				r.beginRefreshing()
			}
		} else {

			let count = fetchedResultsController.fetchedObjects?.count ?? 0
			if viewMode == .PullRequests {
				title = pullRequestsTitle(true)
				tableView.tableFooterView = (count == 0) ? EmptyView(message: PullRequest.reasonForEmptyWithFilter(searchBar.text), parentWidth: view.bounds.size.width) : nil
			} else {
				title = issuesTitle()
				tableView.tableFooterView = (count == 0) ? EmptyView(message: Issue.reasonForEmptyWithFilter(searchBar.text), parentWidth: view.bounds.size.width) : nil
			}
			if let r = refreshControl {
				refreshLabel.text = api.lastUpdateDescription()
				updateRefreshControls()
				r.endRefreshing()
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
			let suffix = unreadCount > 0 ? "PR\(unreadCommentCount(unreadCount))" : pr
			return "1 \(suffix)"
		} else {
			let suffix = unreadCount > 0 ? "PRs\(unreadCommentCount(unreadCount))" : "\(pr)s"
			return "\(count) \(suffix)"
		}
	}

	private func issuesTitle() -> String {
		let f = ListableItem.requestForItemsOfType("Issue", withFilter: nil, sectionIndex: -1)
		let count = mainObjectContext.countForFetchRequest(f, error: nil)
		let unreadCount = Int(issuesItem.badgeValue ?? "0")!

		if count == 0 {
			return "No Issues"
		} else if count == 1 {
			let commentCount = unreadCommentCount(unreadCount)
			return "1 Issue\(commentCount)"
		} else {
			let commentCount = unreadCommentCount(unreadCount)
			return "\(count) Issues\(commentCount)"
		}
	}

	///////////////////////////// filtering

	override func scrollViewWillBeginDragging(scrollView: UIScrollView) {
		becomeFirstResponder()
	}

	func searchBarTextDidBeginEditing(searchBar: UISearchBar) {
		if let r = refreshControl where r.refreshing ?? false {
			r.endRefreshing()
		}
		searchBar.setShowsCancelButton(true, animated: true)
	}

	func searchBarTextDidEndEditing(searchBar: UISearchBar) {
		searchBar.setShowsCancelButton(false, animated: true)
	}

	func searchBar(searchBar: UISearchBar, textDidChange searchText: String) {
		searchTimer.push()
	}

	func searchBarCancelButtonClicked(searchBar: UISearchBar) {
		searchBar.text = nil
		searchTimer.push()
		view.endEditing(false)
	}

	func searchBar(searchBar: UISearchBar, shouldChangeTextInRange range: NSRange, replacementText text: String) -> Bool {
		if text == "\n" {
			view.endEditing(false)
			return false
		} else {
			return true
		}
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
		safeScrollToTop()
		searchBar.becomeFirstResponder()
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
