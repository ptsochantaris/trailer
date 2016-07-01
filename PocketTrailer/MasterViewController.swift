
import UIKit
import CoreData

final class TabBarSet {
	var prItem: UITabBarItem?
	var issuesItem: UITabBarItem?
	let viewCriterion: GroupingCriterion?

	var tabItems: [UITabBarItem] {

		let label = viewCriterion?.label
		var items = [UITabBarItem]()

		let prf = ListableItem.requestForItemsOfType("PullRequest", withFilter: nil, sectionIndex: -1, criterion: viewCriterion)
		if mainObjectContext.countForFetchRequest(prf, error: nil) > 0 {
			let i = UITabBarItem(title: label ?? "Pull Requests", image: UIImage(named: "prsTab"), selectedImage: nil)
			let prUnreadCount = PullRequest.badgeCountInMoc(mainObjectContext, criterion: viewCriterion)
			i.badgeValue = prUnreadCount > 0 ? "\(prUnreadCount)" : nil
			items.append(i)
			prItem = i
		}
		let isf = ListableItem.requestForItemsOfType("Issue", withFilter: nil, sectionIndex: -1, criterion: viewCriterion)
		if mainObjectContext.countForFetchRequest(isf, error: nil) > 0 {
			let i = UITabBarItem(title: label ?? "Issues", image: UIImage(named: "issuesTab"), selectedImage: nil)
			let issuesUnreadCount = Issue.badgeCountInMoc(mainObjectContext, criterion: viewCriterion)
			i.badgeValue = issuesUnreadCount > 0 ? "\(issuesUnreadCount)" : nil
			items.append(i)
			issuesItem = i
		}
		return items
	}

	init(viewCriterion: GroupingCriterion?) {
		self.viewCriterion = viewCriterion
	}
}

final class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate, UISearchBarDelegate, UITabBarControllerDelegate, UITabBarDelegate {

	private var detailViewController: DetailViewController!
	private var _fetchedResultsController: NSFetchedResultsController?

	// Tabs
	private var tabs: UITabBar?
	private var tabSide1: UIView?
	private var tabSide2: UIView?
	private var tabScroll: UIScrollView?
	private var tabBorder: UIView?
	private var tabBarSets = [TabBarSet]()
	private var currentTabBarSet: TabBarSet?

	// Filtering
	@IBOutlet weak var searchBar: UISearchBar!
	private var searchTimer: PopTimer!

	// Refreshing
	@IBOutlet var refreshLabel: UILabel!
	private var refreshOnRelease = false

	private var forceSafari = false

	private func pluralNameForItems() -> String {
		return viewingPrs ? "pull requests" : "issues"
	}

	func allTabSets() -> [TabBarSet] {
		return tabBarSets
	}

	@IBAction func editSelected(sender: UIBarButtonItem ) {

		let promptTitle: String
		if let l = currentTabBarSet?.viewCriterion?.label {
			promptTitle = "\(pluralNameForItems().capitalizedString) in '\(l)'"
		} else {
			promptTitle = pluralNameForItems().capitalizedString
		}

		let a = UIAlertController(title: promptTitle, message: "Mark all as read?", preferredStyle: .Alert)
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
				let a = UIAlertController(title: "Sure?", message: "Remove all \(S.pluralNameForItems()) in the Merged section?", preferredStyle: .Alert)
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
				let a = UIAlertController(title: "Sure?", message: "Remove all \(S.pluralNameForItems()) in the Closed section?", preferredStyle: .Alert)
				a.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style: .Destructive) { [weak S] action in
					S?.removeAllClosedConfirmed()
				})
				S.presentViewController(a, animated: true, completion: nil)
			}
		}
	}

	func removeAllClosedConfirmed() {
		if viewingPrs {
			for p in PullRequest.allClosedInMoc(mainObjectContext, criterion: currentTabBarSet?.viewCriterion) {
				mainObjectContext.deleteObject(p)
			}
		} else {
			for p in Issue.allClosedInMoc(mainObjectContext, criterion: currentTabBarSet?.viewCriterion) {
				mainObjectContext.deleteObject(p)
			}
		}
		DataManager.saveDB()
	}

	func removeAllMergedConfirmed() {
		if viewingPrs {
			for p in PullRequest.allMergedInMoc(mainObjectContext, criterion: currentTabBarSet?.viewCriterion) {
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
		updateStatus()
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
		layoutTabs()
	}

	func layoutTabs() {
		if let v = navigationController?.view, t = tabs, ts = tabScroll, tb = tabBorder, ts1 = tabSide1, ts2 = tabSide2 {
			let b = v.bounds.size
			let w = b.width
			let h = b.height
			let tabScrollTransform = ts.transform
			let tabBorderTransform = tb.transform

			let tf = CGRectMake(0, 0, max(w, 64*CGFloat(t.items?.count ?? 1)), 49)
			t.frame = tf
			ts.contentSize = tf.size

			ts.frame = CGRectMake(0, h-49, w, 49)
			ts.transform = tabScrollTransform

			tb.frame = CGRectMake(0, h-49.5, w, 0.5)
			tb.transform = tabBorderTransform

			let ww = w*0.5
			ts1.frame = CGRectMake(-ww, 0, ww, 49)
			ts2.frame = CGRectMake(w, 0, ww, 49)

			if navigationController?.visibleViewController == self || navigationController?.visibleViewController?.presentingViewController != nil {
				v.bringSubviewToFront(tb)
				v.bringSubviewToFront(ts)
			} else {
				v.sendSubviewToBack(tb)
				v.sendSubviewToBack(ts)
			}
		}
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		updateStatus()
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		view.addSubview(refreshLabel)

		searchTimer = PopTimer(timeInterval: 0.5) { [weak self] in
			self?.applyFilter()
		}

		refreshControl?.addTarget(self, action: #selector(MasterViewController.refreshControlChanged), forControlEvents: .ValueChanged)

		tableView.rowHeight = UITableViewAutomaticDimension
		tableView.estimatedRowHeight = 240
		tableView.registerNib(UINib(nibName: "SectionHeaderView", bundle: nil), forHeaderFooterViewReuseIdentifier: "SectionHeaderView")
		tableView.contentOffset = CGPointMake(0, 44)
		clearsSelectionOnViewWillAppear = false

		if let detailNav = splitViewController?.viewControllers.last as? UINavigationController {
			detailViewController = detailNav.topViewController as? DetailViewController
		}

		let n = NSNotificationCenter.defaultCenter()
		n.addObserver(self, selector: #selector(MasterViewController.updateStatus), name:REFRESH_STARTED_NOTIFICATION, object: nil)
		n.addObserver(self, selector: #selector(MasterViewController.updateStatus), name:REFRESH_ENDED_NOTIFICATION, object: nil)
		n.addObserver(self, selector: #selector(MasterViewController.updateRefresh), name: kSyncProgressUpdate, object: nil)

		updateTabItems(false)
		atNextEvent {
			self.tableView.reloadData() // ensure footers are correct
		}
	}

	func updateRefresh() {
		refreshLabel.text = api.lastUpdateDescription()
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
		let nt = UIKeyCommand(input: "\t", modifierFlags: .Alternate, action: #selector(MasterViewController.moveToNextTab), discoverabilityTitle: "Move to next tab")
		let pt = UIKeyCommand(input: "\t", modifierFlags: [.Alternate, .Shift], action: #selector(MasterViewController.moveToPreviousTab), discoverabilityTitle: "Move to previous tab")
		let sp = UIKeyCommand(input: " ", modifierFlags: [], action: #selector(MasterViewController.keyShowSelectedItem), discoverabilityTitle: "Display current item")
		let d = UIKeyCommand(input: UIKeyInputDownArrow, modifierFlags: [], action: #selector(MasterViewController.keyMoveToNextItem), discoverabilityTitle: "Next item")
		let u = UIKeyCommand(input: UIKeyInputUpArrow, modifierFlags: [], action: #selector(MasterViewController.keyMoveToPreviousItem), discoverabilityTitle: "Previous item")
		let dd = UIKeyCommand(input: UIKeyInputDownArrow, modifierFlags: .Alternate, action: #selector(MasterViewController.keyMoveToNextSection), discoverabilityTitle: "Move to the next section")
		let uu = UIKeyCommand(input: UIKeyInputUpArrow, modifierFlags: .Alternate, action: #selector(MasterViewController.keyMoveToPreviousSection), discoverabilityTitle: "Move to the previous section")
		let fd = UIKeyCommand(input: UIKeyInputRightArrow, modifierFlags: .Command, action: #selector(MasterViewController.keyFocusDetailView), discoverabilityTitle: "Focus keyboard on detail view")
		let fm = UIKeyCommand(input: UIKeyInputLeftArrow, modifierFlags: .Command, action: #selector(MasterViewController.becomeFirstResponder), discoverabilityTitle: "Focus keyboard on list view")
		return [u,d,uu,dd,nt,pt,fd,fm,sp,f,r,a,m,o,s]
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
					markItemAsUnRead(i.objectID.URIRepresentation().absoluteString)
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

	func moveToNextTab() {
		if let t = tabs, i = t.selectedItem, items = t.items, ind = items.indexOf(i) where items.count > 1 {
			var nextIndex = ind+1
			if nextIndex >= items.count {
				nextIndex = 0
			}
			requestTabFocus(items[nextIndex])
		}
	}

	func moveToPreviousTab() {
		if let t = tabs, i = t.selectedItem, items = t.items, ind = items.indexOf(i) where items.count > 1 {
			var nextIndex = ind-1
			if nextIndex < 0 {
				nextIndex = items.count-1
			}
			requestTabFocus(items[nextIndex])
		}
	}

	private func requestTabFocus(item: UITabBarItem?) {
		if let i = item {
			lastTabIndex = tabs?.items?.indexOf(i) ?? 0
			resetView()
		}
	}

	private func tabBarSetForTabItem(i: UITabBarItem?) -> TabBarSet? {

		guard let i = i else { return tabBarSets.first }

		for s in tabBarSets {
			if s.prItem === i || s.issuesItem === i {
				return s
			}
		}
		return nil
	}

	func tabBar(tabBar: UITabBar, didSelectItem item: UITabBarItem) {
		lastTabIndex = tabs?.items?.indexOf(item) ?? 0
		resetView()
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

	private func applyFilter() {

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
			tableView.deleteSections(removedIndexes, withRowAnimation:.Automatic)
		}
		if untouchedIndexes.count > 0 {
			tableView.reloadSections(untouchedIndexes, withRowAnimation:.Automatic)
		}
		if addedIndexes.count > 0 {
			tableView.insertSections(addedIndexes, withRowAnimation:.Automatic)
		}
		tableView.endUpdates()
	}

	private func updateTabItems(animated: Bool) {

		tabBarSets.removeAll()

		for groupLabel in Repo.allGroupLabels {
			let c = GroupingCriterion(repoGroup: groupLabel)
			let s = TabBarSet(viewCriterion: c)
			tabBarSets.append(s)
		}

		if Settings.showSeparateApiServersInMenu {
			for a in ApiServer.allApiServersInMoc(mainObjectContext) {
				if a.goodToGo {
					let c = GroupingCriterion(apiServerId: a.objectID)
					let s = TabBarSet(viewCriterion: c)
					tabBarSets.append(s)
				}
			}
		} else {
			let s = TabBarSet(viewCriterion: nil)
			tabBarSets.append(s)
		}

		var items = [UITabBarItem]()
		for d in tabBarSets {
			items.appendContentsOf(d.tabItems)
		}

		if items.count > 1 {
			showEmpty = false
			showTabBar(true, animated: animated)

			tabs?.items = items
			tabs?.superview?.setNeedsLayout()

			if items.count > lastTabIndex {
				tabs?.selectedItem = items[lastTabIndex]
				currentTabBarSet = tabBarSetForTabItem(items[lastTabIndex])
			} else {
				tabs?.selectedItem = items.last
				currentTabBarSet = tabBarSetForTabItem(items.last!)
			}
		} else {
			showEmpty = items.count == 0
			currentTabBarSet = tabBarSetForTabItem(items.first)
			showTabBar(false, animated: animated)
		}

		if let i = tabs?.selectedItem?.image {
			viewingPrs = i == UIImage(named: "prsTab") // not proud of this :(
		} else if let c = currentTabBarSet {
			viewingPrs = c.tabItems.first?.image == UIImage(named: "prsTab") // or this :(
		} else if Repo.anyVisibleReposInMoc(mainObjectContext, criterion: currentTabBarSet?.viewCriterion, excludeGrouped: true) {
			viewingPrs = Repo.interestedInPrs(currentTabBarSet?.viewCriterion?.apiServerId)
		} else {
			viewingPrs = true
		}

		let newCount = tabs?.items?.count ?? 0

		let latestFetchRequest = _fetchedResultsController?.fetchRequest
		let newFetchRequest = createFetchRequest()

		if newCount != lastTabCount || latestFetchRequest != newFetchRequest {
			_fetchedResultsController = nil
			tableView.reloadData()
		}

		if let ts = tabScroll, t = tabs, i = t.selectedItem, ind = t.items?.indexOf(i) {
			let w = t.bounds.size.width / CGFloat(t.items?.count ?? 1)
			let x = w*CGFloat(ind)
			let f = CGRectMake(x, 0, w, t.bounds.size.height)
			ts.scrollRectToVisible(f, animated: true)
		}

		lastTabCount = tabs?.items?.count ?? 0
		if let i = tabs?.selectedItem, ind = tabs?.items?.indexOf(i) {
			lastTabIndex = ind
		} else {
			lastTabIndex = 0
		}
	}

	private var lastTabIndex = 0
	private var lastTabCount = 0
	private func showTabBar(show: Bool, animated: Bool) {
		if show {

			if tabScroll == nil, let s = navigationController?.view {

				tableView.scrollIndicatorInsets = UIEdgeInsets(top: tableView.scrollIndicatorInsets.top, left: 0, bottom: 49, right: 0)

				let t = UITabBar()
				t.delegate = self
				t.itemPositioning = .Fill
				tabs = t

				let ts = UIScrollView()
				ts.showsHorizontalScrollIndicator = false
				ts.alwaysBounceHorizontal = true
				ts.scrollsToTop = false
				ts.addSubview(t)

				let s1 = UIVisualEffectView(effect: UIBlurEffect(style: .ExtraLight))
				tabSide1 = s1
				ts.addSubview(s1)

				let s2 = UIVisualEffectView(effect: UIBlurEffect(style: .ExtraLight))
				tabSide2 = s2
				ts.addSubview(s2)

				let b = UIView()
				b.backgroundColor = UIColor.blackColor().colorWithAlphaComponent(0.32)
				b.userInteractionEnabled = false
				s.addSubview(b)
				tabBorder = b

				s.addSubview(ts)
				tabScroll = ts

				if animated {
					ts.transform = CGAffineTransformMakeTranslation(0, 49)
					b.transform = CGAffineTransformMakeTranslation(0, 49)
					UIView.animateWithDuration(0.2,
						delay: 0.0,
						options: .CurveEaseInOut,
						animations: {
							ts.transform = CGAffineTransformIdentity
							b.transform = CGAffineTransformIdentity
						}, completion: nil)
				}
			}

		} else {

			tableView.scrollIndicatorInsets = UIEdgeInsets(top: tableView.scrollIndicatorInsets.top, left: 0, bottom: 0, right: 0)

			if let t = tabScroll, b = tabBorder {

				tabs = nil
				tabScroll = nil
				tabBorder = nil
				tabSide1 = nil
				tabSide2 = nil

				if animated {
					UIView.animateWithDuration(0.2,
						delay: 0.0,
						options: .CurveEaseInOut,
						animations: {
							t.transform = CGAffineTransformMakeTranslation(0, 49)
							b.transform = CGAffineTransformMakeTranslation(0, 49)
						}, completion: { finished in
							t.removeFromSuperview()
							b.removeFromSuperview()
						})
				} else {
					t.removeFromSuperview()
					b.removeFromSuperview()
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
		} else if let uri = (userInfo[PULL_REQUEST_ID_KEY] ?? userInfo[ISSUE_ID_KEY]) as? String, itemId = DataManager.idForUriPath(uri) {
			relatedItem = existingObjectWithID(itemId) as? ListableItem
			if relatedItem == nil {
				showMessage("Item not found", "Could not locate the item related to this notification")
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
			resetView()
		}

		var oid: NSManagedObjectID?

		if let i = relatedItem {
			selectTabFor(i)
			oid = i.objectID
			atNextEvent(self) { S in
				if let ip = S.fetchedResultsController.indexPathForObject(i) {
					S.tableView.selectRowAtIndexPath(ip, animated: false, scrollPosition: .Middle)
				}
			}
		}

		if let u = urlToOpen, url = NSURL(string: u) {
			showDetail(url, objectId: oid)
		} else {
			showDetail(nil, objectId: nil)
		}
	}

	private func selectTabFor(i: ListableItem) {
		for d in tabBarSets {
			if d.viewCriterion == nil || d.viewCriterion?.isRelatedTo(i) ?? false {
				if i is PullRequest {
					requestTabFocus(d.prItem)
				} else {
					requestTabFocus(d.issuesItem)
				}
			}
		}
	}

	func openItemWithUriPath(uriPath: String) {
		if let
			itemId = DataManager.idForUriPath(uriPath),
			item = existingObjectWithID(itemId) as? ListableItem,
			ip = fetchedResultsController.indexPathForObject(item)
		{
			selectTabFor(item)
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
				if let item = comment.pullRequest ?? comment.issue {
					selectTabFor(item)
					ip = fetchedResultsController.indexPathForObject(item)
					item.catchUpWithComments()
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

		if let
			p = fetchedResultsController.objectAtIndexPath(indexPath) as? ListableItem,
			u = p.urlForOpening(),
			url = NSURL(string: u)
		{
			if forceSafari || (Settings.openItemsDirectlyInSafari && !detailViewController.isVisible) {
				p.catchUpWithComments()
				UIApplication.sharedApplication().openURL(url)
			} else {
				showDetail(url, objectId: p.objectID)
			}
		}

		forceSafari = false
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
		if viewingPrs {
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
			return tabs == nil ? 20 : 20+49
		}
		return 1
	}

	private func markItemAsUnRead(itemUri: String?) {
		if let
			i = itemUri,
			oid = DataManager.idForUriPath(i),
			o = existingObjectWithID(oid) as? ListableItem {
			o.latestReadCommentDate = never()
			o.postProcess()
			DataManager.saveDB()
			popupManager.getMasterController().updateStatus()
		}
	}

	override func tableView(tableView: UITableView, editActionsForRowAtIndexPath indexPath: NSIndexPath) -> [UITableViewRowAction]? {

		var actions = [UITableViewRowAction]()

		func markItemAsRead(itemUri: String?) {
			if let
				i = itemUri,
				oid = DataManager.idForUriPath(i),
				o = existingObjectWithID(oid) as? ListableItem {
				o.catchUpWithComments()
				DataManager.saveDB()
				popupManager.getMasterController().updateStatus()
			}
		}

		func appendReadUnread(i: ListableItem) {
			let r: UITableViewRowAction
			if i.unreadComments?.longLongValue ?? 0 > 0 {
				r = UITableViewRowAction(style: .Normal, title: "Read") { action, indexPath in
					markItemAsRead(i.objectID.URIRepresentation().absoluteString)
					tableView.setEditing(false, animated: true)
				}
			} else {
				r = UITableViewRowAction(style: .Normal, title: "Unread") { [weak self] action, indexPath in
					self?.markItemAsUnRead(i.objectID.URIRepresentation().absoluteString)
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

				if Settings.showCommentsEverywhere || (sectionName != Section.All.prMenuName() && sectionName != Section.All.issuesMenuName()) {
					appendReadUnread(i)
				}
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

		let c = NSFetchedResultsController(fetchRequest: createFetchRequest(), managedObjectContext: mainObjectContext, sectionNameKeyPath: "sectionName", cacheName: nil)
		_fetchedResultsController = c
		c.delegate = self
		try! c.performFetch()
		return c
	}

	private func createFetchRequest() -> NSFetchRequest {
		let type = viewingPrs ? "PullRequest" : "Issue"
		return ListableItem.requestForItemsOfType(type, withFilter: searchBar.text, sectionIndex: -1, criterion: currentTabBarSet?.viewCriterion)
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
				if o is PullRequest {
					c.setPullRequest(o as! PullRequest)
				} else {
					c.setIssue(o as! Issue)
				}
			}
		}
	}

	private var viewingPrs = true
	private var showEmpty = true

	func updateStatus() {

		updateTabItems(true)
		let empty = (fetchedResultsController.fetchedObjects?.count ?? 0) == 0

		if appIsRefreshing {
			title = "Refreshing..."
			if viewingPrs {
				tableView.tableFooterView = empty ? EmptyView(message: PullRequest.reasonForEmptyWithFilter(searchBar.text, criterion: currentTabBarSet?.viewCriterion), parentWidth: view.bounds.size.width) : nil
			} else {
				tableView.tableFooterView = empty ? EmptyView(message: Issue.reasonForEmptyWithFilter(searchBar.text, criterion: currentTabBarSet?.viewCriterion), parentWidth: view.bounds.size.width) : nil
			}
			if let r = refreshControl {
				refreshLabel.text = api.lastUpdateDescription()
				updateRefreshControls()
				r.beginRefreshing()
			}
		} else {

			if showEmpty {
				title = "No Items"
				if viewingPrs {
					tableView.tableFooterView = empty ? EmptyView(message: PullRequest.reasonForEmptyWithFilter(searchBar.text, criterion: currentTabBarSet?.viewCriterion), parentWidth: view.bounds.size.width) : nil
				} else {
					tableView.tableFooterView = empty ? EmptyView(message: Issue.reasonForEmptyWithFilter(searchBar.text, criterion: currentTabBarSet?.viewCriterion), parentWidth: view.bounds.size.width) : nil
				}
			} else if viewingPrs {
				title = pullRequestsTitle(true)
				tableView.tableFooterView = empty ? EmptyView(message: PullRequest.reasonForEmptyWithFilter(searchBar.text, criterion: currentTabBarSet?.viewCriterion), parentWidth: view.bounds.size.width) : nil
			} else {
				title = issuesTitle()
				tableView.tableFooterView = empty ? EmptyView(message: Issue.reasonForEmptyWithFilter(searchBar.text, criterion: currentTabBarSet?.viewCriterion), parentWidth: view.bounds.size.width) : nil
			}
			if let r = refreshControl {
				refreshLabel.text = api.lastUpdateDescription()
				updateRefreshControls()
				r.endRefreshing()
			}
		}

		app.updateBadge()

		if splitViewController?.displayMode != .AllVisible {
			detailViewController.navigationItem.leftBarButtonItem?.title = title
		}
	}

	private func unreadCommentCount(count: Int) -> String {
		return count == 0 ? "" : count == 1 ? " (1 new comment)" : " (\(count) new comments)"
	}

	private func pullRequestsTitle(long: Bool) -> String {

		let f = ListableItem.requestForItemsOfType("PullRequest", withFilter: nil, sectionIndex: -1, criterion: currentTabBarSet?.viewCriterion)
		let count = mainObjectContext.countForFetchRequest(f, error: nil)
		let unreadCount = Int(currentTabBarSet?.prItem?.badgeValue ?? "0")!

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

		let f = ListableItem.requestForItemsOfType("Issue", withFilter: nil, sectionIndex: -1, criterion: currentTabBarSet?.viewCriterion)
		let count = mainObjectContext.countForFetchRequest(f, error: nil)
		let unreadCount = Int(currentTabBarSet?.issuesItem?.badgeValue ?? "0")!

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

	private func safeScrollToTop() {
		tableView.contentOffset = tableView.contentOffset // halt any inertial scrolling
		atNextEvent(self) { S in
			let t = S.tableView
			if t.numberOfSections > 0 {
				t.scrollToRowAtIndexPath(NSIndexPath(forRow: 0, inSection: 0), atScrollPosition: .Top, animated: false)
			}
		}
	}

	func focusFilter() {
		tableView.contentOffset = CGPointMake(0, -tableView.contentInset.top)
		searchBar.becomeFirstResponder()
	}

	func resetView() {
		safeScrollToTop()
		_fetchedResultsController = nil
		updateStatus()
		tableView.reloadData()
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
