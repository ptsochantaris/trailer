
import UIKit
import CoreData
import UserNotifications

final class TabBarSet {
	var prItem: UITabBarItem?
	var issuesItem: UITabBarItem?
	let viewCriterion: GroupingCriterion?

	var tabItems: [UITabBarItem] {

		let label = viewCriterion?.label
		var items = [UITabBarItem]()

		let prf = ListableItem.requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: viewCriterion)
		if try! DataManager.main.count(for: prf) > 0 {
			let i = UITabBarItem(title: label ?? "Pull Requests", image: UIImage(named: "prsTab"), selectedImage: nil)
			let prUnreadCount = PullRequest.badgeCount(in: DataManager.main, criterion: viewCriterion)
			i.badgeValue = prUnreadCount > 0 ? "\(prUnreadCount)" : nil
			items.append(i)
			prItem = i
		}
		let isf = ListableItem.requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: viewCriterion)
		if try! DataManager.main.count(for: isf) > 0 {
			let i = UITabBarItem(title: label ?? "Issues", image: UIImage(named: "issuesTab"), selectedImage: nil)
			let issuesUnreadCount = Issue.badgeCount(in: DataManager.main, criterion: viewCriterion)
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

final class CustomTabBar: UITabBar {
	override var traitCollection: UITraitCollection {
		return UITraitCollection(horizontalSizeClass: .compact)
	}
}

final class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate,
UITabBarControllerDelegate, UITabBarDelegate, UISearchResultsUpdating,
UITableViewDragDelegate {

	private var detailViewController: DetailViewController!
	private var fetchedResultsController: NSFetchedResultsController<ListableItem>!

	// Tabs
	private var tabs: CustomTabBar?
	private var tabScroll: UIScrollView?
	private var tabBorder: UIView?
	private var tabBarSets = [TabBarSet]()
	private var currentTabBarSet: TabBarSet?

	private var searchTimer: PopTimer!
	private var forceSafari = false

	private var pluralNameForItems: String {
		return viewingPrs ? "pull requests" : "issues"
	}

	var allTabSets: [TabBarSet] {
		return tabBarSets
	}

	@IBAction func editSelected(_ sender: UIBarButtonItem ) {

		let promptTitle: String
		if let l = currentTabBarSet?.viewCriterion?.label {
			promptTitle = "\(pluralNameForItems.capitalized) in '\(l)'"
		} else {
			promptTitle = pluralNameForItems.capitalized
		}

		let a = UIAlertController(title: promptTitle, message: "Mark all as read?", preferredStyle: .alert)
		a.addAction(UIAlertAction(title: "No", style: .cancel) { action in
		})
		a.addAction(UIAlertAction(title: "Yes", style: .default) { action in
			self.markAllAsRead()
		})
		present(a, animated: true)
	}

	func removeAllMerged() {
		atNextEvent(self) { S in
			if Settings.dontAskBeforeWipingMerged {
				S.removeAllMergedConfirmed()
			} else {
				let a = UIAlertController(title: "Sure?", message: "Remove all \(S.pluralNameForItems) in the Merged section?", preferredStyle: .alert)
				a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak S] action in
					S?.removeAllMergedConfirmed()
				})
				S.present(a, animated: true)
			}
		}
	}

	func removeAllClosed() {
		atNextEvent(self) { S in
			if Settings.dontAskBeforeWipingClosed {
				S.removeAllClosedConfirmed()
			} else {
				let a = UIAlertController(title: "Sure?", message: "Remove all \(S.pluralNameForItems) in the Closed section?", preferredStyle: .alert)
				a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
				a.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak S] action in
					S?.removeAllClosedConfirmed()
				})
				S.present(a, animated: true)
			}
		}
	}

	func removeAllClosedConfirmed() {
		if viewingPrs {
			for p in PullRequest.allClosed(in: DataManager.main, criterion: currentTabBarSet?.viewCriterion) {
				DataManager.main.delete(p)
			}
		} else {
			for p in Issue.allClosed(in: DataManager.main, criterion: currentTabBarSet?.viewCriterion) {
				DataManager.main.delete(p)
			}
		}
	}

	func removeAllMergedConfirmed() {
		if viewingPrs {
			for p in PullRequest.allMerged(in: DataManager.main, criterion: currentTabBarSet?.viewCriterion) {
				DataManager.main.delete(p)
			}
		}
	}

	func markAllAsRead() {
		for i in fetchedResultsController.fetchedObjects ?? [] {
			i.catchUpWithComments()
		}
	}

	@objc private func refreshControlChanged(_ sender: UIRefreshControl) {
		if sender.isRefreshing {
			keyForceRefresh()
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateStatus(becauseOfChanges: false, updateItems: true)
		tabs?.setNeedsLayout() // iPhone X bug?

		if let s = splitViewController, !s.isCollapsed {
			return
		} else if let i = tableView.indexPathForSelectedRow {
			tableView.deselectRow(at: i, animated: true)
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		let searchController = UISearchController(searchResultsController: nil)
		searchController.dimsBackgroundDuringPresentation = false
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.searchResultsUpdater = self
		searchController.searchBar.tintColor = view.tintColor
		searchController.searchBar.placeholder = "Filter"
		navigationItem.searchController = searchController

		searchTimer = PopTimer(timeInterval: 0.3) { [weak self] in
			self?.updateSearch()
		}

		refreshControl?.addTarget(self, action: #selector(refreshControlChanged(_:)), for: .valueChanged)

		tableView.rowHeight = UITableViewAutomaticDimension
		tableView.estimatedRowHeight = 160
		tableView.register(UINib(nibName: "SectionHeaderView", bundle: nil), forHeaderFooterViewReuseIdentifier: "SectionHeaderView")
		clearsSelectionOnViewWillAppear = false
		tableView.dragDelegate = self

		if let detailNav = splitViewController?.viewControllers.last as? UINavigationController {
			detailViewController = detailNav.topViewController as? DetailViewController
		}

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(refreshStarting), name: RefreshStartedNotification, object: nil)
		n.addObserver(self, selector: #selector(refreshUpdated), name: SyncProgressUpdateNotification, object: nil)
		n.addObserver(self, selector: #selector(refreshProcessing), name: RefreshProcessingNotification, object: nil)
		n.addObserver(self, selector: #selector(refreshEnded), name: RefreshEndedNotification, object: nil)
		n.addObserver(self, selector: #selector(dataUpdated(_:)), name: .NSManagedObjectContextObjectsDidChange, object: nil)

		dataUpdateTimer = PopTimer(timeInterval: 1) { [weak self] in
			DLog("Detected possible status update")
			self?.updateStatus(becauseOfChanges: true)
		}

		/*let prs = DataItem.allItems(of: PullRequest.self, in: DataManager.main)
		if prs.count > 0 {
			prs[0].postSyncAction = PostSyncAction.delete.rawValue
			DataItem.nukeDeletedItems(in: DataManager.main)
		}*/

		navigationItem.largeTitleDisplayMode = .automatic

		updateTabItems()
		atNextEvent {
			self.tableView.reloadData() // ensure footers are correct
		}
	}

	func tableView(_ tableView: UITableView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
		let p = fetchedResultsController.object(at: indexPath)
		return [p.dragItemForUrl]
	}

	func tableView(_ tableView: UITableView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
		let p = fetchedResultsController.object(at: indexPath)
		let dragItem = p.dragItemForUrl
		return session.items.contains(dragItem) ? [] : [dragItem]
	}

	private var dataUpdateTimer: PopTimer!
	@objc private func dataUpdated(_ notification: Notification) {

		guard let relatedMoc = notification.object as? NSManagedObjectContext, relatedMoc === DataManager.main else { return }

		if let items = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>,
			items.first(where: { $0 is ListableItem }) != nil {
			//DLog(">>>>>>>>>>>>>>> detected inserted items")
			dataUpdateTimer.push()
			return
		}

		if let items = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>,
			items.first(where: { $0 is ListableItem }) != nil {
			//DLog(">>>>>>>>>>>>>>> detected deleted items")
			dataUpdateTimer.push()
			return
		}

		if let items = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>,
			items.first(where: { ($0 as? ListableItem)?.hasPersistentChangedValues ?? false }) != nil {
			//DLog(">>>>>>>>>>>>>>> detected permanently changed items")
			dataUpdateTimer.push()
			return
		}
	}

	@objc private func refreshStarting() {
		updateStatus(becauseOfChanges: false)
	}

	@objc private func refreshEnded() {
		dataUpdateTimer.push()
	}

	@objc private func refreshUpdated() {
		refreshControl?.attributedTitle = NSAttributedString(string: API.lastUpdateDescription, attributes: nil)
	}

	@objc private func refreshProcessing() {
		refreshControl?.attributedTitle = NSAttributedString(string: "Processing…", attributes: nil)
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	override var keyCommands: [UIKeyCommand]? {
		let f = UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(focusFilter), discoverabilityTitle: "Filter items")
		let o = UIKeyCommand(input: "o", modifierFlags: .command, action: #selector(keyOpenInSafari), discoverabilityTitle: "Open in Safari")
		let a = UIKeyCommand(input: "a", modifierFlags: .command, action: #selector(keyToggleRead), discoverabilityTitle: "Mark item read/unread")
		let m = UIKeyCommand(input: "m", modifierFlags: .command, action: #selector(keyToggleMute), discoverabilityTitle: "Set item mute/unmute")
		let s = UIKeyCommand(input: "s", modifierFlags: .command, action: #selector(keyToggleSnooze), discoverabilityTitle: "Snooze/wake item")
		let r = UIKeyCommand(input: "r", modifierFlags: .command, action: #selector(keyForceRefresh), discoverabilityTitle: "Refresh now")
		let nt = UIKeyCommand(input: "\t", modifierFlags: .alternate, action: #selector(moveToNextTab), discoverabilityTitle: "Move to next tab")
		let pt = UIKeyCommand(input: "\t", modifierFlags: [.alternate, .shift], action: #selector(moveToPreviousTab), discoverabilityTitle: "Move to previous tab")
		let sp = UIKeyCommand(input: " ", modifierFlags: [], action: #selector(keyShowSelectedItem), discoverabilityTitle: "Display current item")
		let d = UIKeyCommand(input: UIKeyInputDownArrow, modifierFlags: [], action: #selector(keyMoveToNextItem), discoverabilityTitle: "Next item")
		let u = UIKeyCommand(input: UIKeyInputUpArrow, modifierFlags: [], action: #selector(keyMoveToPreviousItem), discoverabilityTitle: "Previous item")
		let dd = UIKeyCommand(input: UIKeyInputDownArrow, modifierFlags: .alternate, action: #selector(keyMoveToNextSection), discoverabilityTitle: "Move to the next section")
		let uu = UIKeyCommand(input: UIKeyInputUpArrow, modifierFlags: .alternate, action: #selector(keyMoveToPreviousSection), discoverabilityTitle: "Move to the previous section")
		let fd = UIKeyCommand(input: UIKeyInputRightArrow, modifierFlags: .command, action: #selector(keyFocusDetailView), discoverabilityTitle: "Focus keyboard on detail view")
		let fm = UIKeyCommand(input: UIKeyInputLeftArrow, modifierFlags: .command, action: #selector(becomeFirstResponder), discoverabilityTitle: "Focus keyboard on list view")
		return [u,d,uu,dd,nt,pt,fd,fm,sp,f,r,a,m,o,s]
	}


	private func canIssueKeyForIndexPath(actionTitle: String, indexPath: IndexPath) -> Bool {
		if let actions = tableView(tableView, editActionsForRowAt: indexPath) {

			for a in actions {
				if a.title == actionTitle {
					return true
				}
			}
		}
		showMessage("\(actionTitle) not available", "This command cannot be used on this item")
		return false
	}

	@objc private func keyToggleSnooze() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			if i.isSnoozing {
				if canIssueKeyForIndexPath(actionTitle: "Wake", indexPath: ip) {
					i.wakeUp()
				}
			} else {
				if canIssueKeyForIndexPath(actionTitle: "Snooze", indexPath: ip) {
					showSnoozeMenuFor(i: i)
				}
			}
		}
	}

	@objc private func keyToggleRead() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			if i.hasUnreadCommentsOrAlert {
				if canIssueKeyForIndexPath(actionTitle: "Read", indexPath: ip) {
					markItemAsRead(itemUri: i.objectID.uriRepresentation().absoluteString)
				}
			} else {
				if canIssueKeyForIndexPath(actionTitle: "Unread", indexPath: ip) {
					markItemAsUnRead(itemUri: i.objectID.uriRepresentation().absoluteString)
				}
			}
		}
	}

	@objc private func keyToggleMute() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			let isMuted = i.muted
			if (!isMuted && canIssueKeyForIndexPath(actionTitle: "Mute", indexPath: ip)) || (isMuted && canIssueKeyForIndexPath(actionTitle: "Unmute", indexPath: ip)) {
				i.setMute(to: !isMuted)
			}
		}
	}

	@objc private func keyForceRefresh() {
		switch app.startRefresh() {
		case .alreadyRefreshing, .started:
			break
		case .noConfiguredServers:
			showMessage("No Configured Servers", "There are no configured servers to sync from, please check your settings")
		case .noNetwork:
			showMessage("No Network", "There is no network connectivity, please try again later")
		}
		updateStatus(becauseOfChanges: false)
	}

	@objc private func keyFocusDetailView() {
		showDetailViewController(detailViewController.navigationController ?? detailViewController, sender: self)
		detailViewController.becomeFirstResponder()
	}

	@objc private func keyOpenInSafari() {
		if let ip = tableView.indexPathForSelectedRow {
			forceSafari = true
			tableView(tableView, didSelectRowAt: ip)
		}
	}

	@objc private func keyShowSelectedItem() {
		if let ip = tableView.indexPathForSelectedRow {
			tableView(tableView, didSelectRowAt: ip)
		}
	}

	@objc private func keyMoveToNextItem() {
		if let ip = tableView.indexPathForSelectedRow {
			var newRow = ip.row+1
			var newSection = ip.section
			if newRow >= tableView.numberOfRows(inSection: ip.section) {
				newSection += 1
				if newSection >= tableView.numberOfSections {
					return; // end of the table
				}
				newRow = 0
			}
			tableView.selectRow(at: IndexPath(row: newRow, section: newSection), animated: true, scrollPosition: .middle)
		} else if numberOfSections(in: tableView) > 0 {
			tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: true, scrollPosition: .top)
		}
	}

	@objc private func keyMoveToPreviousItem() {
		if let ip = tableView.indexPathForSelectedRow {
			var newRow = ip.row-1
			var newSection = ip.section
			if newRow < 0 {
				newSection -= 1
				if newSection < 0 {
					return; // start of the table
				}
				newRow = tableView.numberOfRows(inSection: newSection)-1
			}
			tableView.selectRow(at: IndexPath(row: newRow, section: newSection), animated: true, scrollPosition: .middle)
		} else if numberOfSections(in: tableView) > 0 {
			tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: true, scrollPosition: .top)
		}
	}

	@objc private func keyMoveToPreviousSection() {
		if let ip = tableView.indexPathForSelectedRow {
			let newSection = ip.section-1
			if newSection < 0 {
				return; // start of table
			}
			tableView.selectRow(at: IndexPath(row: 0, section: newSection), animated: true, scrollPosition: .middle)
		} else if numberOfSections(in: tableView) > 0 {
			tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: true, scrollPosition: .top)
		}
	}

	@objc private func keyMoveToNextSection() {
		if let ip = tableView.indexPathForSelectedRow {
			let newSection = ip.section+1
			if newSection >= tableView.numberOfSections {
				return; // end of table
			}
			tableView.selectRow(at: IndexPath(row: 0, section: newSection), animated: true, scrollPosition: .middle)
		} else if numberOfSections(in: tableView) > 0 {
			tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: true, scrollPosition: .top)
		}
	}

	@objc private func moveToNextTab() {
		if let t = tabs, let i = t.selectedItem, let items = t.items, let ind = items.index(of: i), items.count > 1 {
			var nextIndex = ind+1
			if nextIndex >= items.count {
				nextIndex = 0
			}
			requestTabFocus(tabItem: items[nextIndex])
		}
	}

	@objc private func moveToPreviousTab() {
		if let t = tabs, let i = t.selectedItem, let items = t.items, let ind = items.index(of: i), items.count > 1 {
			var nextIndex = ind-1
			if nextIndex < 0 {
				nextIndex = items.count-1
			}
			requestTabFocus(tabItem: items[nextIndex])
		}
	}

	private func requestTabFocus(tabItem: UITabBarItem?, andOpen: ListableItem? = nil, overrideUrl: String? = nil) {
		if let tabs = tabs, let tabItem = tabItem {
			tabbing(tabs, didSelect: tabItem) { [weak self] in
				if let andOpen = andOpen {
					self?.openInCurrentTab(item: andOpen, overrideUrl: overrideUrl)
				}
			}
		} else if let andOpen = andOpen { // no tabs
			openInCurrentTab(item: andOpen, overrideUrl: overrideUrl)
		}
	}

	private func openInCurrentTab(item: ListableItem, overrideUrl: String?) {
		guard let ip = fetchedResultsController.indexPath(forObject: item) else { return }

		tableView.selectRow(at: ip, animated: false, scrollPosition: .middle)
		tableView(tableView, didSelectRowAt: ip)

		atNextEvent(self) { S in
			if let u = overrideUrl, let url = URL(string: u) {
				S.showDetail(url: url, objectId: item.objectID)
			} else if let u = item.webUrl, let url = URL(string: u) {
				S.showDetail(url: url, objectId: item.objectID)
			}
		}
	}

	private func tabBarSetForTabItem(i: UITabBarItem?) -> TabBarSet? {
		guard let i = i else { return tabBarSets.first }
		return tabBarSets.first(where: { $0.prItem === i || $0.issuesItem === i })
	}

	func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
		tabbing(tabBar, didSelect: item, completion: nil)
	}

	private func tabbing(_ tabBar: UITabBar, didSelect item: UITabBarItem, completion: Completion?) {
		safeScrollToTop { [weak self] in
			guard let S = self else { return }
			S.lastTabIndex = S.tabs?.items?.index(of: item) ?? 0
			S.updateStatus(becauseOfChanges: false, updateItems: true)
			completion?()
		}
	}

	private func updateSearch() {

		let r = Range(uncheckedBounds: (lower: 0, upper: fetchedResultsController.sections?.count ?? 0))
		let currentIndexes = IndexSet(integersIn: r)

		updateQuery(newFetchRequest: itemFetchRequest)

		let r2 = Range(uncheckedBounds: (lower: 0, upper: fetchedResultsController.sections?.count ?? 0))
		let dataIndexes = IndexSet(integersIn: r2)

		let removedIndexes = currentIndexes.filter { !dataIndexes.contains($0) }
		let addedIndexes = dataIndexes.filter { !currentIndexes.contains($0) }
		let untouchedIndexes = dataIndexes.filter { !(removedIndexes.contains($0) || addedIndexes.contains($0)) }

		tableView.beginUpdates()
		if removedIndexes.count > 0 {
			tableView.deleteSections(IndexSet(removedIndexes), with: .fade)
		}
		if untouchedIndexes.count > 0 {
			tableView.reloadSections(IndexSet(untouchedIndexes), with: .fade)
		}
		if addedIndexes.count > 0 {
			tableView.insertSections(IndexSet(addedIndexes), with: .fade)
		}
		tableView.endUpdates()

		updateFooter()
	}

	private func updateQuery(newFetchRequest: NSFetchRequest<ListableItem>) {

		if fetchedResultsController == nil || fetchedResultsController.fetchRequest.entityName != newFetchRequest.entityName {
			let c = NSFetchedResultsController(fetchRequest: newFetchRequest, managedObjectContext: DataManager.main, sectionNameKeyPath: "sectionName", cacheName: nil)
			fetchedResultsController = c
			try! c.performFetch()
			c.delegate = self
		} else {
			let fr = fetchedResultsController.fetchRequest
			fr.relationshipKeyPathsForPrefetching = newFetchRequest.relationshipKeyPathsForPrefetching
			fr.sortDescriptors = newFetchRequest.sortDescriptors
			fr.predicate = newFetchRequest.predicate
			try! fetchedResultsController.performFetch()
		}
	}

	private func updateTabItems() {

		tabBarSets.removeAll()

		for groupLabel in Repo.allGroupLabels(in: DataManager.main) {
			let c = GroupingCriterion(repoGroup: groupLabel)
			let s = TabBarSet(viewCriterion: c)
			tabBarSets.append(s)
		}

		if Settings.showSeparateApiServersInMenu {
			for a in ApiServer.allApiServers(in: DataManager.main) {
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
			items.append(contentsOf: d.tabItems)
		}

		let tabsAlreadyWereVisible = tabs != nil

		if items.count > 1 {
			showTabBar(show: true, animated: true)

			tabs?.items = items
			if items.count > lastTabIndex {
				tabs?.selectedItem = items[lastTabIndex]
				currentTabBarSet = tabBarSetForTabItem(i: items[lastTabIndex])
			} else {
				tabs?.selectedItem = items.last
				currentTabBarSet = tabBarSetForTabItem(i: items.last!)
			}
			tabsWidth?.constant = CGFloat(items.count * 64)
			tabs?.superview?.layoutIfNeeded()

		} else {
			currentTabBarSet = tabBarSetForTabItem(i: items.first)
			showTabBar(show: false, animated: true)
		}

		if let i = tabs?.selectedItem?.image {
			viewingPrs = i == UIImage(named: "prsTab") // not proud of this :(
		} else if let c = currentTabBarSet {
			viewingPrs = c.tabItems.first?.image == UIImage(named: "prsTab") // or this :(
		} else if Repo.anyVisibleRepos(in: DataManager.main, criterion: currentTabBarSet?.viewCriterion, excludeGrouped: true) {
			viewingPrs = Repo.interestedInPrs(fromServerWithId: currentTabBarSet?.viewCriterion?.apiServerId)
		} else {
			viewingPrs = true
		}

		if fetchedResultsController == nil {
			updateQuery(newFetchRequest: itemFetchRequest)
			tableView.reloadData()
		} else {
			let latestFetchRequest = fetchedResultsController.fetchRequest
			let newFetchRequest = itemFetchRequest
			let newCount = tabs?.items?.count ?? 0
			if newCount != lastTabCount || latestFetchRequest != newFetchRequest {
				updateQuery(newFetchRequest: newFetchRequest)
				tableView.reloadData()
			}
		}

		if let ts = tabScroll, let t = tabs, let i = t.selectedItem, let ind = t.items?.index(of: i) {
			let w = t.bounds.size.width / CGFloat(t.items?.count ?? 1)
			let x = w * CGFloat(ind)
			let f = CGRect(x: x, y: 0, width: w, height: t.bounds.size.height)
			ts.scrollRectToVisible(f, animated: tabsAlreadyWereVisible)
		}
		lastTabCount = tabs?.items?.count ?? 0

		if let i = tabs?.selectedItem, let ind = tabs?.items?.index(of: i) {
			lastTabIndex = ind
		} else {
			lastTabIndex = 0
		}
	}

	private var lastTabIndex = 0
	private var lastTabCount = 0
	private var tabsWidth: NSLayoutConstraint?
	private func showTabBar(show: Bool, animated: Bool) {
		if show {

			if tabScroll == nil, let v = navigationController?.view {

				tableView.scrollIndicatorInsets = UIEdgeInsets(top: tableView.scrollIndicatorInsets.top, left: 0, bottom: 49, right: 0)

				let t = CustomTabBar()
				t.translatesAutoresizingMaskIntoConstraints = false
				t.delegate = self
				tabs = t

				let ts = UIScrollView()
				ts.translatesAutoresizingMaskIntoConstraints = false
				ts.showsHorizontalScrollIndicator = false
				ts.alwaysBounceHorizontal = true
				ts.scrollsToTop = false
				ts.addSubview(t)

				let s1 = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
				s1.translatesAutoresizingMaskIntoConstraints = false
				ts.addSubview(s1)

				let s2 = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
				s2.translatesAutoresizingMaskIntoConstraints = false
				ts.addSubview(s2)

				let b = UIView()
				b.translatesAutoresizingMaskIntoConstraints = false
				b.backgroundColor = UIColor.black.withAlphaComponent(DISABLED_FADE)
				b.isUserInteractionEnabled = false
				v.addSubview(b)
				tabBorder = b

				v.addSubview(ts)
				tabScroll = ts

				t.heightAnchor.constraint(equalTo: ts.heightAnchor).isActive = true
				t.widthAnchor.constraint(greaterThanOrEqualTo: v.widthAnchor).isActive = true
				tabsWidth = t.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
				tabsWidth!.isActive = true

				t.topAnchor.constraint(equalTo: ts.contentLayoutGuide.topAnchor).isActive = true
				t.leadingAnchor.constraint(equalTo: ts.contentLayoutGuide.leadingAnchor).isActive = true
				t.trailingAnchor.constraint(equalTo: ts.contentLayoutGuide.trailingAnchor).isActive = true
				t.bottomAnchor.constraint(equalTo: ts.contentLayoutGuide.bottomAnchor).isActive = true

				ts.bottomAnchor.constraint(equalTo: v.bottomAnchor).isActive = true
				ts.leadingAnchor.constraint(equalTo: v.leadingAnchor).isActive = true
				ts.trailingAnchor.constraint(equalTo: v.trailingAnchor).isActive = true
				ts.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.bottomAnchor, constant: -49).isActive = true

				b.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
				b.bottomAnchor.constraint(equalTo: ts.topAnchor).isActive = true
				b.leadingAnchor.constraint(equalTo: ts.leadingAnchor).isActive = true
				b.trailingAnchor.constraint(equalTo: ts.trailingAnchor).isActive = true

				s2.trailingAnchor.constraint(equalTo: t.leadingAnchor).isActive = true
				s2.widthAnchor.constraint(equalToConstant: 320).isActive = true
				s2.topAnchor.constraint(equalTo: ts.contentLayoutGuide.topAnchor).isActive = true
				s2.bottomAnchor.constraint(equalTo: ts.contentLayoutGuide.bottomAnchor).isActive = true

				s1.leadingAnchor.constraint(equalTo: t.trailingAnchor).isActive = true
				s1.widthAnchor.constraint(equalToConstant: 320).isActive = true
				s1.topAnchor.constraint(equalTo: ts.contentLayoutGuide.topAnchor).isActive = true
				s1.bottomAnchor.constraint(equalTo: ts.contentLayoutGuide.bottomAnchor).isActive = true

				if animated {
					ts.transform = CGAffineTransform(translationX: 0, y: 49)
					b.transform = CGAffineTransform(translationX: 0, y: 49)
					UIView.animate(withDuration: 0.2,
					               delay: 0.0,
					               options: .curveEaseInOut,
					               animations: {
									ts.transform = .identity
									b.transform = .identity
					}, completion: nil)
				}
			}

		} else {

			tableView.scrollIndicatorInsets = UIEdgeInsets(top: tableView.scrollIndicatorInsets.top, left: 0, bottom: 0, right: 0)

			if let t = tabScroll, let b = tabBorder {

				tabs = nil
				tabScroll = nil
				tabBorder = nil
				tabsWidth = nil

				if animated {
					UIView.animate(withDuration: 0.2,
					               delay: 0.0,
					               options: .curveEaseInOut,
					               animations: {
									t.transform = CGAffineTransform(translationX: 0, y: 49)
									b.transform = CGAffineTransform(translationX: 0, y: 49)
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

	func localNotification(userInfo: [AnyHashable : Any], action: String) {
		var urlToOpen = userInfo[NOTIFICATION_URL_KEY] as? String
		var relatedItem: ListableItem?

		if let commentId = DataManager.id(for: userInfo[COMMENT_ID_KEY] as? String), let c = existingObject(with: commentId) as? PRComment {
			relatedItem = c.parent
			if urlToOpen == nil {
				urlToOpen = c.webUrl
			}
		} else if let uri = userInfo[LISTABLE_URI_KEY] as? String, let itemId = DataManager.id(for: uri) {
			relatedItem = existingObject(with: itemId) as? ListableItem
		}

		if let item = relatedItem {
			switch action {
			case "mute":
				item.setMute(to: true)

			case "read":
				item.catchUpWithComments()

			default:
				if let sc = navigationItem.searchController, sc.isActive {
					sc.searchBar.text = nil
					sc.isActive = false
				}
				selectTabAndOpen(item, overrideUrl: urlToOpen)
			}
		} else {
			showMessage("Item not found", "Could not locate the item related to this notification")
		}
	}

	private func selectTabAndOpen(_ item: ListableItem, overrideUrl: String?) {
		for d in tabBarSets {
			if d.viewCriterion == nil || d.viewCriterion?.isRelated(to: item) ?? false {
				requestTabFocus(tabItem: item is PullRequest ? d.prItem : d.issuesItem,
				                andOpen: item,
				                overrideUrl: overrideUrl)
				return
			}
		}
	}

	func openItemWithUriPath(uriPath: String) {
		if
			let itemId = DataManager.id(for: uriPath),
			let item = existingObject(with: itemId) as? ListableItem {
			selectTabAndOpen(item, overrideUrl: nil)
		}
	}

	func openCommentWithId(cId: String) {
		if let
			itemId = DataManager.id(for: cId),
			let comment = existingObject(with: itemId) as? PRComment,
			let item = comment.parent {
			selectTabAndOpen(item, overrideUrl: nil)
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return fetchedResultsController.sections?.count ?? 0
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return fetchedResultsController.sections?[section].numberOfObjects ?? 0
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
		let o = fetchedResultsController.object(at: indexPath)
		configureCell(cell: cell, withObject: o)
		return cell
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

		if !isFirstResponder {
			becomeFirstResponder()
		}

		let p = fetchedResultsController.object(at: indexPath)
		if let u = p.urlForOpening, let url = URL(string: u) {
			showDetail(url: url, objectId: p.objectID)
		}
	}

	private func showDetail(url: URL, objectId: NSManagedObjectID) {

		if forceSafari || (Settings.openItemsDirectlyInSafari && !detailViewController.isVisible) {
			forceSafari = false
			if let item = existingObject(with: objectId) as? ListableItem {
				item.catchUpWithComments()
			}
			UIApplication.shared.open(url, options: [:])
		} else {
			detailViewController.catchupWithDataItemWhenLoaded = objectId
			detailViewController.detailItem = url
			if !detailViewController.isVisible {
				showTabBar(show: false, animated: true)
				keyFocusDetailView()
			}
		}
	}

	override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
		let v = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeaderView") as! SectionHeaderView
		let name = S(fetchedResultsController.sections?[section].name)
		v.title.text = name.uppercased()
		if viewingPrs {
			if name == Section.closed.prMenuName {
				v.action.isHidden = false
				v.callback = { [weak self] in
					self?.removeAllClosed()
				}
			} else if name == Section.merged.prMenuName {
				v.action.isHidden = false
				v.callback = { [weak self] in
					self?.removeAllMerged()
				}
			} else {
				v.action.isHidden = true
			}
		} else {
			if name == Section.closed.issuesMenuName {
				v.action.isHidden = false
				v.callback = { [weak self] in
					self?.removeAllClosed()
				}
			} else {
				v.action.isHidden = true
			}
		}
		return v
	}

	override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
		return 64
	}

	override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
		if section == numberOfSections(in: tableView)-1 {
			return 20 + (tabs == nil ? 0 : 49)
		}
		return CGFloat.leastNonzeroMagnitude
	}

	private func markItemAsRead(itemUri: String?) {
		if let
			i = itemUri,
			let oid = DataManager.id(for: i),
			let o = existingObject(with: oid) as? ListableItem {
			o.catchUpWithComments()
		}
	}

	private func markItemAsUnRead(itemUri: String?) {
		if let
			i = itemUri,
			let oid = DataManager.id(for: i),
			let o = existingObject(with: oid) as? ListableItem {
			o.latestReadCommentDate = .distantPast
			o.postProcess()
		}
	}

	override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {

		var actions = [UITableViewRowAction]()

		func appendReadUnread(i: ListableItem) {
			let r: UITableViewRowAction
			if i.hasUnreadCommentsOrAlert {
				r = UITableViewRowAction(style: .normal, title: "Read") { [weak self] action, indexPath in
					tableView.setEditing(false, animated: true)
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
						self?.markItemAsRead(itemUri: i.objectID.uriRepresentation().absoluteString)
					}
				}
			} else {
				r = UITableViewRowAction(style: .normal, title: "Unread") { [weak self] action, indexPath in
					tableView.setEditing(false, animated: true)
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
						self?.markItemAsUnRead(itemUri: i.objectID.uriRepresentation().absoluteString)
					}
				}
			}
			r.backgroundColor = view.tintColor
			actions.append(r)
		}

		func appendMuteUnmute(i: ListableItem) {
			let m: UITableViewRowAction
			if i.muted {
				m = UITableViewRowAction(style: .normal, title: "Unmute") { action, indexPath in
					tableView.setEditing(false, animated: true)
					i.setMute(to: false)
				}
			} else {
				m = UITableViewRowAction(style: .normal, title: "Mute") { action, indexPath in
					tableView.setEditing(false, animated: true)
					i.setMute(to: true)
				}
			}
			actions.append(m)
		}

		let i = fetchedResultsController.object(at: indexPath)
		if let sectionName = fetchedResultsController.sections?[indexPath.section].name {

			if sectionName == Section.merged.prMenuName || sectionName == Section.closed.prMenuName || sectionName == Section.closed.issuesMenuName {

				appendReadUnread(i: i)
				let d = UITableViewRowAction(style: .destructive, title: "Remove") { action, indexPath in
					DataManager.main.delete(i)
				}
				actions.append(d)

			} else if i.isSnoozing {

				let w = UITableViewRowAction(style: .normal, title: "Wake") { action, indexPath in
					i.wakeUp()
				}
				w.backgroundColor = .darkGray
				actions.append(w)

			} else {

				if Settings.showCommentsEverywhere || (sectionName != Section.all.prMenuName && sectionName != Section.all.issuesMenuName) {
					appendReadUnread(i: i)
				}
				appendMuteUnmute(i: i)
				let s = UITableViewRowAction(style: .normal, title: "Snooze") { [weak self] action, indexPath in
					self?.showSnoozeMenuFor(i: i)
				}
				s.backgroundColor = .darkGray
				actions.append(s)
			}
		}
		return actions
	}

	private func showSnoozeMenuFor(i: ListableItem) {
		let snoozePresets = SnoozePreset.allSnoozePresets(in: DataManager.main)
		let hasPresets = snoozePresets.count > 0
		let singleColumn = splitViewController?.isCollapsed ?? true
		let a = UIAlertController(title: hasPresets ? "Snooze" : nil,
		                          message: hasPresets ? S(i.title) : "You do not currently have any snoozing presets configured. Please add some in the relevant preferences tab.",
		                          preferredStyle: singleColumn ? .actionSheet : .alert)
		for preset in snoozePresets {
			a.addAction(UIAlertAction(title: preset.listDescription, style: .default) { action in
				i.snooze(using: preset)
			})
		}
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true)
	}

	private var itemFetchRequest: NSFetchRequest<ListableItem> {
		let type: ListableItem.Type = viewingPrs ? PullRequest.self : Issue.self
		let searchBar = navigationItem.searchController!.searchBar
		return ListableItem.requestForItems(of: type, withFilter: searchBar.text, sectionIndex: -1, criterion: currentTabBarSet?.viewCriterion)
	}

	private var animatedUpdates = false

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		animatedUpdates = UIApplication.shared.applicationState != .background
		sectionsChanged = false
		if animatedUpdates {
			tableView.beginUpdates()
		}
	}

	private var sectionsChanged = false

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {

		guard animatedUpdates else { return }

		switch(type) {
		case .insert:
			tableView.insertSections(IndexSet(integer: sectionIndex), with: .fade)
		case .delete:
			tableView.deleteSections(IndexSet(integer: sectionIndex), with: .fade)
		case .update, .move:
			break
		}

		sectionsChanged = true
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

		guard animatedUpdates else { return }

		switch(type) {
		case .insert:
			if let n = newIndexPath {
				tableView.insertRows(at: [n], with: .fade)
			}
		case .delete:
			if let i = indexPath {
				tableView.deleteRows(at: [i], with: .fade)
			}
		case .update:
			if let i = indexPath, let object = anObject as? ListableItem, let cell = tableView.cellForRow(at: i) {
				configureCell(cell: cell, withObject: object)
			}
		case .move:
			if let i = indexPath, let n = newIndexPath {
				if sectionsChanged {
					tableView.deleteRows(at: [i], with: .fade)
					tableView.insertRows(at: [n], with: .fade)
				} else {
					tableView.moveRow(at: i, to: n)
				}
			}
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		if animatedUpdates {
			tableView.endUpdates()
		} else {
			tableView.reloadData()
		}
	}

	private func configureCell(cell: UITableViewCell, withObject: ListableItem) {
		guard let c = cell as? PRCell else { return }
		if let o = withObject as? PullRequest {
			c.setPullRequest(pullRequest: o)
		} else if let o = withObject as? Issue {
			c.setIssue(issue: o)
		}
	}

	private var viewingPrs = true

	func updateStatus(becauseOfChanges: Bool, updateItems: Bool = false) {

		if becauseOfChanges {
			app.updateBadgeAndSaveDB()
		}

		if becauseOfChanges || updateItems {
			updateTabItems()
		}

		updateFooter()
		refreshUpdated()

		if appIsRefreshing {
			title = "Refreshing…"
		} else {
			title = viewingPrs ? pullRequestsTitle : issuesTitle
		}

		if splitViewController?.displayMode != .allVisible {
			detailViewController.navigationItem.leftBarButtonItem?.title = title
		}

		if !appIsRefreshing {
			refreshControl?.endRefreshing()
		}
	}

	private func updateFooter() {
		if (fetchedResultsController.fetchedObjects?.count ?? 0) == 0 {
			let reasonForEmpty: NSAttributedString
			let searchBarText = navigationItem.searchController!.searchBar.text
			if viewingPrs {
				reasonForEmpty = PullRequest.reasonForEmpty(with: searchBarText, criterion: currentTabBarSet?.viewCriterion)
			} else {
				reasonForEmpty = Issue.reasonForEmpty(with: searchBarText, criterion: currentTabBarSet?.viewCriterion)
			}
			tableView.tableFooterView = EmptyView(message: reasonForEmpty, parentWidth: view.bounds.size.width)
		} else {
			tableView.tableFooterView = nil
		}
	}

	private func unreadCommentCount(count: Int) -> String {
		return count == 0 ? "" : count == 1 ? " (1 update)" : " (\(count) updates)"
	}

	private var pullRequestsTitle: String {
		let item = currentTabBarSet?.prItem
		let unreadCount = Int(item?.badgeValue ?? "0")!
		let title = item?.title ?? "Pull Requests"
		if unreadCount > 0 {
			return title.appending(" (\(unreadCount))")
		} else {
			return title
		}
	}

	private var issuesTitle: String {
		let item = currentTabBarSet?.issuesItem
		let unreadCount = Int(item?.badgeValue ?? "0")!
		let title = item?.title ?? "Issues"
		if unreadCount > 0 {
			return title.appending(" (\(unreadCount))")
		} else {
			return title
		}
	}

	///////////////////////////// filtering

	override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		becomeFirstResponder()
	}

	func updateSearchResults(for searchController: UISearchController) {
		searchTimer.push()
	}

	private func safeScrollToTop(completion: Completion?) {
		tableView.contentOffset = tableView.contentOffset // halt any inertial scrolling
		atNextEvent(self) { S in
			if S.tableView.numberOfSections > 0 {
				S.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
			}
			atNextEvent {
				completion?()
			}
		}
	}

	@objc func focusFilter(terms: String?) {
		tableView.contentOffset = CGPoint(x: 0, y: -tableView.contentInset.top)
		let searchBar = navigationItem.searchController!.searchBar
		searchBar.becomeFirstResponder()
		searchBar.text = terms
		searchTimer.push()
	}

	func resetView(becauseOfChanges: Bool) {
		safeScrollToTop { [weak self] in
			guard let S = self else { return }
			S.updateQuery(newFetchRequest: S.itemFetchRequest)
			S.updateStatus(becauseOfChanges: becauseOfChanges)
			S.tableView.reloadData()
		}
	}

	////////////////// opening prefs

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		var allServersHaveTokens = true
		for a in ApiServer.allApiServers(in: DataManager.main) {
			if !a.goodToGo {
				allServersHaveTokens = false
				break
			}
		}

		if let destination = segue.destination as? UITabBarController {
			if allServersHaveTokens {
				destination.selectedIndex = min(Settings.lastPreferencesTabSelected, (destination.viewControllers?.count ?? 1)-1)
				destination.delegate = self
			}
		}
	}

	func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
		Settings.lastPreferencesTabSelected = tabBarController.viewControllers?.index(of: viewController) ?? 0
	}

}
