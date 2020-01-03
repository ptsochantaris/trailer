
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

final class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate,
UITabBarControllerDelegate, UITabBarDelegate, UISearchResultsUpdating,
UITableViewDragDelegate {

	private var fetchedResultsController: NSFetchedResultsController<ListableItem>!

	// Tabs
	private var tabs = UITabBar()
	private var tabScroll: UIScrollView?
	private var tabBorder: UIView?
	private var tabBarSets = [TabBarSet]()
	private var currentTabBarSet: TabBarSet?

	private var searchTimer: PopTimer!

	private var pluralNameForItems: String {
		return viewingPrs ? "pull requests" : "issues"
	}

	var allTabSets: [TabBarSet] {
		return tabBarSets
	}

	@IBAction private func editSelected(_ sender: UIBarButtonItem ) {

		let promptTitle: String
		if let l = currentTabBarSet?.viewCriterion?.label {
			promptTitle = "\(pluralNameForItems.capitalized) in '\(l)'"
		} else {
			promptTitle = pluralNameForItems.capitalized
		}

		let a = UIAlertController(title: promptTitle, message: "Mark all as read?", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "No", style: .cancel))
		a.addAction(UIAlertAction(title: "Yes", style: .default) { action in
			self.markAllAsRead()
		})
		present(a, animated: true)
	}
    
	func removeAllMerged() {
        DispatchQueue.main.async { [weak self] in
            guard let S = self else { return }
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
        DispatchQueue.main.async { [weak self] in
            guard let S = self else { return }
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

	private func removeAllClosedConfirmed() {
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

	private func removeAllMergedConfirmed() {
		if viewingPrs {
			for p in PullRequest.allMerged(in: DataManager.main, criterion: currentTabBarSet?.viewCriterion) {
				DataManager.main.delete(p)
			}
		}
	}

	private func markAllAsRead() {
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

		if let s = splitViewController, !s.isCollapsed {
			return
		} else if let i = tableView.indexPathForSelectedRow {
			tableView.deselectRow(at: i, animated: true)
		}
	}
    
    private var firstAppearance = true
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        guard firstAppearance else {
            return
        }
        
        firstAppearance = false
        if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
            let m = popupManager.masterController
            if ApiServer.countApiServers(in: DataManager.main) == 1, let a = ApiServer.allApiServers(in: DataManager.main).first, a.authToken == nil || a.authToken!.isEmpty {
                m.performSegue(withIdentifier: "showQuickstart", sender: self)
            } else {
                m.performSegue(withIdentifier: "showPreferences", sender: self)
            }
        }
    }

    let watchManager = WatchManager()
    
	override func viewDidLoad() {
		super.viewDidLoad()

		let searchController = UISearchController(searchResultsController: nil)
		searchController.obscuresBackgroundDuringPresentation = false
		searchController.searchResultsUpdater = self
		searchController.searchBar.tintColor = view.tintColor
		searchController.searchBar.placeholder = "Filter"
		searchController.searchBar.autocapitalizationType = .none
		navigationItem.searchController = searchController

		searchTimer = PopTimer(timeInterval: 0.3) { [weak self] in
			self?.updateSearch()
		}

		refreshControl?.addTarget(self, action: #selector(refreshControlChanged(_:)), for: .valueChanged)

		tableView.rowHeight = UITableView.automaticDimension
		tableView.estimatedRowHeight = 160
		tableView.register(UINib(nibName: "SectionHeaderView", bundle: nil), forHeaderFooterViewReuseIdentifier: "SectionHeaderView")
		clearsSelectionOnViewWillAppear = false
		tableView.dragDelegate = self

		let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(refreshUpdated), name: .SyncProgressUpdate, object: nil)
        n.addObserver(self, selector: #selector(refreshEnded), name: .RefreshEnded, object: nil)
		n.addObserver(self, selector: #selector(dataUpdated(_:)), name: .NSManagedObjectContextObjectsDidChange, object: nil)

        tabs.tintColor = UIColor(named: "apptint")
        
		updateTabItems(animated: false)
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

	@objc private func dataUpdated(_ notification: Notification) {

		guard let relatedMoc = notification.object as? NSManagedObjectContext, relatedMoc === DataManager.main else { return }

		if let items = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>, items.contains(where: { $0 is ListableItem }) {
			//DLog(">>>>>>>>>>>>>>> detected inserted items")
            DispatchQueue.main.async {
                self.updateStatus(becauseOfChanges: true)
            }
			return
		}

		if let items = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>, items.contains(where: { $0 is ListableItem }) {
			//DLog(">>>>>>>>>>>>>>> detected deleted items")
            DispatchQueue.main.async {
                self.updateStatus(becauseOfChanges: true)
            }
			return
		}

		if let items = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>, items.contains(where: { ($0 as? ListableItem)?.hasPersistentChangedValues ?? false }) {
			//DLog(">>>>>>>>>>>>>>> detected permanently changed items")
            DispatchQueue.main.async {
                self.updateStatus(becauseOfChanges: true)
            }
			return
		}
	}

	@objc private func refreshEnded() {
        refreshControl?.endRefreshing()
	}
    
    private func updateTitle() {
        let newTitle: String
        
        if API.isRefreshing {
            newTitle = "Refreshing…"
            
        } else if viewingPrs {
            let item = currentTabBarSet?.prItem
            let unreadCount = Int(item?.badgeValue ?? "0")!
            let t = item?.title ?? "Pull Requests"
            if unreadCount > 0 {
                newTitle = t.appending(" (\(unreadCount))")
            } else {
                newTitle = t
            }
            
        } else {
            let item = currentTabBarSet?.issuesItem
            let unreadCount = Int(item?.badgeValue ?? "0")!
            let t = item?.title ?? "Issues"
            if unreadCount > 0 {
                newTitle = t.appending(" (\(unreadCount))")
            } else {
                newTitle = t
            }
        }
        
        if title != newTitle {
            title = newTitle
        }
    }

	@objc private func refreshUpdated() {
        updateTitle()
		refreshControl?.attributedTitle = NSAttributedString(string: API.currentOperationName, attributes: nil)
	}
    
	override var canBecomeFirstResponder: Bool {
		return true
	}

	override var keyCommands: [UIKeyCommand]? {
        return [
		makeKeyCommand(input: "f", modifierFlags: .command, action: #selector(focusFilter), discoverabilityTitle: "Filter items"),
        makeKeyCommand(input: "a", modifierFlags: .command, action: #selector(keyToggleRead), discoverabilityTitle: "Mark item read/unread"),
		makeKeyCommand(input: "m", modifierFlags: .command, action: #selector(keyToggleMute), discoverabilityTitle: "Set item mute/unmute"),
		makeKeyCommand(input: "s", modifierFlags: .command, action: #selector(keyToggleSnooze), discoverabilityTitle: "Snooze/wake item"),
		makeKeyCommand(input: "r", modifierFlags: .command, action: #selector(keyForceRefresh), discoverabilityTitle: "Refresh now"),
		makeKeyCommand(input: "\t", modifierFlags: .alternate, action: #selector(moveToNextTab), discoverabilityTitle: "Move to next tab"),
		makeKeyCommand(input: "\t", modifierFlags: [.alternate, .shift], action: #selector(moveToPreviousTab), discoverabilityTitle: "Move to previous tab"),
		makeKeyCommand(input: " ", modifierFlags: [], action: #selector(keyShowSelectedItem), discoverabilityTitle: "Display current item"),
		makeKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(keyMoveToNextItem), discoverabilityTitle: "Next item"),
		makeKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(keyMoveToPreviousItem), discoverabilityTitle: "Previous item"),
		makeKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: .alternate, action: #selector(keyMoveToNextSection), discoverabilityTitle: "Move to the next section"),
		makeKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: .alternate, action: #selector(keyMoveToPreviousSection), discoverabilityTitle: "Move to the previous section"),
		makeKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: .command, action: #selector(becomeFirstResponder), discoverabilityTitle: "Focus keyboard on list view")
        ]
	}

    private func canIssueKeyForIndexPath(action: ListableItem.MenuAction, indexPath: IndexPath) -> Bool {
        let actions = fetchedResultsController.object(at: indexPath).contextActions
        if actions.contains(action) {
            return true
        } else {
            showMessage("\(action.title) not available", "This command cannot be used on this item")
            return false
        }
	}

	@objc private func keyToggleSnooze() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			if i.isSnoozing {
                if canIssueKeyForIndexPath(action: .wake(date: i.snoozeUntil), indexPath: ip) {
					i.wakeUp()
				}
			} else {
                let presets = SnoozePreset.allSnoozePresets(in: DataManager.main)
                if canIssueKeyForIndexPath(action: .snooze(presets: presets), indexPath: ip) {
					showSnoozeMenuFor(i: i)
				}
			}
		}
	}

	@objc private func keyToggleRead() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			if i.hasUnreadCommentsOrAlert {
                if canIssueKeyForIndexPath(action: .markRead, indexPath: ip) {
					markItemAsRead(itemUri: i.objectID.uriRepresentation().absoluteString)
				}
			} else {
                if canIssueKeyForIndexPath(action: .markUnread, indexPath: ip) {
					markItemAsUnRead(itemUri: i.objectID.uriRepresentation().absoluteString)
				}
			}
		}
	}

	@objc private func keyToggleMute() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			let isMuted = i.muted
            if (!isMuted && canIssueKeyForIndexPath(action: .mute, indexPath: ip)) || (isMuted && canIssueKeyForIndexPath(action: .unmute, indexPath: ip)) {
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
		if let i = tabs.selectedItem, let items = tabs.items, let ind = items.firstIndex(of: i), items.count > 1 {
			var nextIndex = ind+1
			if nextIndex >= items.count {
				nextIndex = 0
			}
			requestTabFocus(tabItem: items[nextIndex])
		}
	}

	@objc private func moveToPreviousTab() {
		if let i = tabs.selectedItem, let items = tabs.items, let ind = items.firstIndex(of: i), items.count > 1 {
			var nextIndex = ind-1
			if nextIndex < 0 {
				nextIndex = items.count-1
			}
			requestTabFocus(tabItem: items[nextIndex])
		}
	}

    private func requestTabFocus(tabItem: UITabBarItem?, item: ListableItem? = nil, overrideUrl: String? = nil, andOpen: Bool = false) {
        let group = DispatchGroup()
		if let tabItem = tabItem {
            group.enter()
			tabbing(tabs, didSelect: tabItem) {
                group.leave()
			}
		}
        group.notify(queue: .main) { [weak self] in
            if let item = item {
                self?.selectInCurrentTab(item: item, overrideUrl: overrideUrl, andOpen: andOpen)
            }
        }
	}

    private func selectInCurrentTab(item: ListableItem, overrideUrl: String?, andOpen: Bool) {
		guard let ip = fetchedResultsController.indexPath(forObject: item) else { return }
        
        tableView.selectRow(at: ip, animated: false, scrollPosition: .middle)
        if andOpen {
            DispatchQueue.main.async { [weak self] in
                guard let S = self else { return }
                if let u = overrideUrl, let url = URL(string: u) {
                    S.showDetail(url: url, objectId: item.objectID)
                } else if let u = item.webUrl, let url = URL(string: u) {
                    S.showDetail(url: url, objectId: item.objectID)
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.tableView.deselectRow(at: ip, animated: true)
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
			S.lastTabIndex = tabBar.items?.firstIndex(of: item) ?? 0
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
		if !removedIndexes.isEmpty {
			tableView.deleteSections(IndexSet(removedIndexes), with: .fade)
		}
		if !untouchedIndexes.isEmpty {
			tableView.reloadSections(IndexSet(untouchedIndexes), with: .fade)
		}
		if !addedIndexes.isEmpty {
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

	private func updateTabItems(animated: Bool) {

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

        let items = tabBarSets.reduce([], { $0 + $1.tabItems })

		let tabsAlreadyWereVisible = tabScroll != nil

		if items.count > 1 {
			if splitViewController?.isCollapsed ?? false && (splitViewController?.viewControllers.first as? UINavigationController)?.viewControllers.count == 2 {
				// collapsed split view, and detail view is showing
			} else {
				showTabBar()
			}

			tabs.items = items
			if items.count > lastTabIndex {
				tabs.selectedItem = items[lastTabIndex]
				currentTabBarSet = tabBarSetForTabItem(i: items[lastTabIndex])
			} else {
				tabs.selectedItem = items.last
				currentTabBarSet = tabBarSetForTabItem(i: items.last!)
			}
			tabsWidth?.constant = CGFloat(items.count * 64)
			tabs.superview?.layoutIfNeeded()

		} else {
			tabs.items = items
			tabs.selectedItem = items.first
			currentTabBarSet = tabBarSetForTabItem(i: items.first)
			hideTabBar()
		}

		if let i = tabs.selectedItem?.image {
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
			let newCount = tabs.items?.count ?? 0
			if newCount != lastTabCount || latestFetchRequest != newFetchRequest {
				updateQuery(newFetchRequest: newFetchRequest)
				tableView.reloadData()
			}
		}

		if let ts = tabScroll, let i = tabs.selectedItem, let ind = tabs.items?.firstIndex(of: i) {
			let w = tabs.bounds.size.width / CGFloat(tabs.items?.count ?? 1)
			let x = w * CGFloat(ind)
			let f = CGRect(x: x, y: 0, width: w, height: tabs.bounds.size.height)
			ts.scrollRectToVisible(f, animated: animated && tabsAlreadyWereVisible)
		}
		lastTabCount = tabs.items?.count ?? 0

		if let i = tabs.selectedItem, let ind = tabs.items?.firstIndex(of: i) {
			lastTabIndex = ind
		} else {
			lastTabIndex = 0
		}
	}

	private var lastTabIndex = 0
    private var lastTabCount = 0
    private var tabsWidth: NSLayoutConstraint?
    
    private func showTabBar() {
        guard tabScroll == nil, let v = navigationController?.view else { return }
        
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.delegate = self
        
        let ts = UIScrollView()
        ts.translatesAutoresizingMaskIntoConstraints = false
        ts.showsHorizontalScrollIndicator = false
        ts.showsVerticalScrollIndicator = false
        ts.alwaysBounceHorizontal = true
        ts.scrollsToTop = false
        ts.contentInsetAdjustmentBehavior = .never
        ts.backgroundColor = .systemBackground
        ts.addSubview(tabs)
                
        let b = UIView()
        b.translatesAutoresizingMaskIntoConstraints = false
        b.backgroundColor = UIColor.separator
        b.isUserInteractionEnabled = false
        v.addSubview(b)
        tabBorder = b
        
        v.addSubview(ts)
        tabScroll = ts
        
        tabsWidth = tabs.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
                
        let cl = ts.contentLayoutGuide
        let top = cl.topAnchor
        let bottom = cl.bottomAnchor
        
        let frameHeight: CGFloat = 50
        
        additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: frameHeight, right: 0)
        
        NSLayoutConstraint.activate([
            tabs.heightAnchor.constraint(equalTo: ts.heightAnchor),
            tabs.widthAnchor.constraint(greaterThanOrEqualTo: v.widthAnchor),
            tabsWidth!,
            
            tabs.topAnchor.constraint(equalTo: top),
            tabs.leadingAnchor.constraint(equalTo: cl.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: cl.trailingAnchor),
            tabs.bottomAnchor.constraint(equalTo: bottom),
            
            ts.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            ts.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            ts.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            ts.topAnchor.constraint(equalTo: v.safeAreaLayoutGuide.bottomAnchor, constant: -frameHeight),
            
            b.heightAnchor.constraint(equalToConstant: 0.5),
            b.bottomAnchor.constraint(equalTo: ts.topAnchor),
            b.leadingAnchor.constraint(equalTo: ts.leadingAnchor),
            b.trailingAnchor.constraint(equalTo: ts.trailingAnchor),
        ])
    }
    
    private func hideTabBar() {
        guard let ts = tabScroll, let b = tabBorder else { return  }
        
        additionalSafeAreaInsets = .zero
        
        tabScroll = nil
        tabBorder = nil
        tabsWidth = nil
        
        ts.removeFromSuperview()
        b.removeFromSuperview()
        tabs.removeFromSuperview()
    }
    
	func localNotificationSelected(userInfo: [AnyHashable : Any], action: String) {
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
				DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
                    self.selectTab(for: item, overrideUrl: urlToOpen, andOpen: true)
				}
			}
		} else {
			showMessage("Item not found", "Could not locate the item related to this notification")
		}
	}

    private func selectTab(for item: ListableItem, overrideUrl: String?, andOpen: Bool) {
		var tabItem: UITabBarItem?
		for d in tabBarSets {
			if d.viewCriterion == nil || d.viewCriterion?.isRelated(to: item) ?? false {
				tabItem = item is PullRequest ? d.prItem : d.issuesItem
				break
			}
		}
        requestTabFocus(tabItem: tabItem, item: item, overrideUrl: overrideUrl, andOpen: andOpen)
	}

    func highightItemWithUriPath(uriPath: String) {
		if
			let itemId = DataManager.id(for: uriPath),
			let item = existingObject(with: itemId) as? ListableItem {
            selectTab(for: item, overrideUrl: nil, andOpen: false)
		}
	}

	func openCommentWithId(cId: String) {
		if let
			itemId = DataManager.id(for: cId),
			let comment = existingObject(with: itemId) as? PRComment,
			let item = comment.parent {
            selectTab(for: item, overrideUrl: nil, andOpen: true)
		}
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        tableView.reloadData()
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
        
        tableView.deselectRow(at: indexPath, animated: true)
	}

	private func showDetail(url: URL, objectId: NSManagedObjectID) {
        if let item = existingObject(with: objectId) as? ListableItem {
            item.catchUpWithComments()
        }
        UIApplication.shared.open(url, options: [:])
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
		return 40
	}

	func markItemAsRead(itemUri: String?) {
		if let
			i = itemUri,
			let oid = DataManager.id(for: i),
			let o = existingObject(with: oid) as? ListableItem {
			o.catchUpWithComments()
		}
	}

	func markItemAsUnRead(itemUri: String?) {
		if let
			i = itemUri,
			let oid = DataManager.id(for: i),
			let o = existingObject(with: oid) as? ListableItem {
			o.latestReadCommentDate = .distantPast
			o.postProcess()
		}
	}

	private func showSnoozeMenuFor(i: ListableItem) {
		let snoozePresets = SnoozePreset.allSnoozePresets(in: DataManager.main)
		let hasPresets = !snoozePresets.isEmpty
		let a = UIAlertController(title: hasPresets ? "Snooze" : nil,
		                          message: hasPresets ? S(i.title) : "You do not currently have any snoozing presets configured. Please add some in the relevant preferences tab.",
		                          preferredStyle: .alert)
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
		@unknown default:
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
		@unknown default:
			break
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

		if becauseOfChanges || updateItems {
            if becauseOfChanges {
                watchManager.updateContext()
            }
            updateTabItems(animated: true)
		}

		updateFooter()
		refreshUpdated()
        updateTitle()
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

	///////////////////////////// filtering

	override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		becomeFirstResponder()
        if scrollView.contentOffset.y <= 0, !API.isRefreshing {
            refreshControl?.attributedTitle = NSAttributedString(string: API.lastSuccessfulSyncAt, attributes: nil)
        }
	}

	func updateSearchResults(for searchController: UISearchController) {
		searchTimer.push()
	}

	private func safeScrollToTop(completion: Completion?) {
		tableView.contentOffset = tableView.contentOffset // halt any inertial scrolling
        DispatchQueue.main.async { [weak self] in
            guard let S = self else { return }
			if S.tableView.numberOfSections > 0 {
				S.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
			}
			DispatchQueue.main.async {
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
            let index = sender as? Int ?? Settings.lastPreferencesTabSelected
            if allServersHaveTokens {
                destination.selectedIndex = min(index, (destination.viewControllers?.count ?? 1)-1)
			}
            destination.delegate = self
		}
	}

	func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
		Settings.lastPreferencesTabSelected = tabBarController.viewControllers?.firstIndex(of: viewController) ?? 0
	}
}
