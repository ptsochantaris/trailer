
import UIKit
import CoreData

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

final class MasterViewController: UITableViewController, NSFetchedResultsControllerDelegate, UISearchBarDelegate, UITabBarControllerDelegate, UITabBarDelegate {

	private var detailViewController: DetailViewController!
	private var _fetchedResultsController: NSFetchedResultsController<ListableItem>?

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
		a.addAction(UIAlertAction(title: "Yes", style: .default) { [weak self] action in
			self?.markAllAsRead()
		})
		present(a, animated: true, completion: nil)
	}

	private func tryRefresh() {
		refreshOnRelease = false

		if API.hasNetworkConnection {
			if !app.startRefresh() {
				updateStatus()
			}
		} else {
			showMessage("No Network", "There is no network connectivity, please try again later")
			updateStatus()
		}
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
				S.present(a, animated: true, completion: nil)
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
				S.present(a, animated: true, completion: nil)
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
		DataManager.saveDB()
	}

	func removeAllMergedConfirmed() {
		if viewingPrs {
			for p in PullRequest.allMerged(in: DataManager.main, criterion: currentTabBarSet?.viewCriterion) {
				DataManager.main.delete(p)
			}
			DataManager.saveDB()
		}
	}

	func markAllAsRead() {
		for i in fetchedResultsController.fetchedObjects ?? [] {
			i.catchUpWithComments()
		}
		DataManager.saveDB()
		updateStatus()
	}

	func refreshControlChanged() {
		refreshOnRelease = !appIsRefreshing
	}

	override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		if refreshOnRelease {
			tryRefresh()
		}
	}

	override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
		if refreshOnRelease {
			tryRefresh()
		}
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		refreshLabel.center = CGPoint(x: view.bounds.midX, y: refreshControl!.center.y+36)
		layoutTabs()
	}

	func layoutTabs() {
		if let v = navigationController?.view, let t = tabs, let ts = tabScroll, let tb = tabBorder, let ts1 = tabSide1, let ts2 = tabSide2 {
			let b = v.bounds.size
			let w = b.width
			let h = b.height
			let tabScrollTransform = ts.transform
			let tabBorderTransform = tb.transform

			let tf = CGRect(x: 0, y: 0, width: max(w, 64*CGFloat(t.items?.count ?? 1)), height: 49)
			t.frame = tf
			ts.contentSize = tf.size

			ts.frame = CGRect(x: 0, y: h-49, width: w, height: 49)
			ts.transform = tabScrollTransform

			tb.frame = CGRect(x: 0, y: h-49.5, width: w, height: 0.5)
			tb.transform = tabBorderTransform

			let ww = w*0.5
			ts1.frame = CGRect(x: -ww, y: 0, width: ww, height: 49)
			ts2.frame = CGRect(x: w, y: 0, width: ww, height: 49)

			if navigationController?.visibleViewController == self || navigationController?.visibleViewController?.presentingViewController != nil {
				v.bringSubview(toFront: tb)
				v.bringSubview(toFront: ts)
			} else {
				v.sendSubview(toBack: tb)
				v.sendSubview(toBack: ts)
			}
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateStatus()
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		view.addSubview(refreshLabel)

		searchTimer = PopTimer(timeInterval: 0.5) { [weak self] in
			self?.applyFilter()
		}

		refreshControl?.addTarget(self, action: #selector(refreshControlChanged), for: .valueChanged)

		tableView.rowHeight = UITableViewAutomaticDimension
		tableView.estimatedRowHeight = 240
		tableView.register(UINib(nibName: "SectionHeaderView", bundle: nil), forHeaderFooterViewReuseIdentifier: "SectionHeaderView")
		tableView.contentOffset = CGPoint(x: 0, y: 44)
		clearsSelectionOnViewWillAppear = false

		if let detailNav = splitViewController?.viewControllers.last as? UINavigationController {
			detailViewController = detailNav.topViewController as? DetailViewController
		}

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(updateStatus), name: RefreshStartedNotification, object: nil)
		n.addObserver(self, selector: #selector(updateStatus), name: RefreshEndedNotification, object: nil)
		n.addObserver(self, selector: #selector(updateRefresh), name: SyncProgressUpdateNotification, object: nil)

		updateTabItems(animated: false)
		atNextEvent {
			self.tableView.reloadData() // ensure footers are correct
		}
	}

	func updateRefresh() {
		refreshLabel.text = API.lastUpdateDescription
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

	func keyToggleSnooze() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			if i.isSnoozing {
				if canIssueKeyForIndexPath(actionTitle: "Wake", indexPath: ip) {
					i.wakeUp()
					DataManager.saveDB()
					updateStatus()
				}
			} else {
				if canIssueKeyForIndexPath(actionTitle: "Snooze", indexPath: ip) {
					showSnoozeMenuFor(i: i)
				}
			}
		}
	}

	func keyToggleRead() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			if i.unreadComments > 0 {
				if canIssueKeyForIndexPath(actionTitle: "Read", indexPath: ip) {
					i.catchUpWithComments()
					DataManager.saveDB()
				}
			} else {
				if canIssueKeyForIndexPath(actionTitle: "Unread", indexPath: ip) {
					markItemAsUnRead(itemUri: i.objectID.uriRepresentation().absoluteString)
				}
			}
			updateStatus()
		}
	}

	func keyToggleMute() {
		if let ip = tableView.indexPathForSelectedRow {
			let i = fetchedResultsController.object(at: ip)
			let isMuted = i.muted
			if (!isMuted && canIssueKeyForIndexPath(actionTitle: "Mute", indexPath: ip)) || (isMuted && canIssueKeyForIndexPath(actionTitle: "Unmute", indexPath: ip)) {
				i.setMute(to: !isMuted)
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
		_ = detailViewController.becomeFirstResponder()
	}

	func keyOpenInSafari() {
		if let ip = tableView.indexPathForSelectedRow {
			forceSafari = true
			tableView(tableView, didSelectRowAt: ip)
		}
	}

	func keyShowSelectedItem() {
		if let ip = tableView.indexPathForSelectedRow {
			tableView(tableView, didSelectRowAt: ip)
		}
	}

	func keyMoveToNextItem() {
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

	func keyMoveToPreviousItem() {
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

	func keyMoveToPreviousSection() {
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

	func keyMoveToNextSection() {
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

	func moveToNextTab() {
		if let t = tabs, let i = t.selectedItem, let items = t.items, let ind = items.index(of: i), items.count > 1 {
			var nextIndex = ind+1
			if nextIndex >= items.count {
				nextIndex = 0
			}
			requestTabFocus(item: items[nextIndex])
		}
	}

	func moveToPreviousTab() {
		if let t = tabs, let i = t.selectedItem, let items = t.items, let ind = items.index(of: i), items.count > 1 {
			var nextIndex = ind-1
			if nextIndex < 0 {
				nextIndex = items.count-1
			}
			requestTabFocus(item: items[nextIndex])
		}
	}

	private func requestTabFocus(item: UITabBarItem?) {
		if let i = item {
			lastTabIndex = tabs?.items?.index(of: i) ?? 0
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

	func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
		lastTabIndex = tabs?.items?.index(of: item) ?? 0
		resetView()
	}

	override func scrollViewDidScroll(_ scrollView: UIScrollView) {
		updateRefreshControls()
	}

	private func updateRefreshControls() {
		let ra = min(1.0, max(0, (-84-tableView.contentOffset.y)/32.0))
		if ra > 0.0 && refreshLabel.alpha == 0 {
			refreshLabel.text = API.lastUpdateDescription
		}
		refreshLabel.alpha = ra
		refreshControl?.alpha = ra
		searchBar.alpha = min(1.0, max(0, ((116+tableView.contentOffset.y)/32.0)))
	}

	private func applyFilter() {

		let r = Range(uncheckedBounds: (lower: 0, upper: fetchedResultsController.sections?.count ?? 0))
		let currentIndexes = IndexSet(integersIn: r)

		_fetchedResultsController = nil

		let r2 = Range(uncheckedBounds: (lower: 0, upper: fetchedResultsController.sections?.count ?? 0))
		let dataIndexes = IndexSet(integersIn: r2)

		let removedIndexes = currentIndexes.filter { !dataIndexes.contains($0) }
		let addedIndexes = dataIndexes.filter { !currentIndexes.contains($0) }
		let untouchedIndexes = dataIndexes.filter { !(removedIndexes.contains($0) || addedIndexes.contains($0)) }

		tableView.beginUpdates()
		if removedIndexes.count > 0 {
			tableView.deleteSections(IndexSet(removedIndexes), with:.automatic)
		}
		if untouchedIndexes.count > 0 {
			tableView.reloadSections(IndexSet(untouchedIndexes), with:.automatic)
		}
		if addedIndexes.count > 0 {
			tableView.insertSections(IndexSet(addedIndexes), with:.automatic)
		}
		tableView.endUpdates()
		updateFooter()
	}

	private func updateTabItems(animated: Bool) {

		tabBarSets.removeAll()

		for groupLabel in Repo.allGroupLabels {
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

		if items.count > 1 {
			showEmpty = false
			showTabBar(show: true, animated: animated)

			tabs?.items = items
			tabs?.superview?.setNeedsLayout()

			if items.count > lastTabIndex {
				tabs?.selectedItem = items[lastTabIndex]
				currentTabBarSet = tabBarSetForTabItem(i: items[lastTabIndex])
			} else {
				tabs?.selectedItem = items.last
				currentTabBarSet = tabBarSetForTabItem(i: items.last!)
			}
		} else {
			showEmpty = items.count == 0
			currentTabBarSet = tabBarSetForTabItem(i: items.first)
			showTabBar(show: false, animated: animated)
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

		let newCount = tabs?.items?.count ?? 0

		let latestFetchRequest = _fetchedResultsController?.fetchRequest
		let newFetchRequest = itemFetchRequest

		if newCount != lastTabCount || latestFetchRequest != newFetchRequest {
			_fetchedResultsController = nil
			tableView.reloadData()
		}

		if let ts = tabScroll, let t = tabs, let i = t.selectedItem, let ind = t.items?.index(of: i) {
			let w = t.bounds.size.width / CGFloat(t.items?.count ?? 1)
			let x = w*CGFloat(ind)
			let f = CGRect(x: x, y: 0, width: w, height: t.bounds.size.height)
			ts.scrollRectToVisible(f, animated: true)
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
	private func showTabBar(show: Bool, animated: Bool) {
		if show {

			if tabScroll == nil, let s = navigationController?.view {

				tableView.scrollIndicatorInsets = UIEdgeInsets(top: tableView.scrollIndicatorInsets.top, left: 0, bottom: 49, right: 0)

				let t = UITabBar()
				t.delegate = self
				t.itemPositioning = .fill
				tabs = t

				let ts = UIScrollView()
				ts.showsHorizontalScrollIndicator = false
				ts.alwaysBounceHorizontal = true
				ts.scrollsToTop = false
				ts.addSubview(t)

				let s1 = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
				tabSide1 = s1
				ts.addSubview(s1)

				let s2 = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
				tabSide2 = s2
				ts.addSubview(s2)

				let b = UIView()
				b.backgroundColor = UIColor.black.withAlphaComponent(DISABLED_FADE)
				b.isUserInteractionEnabled = false
				s.addSubview(b)
				tabBorder = b

				s.addSubview(ts)
				tabScroll = ts

				if animated {
					ts.transform = CGAffineTransform(translationX: 0, y: 49)
					b.transform = CGAffineTransform(translationX: 0, y: 49)
					UIView.animate(withDuration: 0.2,
						delay: 0.0,
						options: .curveEaseInOut,
						animations: {
							ts.transform = CGAffineTransform.identity
							b.transform = CGAffineTransform.identity
						}, completion: nil)
				}
			}

		} else {

			tableView.scrollIndicatorInsets = UIEdgeInsets(top: tableView.scrollIndicatorInsets.top, left: 0, bottom: 0, right: 0)

			if let t = tabScroll, let b = tabBorder {

				tabs = nil
				tabScroll = nil
				tabBorder = nil
				tabSide1 = nil
				tabSide2 = nil

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

	func localNotification(userInfo: [AnyHashable : Any], action: String?) {
		var urlToOpen = userInfo[NOTIFICATION_URL_KEY] as? String
		var relatedItem: ListableItem?

		if let commentId = DataManager.id(for: userInfo[COMMENT_ID_KEY] as? String), let c = existingObject(with: commentId) as? PRComment {
			relatedItem = c.parent
			if urlToOpen == nil {
				urlToOpen = c.webUrl
			}
		} else if let uri = userInfo[LISTABLE_URI_KEY] as? String, let itemId = DataManager.id(for: uri) {
			relatedItem = existingObject(with: itemId) as? ListableItem
			if relatedItem == nil {
				showMessage("Item not found", "Could not locate the item related to this notification")
			} else if urlToOpen == nil {
				urlToOpen = relatedItem!.webUrl
			}
		}

		if let a = action, let i = relatedItem {
			if a == "mute" {
				i.setMute(to: true)
				DataManager.saveDB()
				updateStatus()
				return
			} else if a == "read" {
				i.catchUpWithComments()
				DataManager.saveDB()
				updateStatus()
				return
			}
		}

		if urlToOpen != nil && !S(searchBar.text).isEmpty {
			searchBar.text = nil
			searchBar.resignFirstResponder()
			resetView()
		}

		var oid: NSManagedObjectID?

		if let i = relatedItem {
			selectTabFor(i: i)
			oid = i.objectID
			atNextEvent(self) { S in
				if let ip = S.fetchedResultsController.indexPath(forObject: i) {
					S.tableView.selectRow(at: ip, animated: false, scrollPosition: .middle)
				}
			}
		}

		if let u = urlToOpen, let url = URL(string: u) {
			showDetail(url: url, objectId: oid)
		} else {
			showDetail(url: nil, objectId: nil)
		}
	}

	private func selectTabFor(i: ListableItem) {
		for d in tabBarSets {
			if d.viewCriterion == nil || d.viewCriterion?.isRelated(to: i) ?? false {
				if i is PullRequest {
					requestTabFocus(item: d.prItem)
				} else {
					requestTabFocus(item: d.issuesItem)
				}
			}
		}
	}

	func openItemWithUriPath(uriPath: String) {
		if let itemId = DataManager.id(for: uriPath),
			let item = existingObject(with: itemId) as? ListableItem,
			let ip = fetchedResultsController.indexPath(forObject: item) {

			selectTabFor(i: item)
			item.catchUpWithComments()
			tableView.selectRow(at: ip, animated: false, scrollPosition: .middle)
			tableView(tableView, didSelectRowAt: ip)
		}
	}

	func openCommentWithId(cId: String) {
		if let
			itemId = DataManager.id(for: cId),
			let comment = existingObject(with: itemId) as? PRComment
		{
			if let url = comment.webUrl {
				var ip: IndexPath?
				if let item = comment.parent {
					selectTabFor(i: item)
					ip = fetchedResultsController.indexPath(forObject: item)
					item.catchUpWithComments()
				}
				if let i = ip {
					tableView.selectRow(at: i, animated: false, scrollPosition: .middle)
					showDetail(url: URL(string: url), objectId: nil)
				}
			}
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
		if let u = p.urlForOpening, let url = URL(string: u)
		{
			if forceSafari || (Settings.openItemsDirectlyInSafari && !detailViewController.isVisible) {
				UIApplication.shared.open(url, options: [:]) { success in
					p.catchUpWithComments()
				}
			} else {
				showDetail(url: url, objectId: p.objectID)
			}
		}

		forceSafari = false
	}

	private func showDetail(url: URL?, objectId: NSManagedObjectID?) {
		detailViewController.catchupWithDataItemWhenLoaded = objectId
		detailViewController.detailItem = url
		if !detailViewController.isVisible {
			showTabBar(show: false, animated: true)
			showDetailViewController(detailViewController.navigationController ?? detailViewController, sender: self)
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
			return tabs == nil ? 20 : 20+49
		}
		return 1
	}

	private func markItemAsUnRead(itemUri: String?) {
		if let
			i = itemUri,
			let oid = DataManager.id(for: i),
			let o = existingObject(with: oid) as? ListableItem {
			o.latestReadCommentDate = .distantPast
			o.postProcess()
			DataManager.saveDB()
			popupManager.masterController.updateStatus()
		}
	}

	override func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {

		var actions = [UITableViewRowAction]()

		func markItemAsRead(itemUri: String?) {
			if let
				i = itemUri,
				let oid = DataManager.id(for: i),
				let o = existingObject(with: oid) as? ListableItem {
				o.catchUpWithComments()
				DataManager.saveDB()
				popupManager.masterController.updateStatus()
			}
		}

		func appendReadUnread(i: ListableItem) {
			let r: UITableViewRowAction
			if i.unreadComments > 0 {
				r = UITableViewRowAction(style: .normal, title: "Read") { action, indexPath in
					markItemAsRead(itemUri: i.objectID.uriRepresentation().absoluteString)
					tableView.setEditing(false, animated: true)
				}
			} else {
				r = UITableViewRowAction(style: .normal, title: "Unread") { [weak self] action, indexPath in
					self?.markItemAsUnRead(itemUri: i.objectID.uriRepresentation().absoluteString)
					tableView.setEditing(false, animated: true)
				}
			}
			r.backgroundColor = view.tintColor
			actions.append(r)
		}

		func appendMuteUnmute(i: ListableItem) {
			let m: UITableViewRowAction
			if i.muted {
				m = UITableViewRowAction(style: .normal, title: "Unmute") { action, indexPath in
					i.setMute(to: false)
					DataManager.saveDB()
					tableView.setEditing(false, animated: true)
				}
			} else {
				m = UITableViewRowAction(style: .normal, title: "Mute") { action, indexPath in
					i.setMute(to: true)
					DataManager.saveDB()
					tableView.setEditing(false, animated: true)
				}
			}
			actions.append(m)
		}

		let i = fetchedResultsController.object(at:
			indexPath)
		if let sectionName = fetchedResultsController.sections?[indexPath.section].name {

			if sectionName == Section.merged.prMenuName || sectionName == Section.closed.prMenuName || sectionName == Section.closed.issuesMenuName {

				appendReadUnread(i: i)
				let d = UITableViewRowAction(style: .destructive, title: "Remove") { action, indexPath in
					DataManager.main.delete(i)
					DataManager.saveDB()
				}
				actions.append(d)

			} else if i.isSnoozing {

				let w = UITableViewRowAction(style: .normal, title: "Wake") { action, indexPath in
					i.wakeUp()
					DataManager.saveDB()
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
				DataManager.saveDB()
			})
		}
		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		present(a, animated: true, completion: nil)
	}

	private var fetchedResultsController: NSFetchedResultsController<ListableItem> {
		if let c = _fetchedResultsController {
			return c
		}

		let c = NSFetchedResultsController(fetchRequest: itemFetchRequest, managedObjectContext: DataManager.main, sectionNameKeyPath: "sectionName", cacheName: nil)
		_fetchedResultsController = c
		c.delegate = self
		try! c.performFetch()
		return c
	}

	private var itemFetchRequest: NSFetchRequest<ListableItem> {
		let type: ListableItem.Type = viewingPrs ? PullRequest.self : Issue.self
		return ListableItem.requestForItems(of: type, withFilter: searchBar.text, sectionIndex: -1, criterion: currentTabBarSet?.viewCriterion)
	}

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		if UIApplication.shared.applicationState != .active { return }
		tableView.beginUpdates()
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {

		if UIApplication.shared.applicationState != .active { return }

		switch(type) {
		case .insert:
			tableView.insertSections(IndexSet(integer: sectionIndex) as IndexSet, with: .automatic)
		case .delete:
			tableView.deleteSections(IndexSet(integer: sectionIndex) as IndexSet, with: .automatic)
		case .update, .move:
			break
		}
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

		if UIApplication.shared.applicationState != .active { return }

		switch(type) {
		case .insert:
			if let n = newIndexPath {
				tableView.insertRows(at: [n], with: .automatic)
			}
		case .delete:
			if let i = indexPath {
				tableView.deleteRows(at: [i], with: .automatic)
			}
		case .update:
			if let i = indexPath, let object = anObject as? ListableItem, let cell = tableView.cellForRow(at: i) {
				configureCell(cell: cell, withObject: object)
			}
		case .move:
			if let i = indexPath {
				tableView.deleteRows(at: [i], with: .automatic)
			}
			if let n = newIndexPath {
				tableView.insertRows(at: [n], with: .automatic)
			}
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		if UIApplication.shared.applicationState != .active {
			tableView.reloadData()
		} else {
			tableView.endUpdates()
		}
		atNextEvent { [weak self] in
			self?.updateStatus()
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
	private var showEmpty = true

	func updateStatus() {

		updateTabItems(animated: true)
		updateFooter()

		if appIsRefreshing {
			title = "Refreshing..."
			if let r = refreshControl {
				refreshLabel.text = API.lastUpdateDescription
				updateRefreshControls()
				r.beginRefreshing()
			}
		} else {

			title = showEmpty ? "No Items"
				: viewingPrs ? pullRequestsTitle(long: true)
				: issuesTitle

			if let r = refreshControl {
				refreshLabel.text = API.lastUpdateDescription
				updateRefreshControls()
				r.endRefreshing()
			}
		}

		app.updateBadge()

		if splitViewController?.displayMode != .allVisible {
			detailViewController.navigationItem.leftBarButtonItem?.title = title
		}
	}

	private func updateFooter() {
		if fetchedResultsController.fetchedObjects?.count ?? 0 == 0 {
			let reasonForEmpty: NSAttributedString
			if viewingPrs {
				reasonForEmpty = PullRequest.reasonForEmpty(with: searchBar.text, criterion: currentTabBarSet?.viewCriterion)
			} else {
				reasonForEmpty = Issue.reasonForEmpty(with: searchBar.text, criterion: currentTabBarSet?.viewCriterion)
			}
			tableView.tableFooterView = EmptyView(message: reasonForEmpty, parentWidth: view.bounds.size.width)
		} else {
			tableView.tableFooterView = nil
		}
	}

	private func unreadCommentCount(count: Int) -> String {
		return count == 0 ? "" : count == 1 ? " (1 new comment)" : " (\(count) new comments)"
	}

	private func pullRequestsTitle(long: Bool) -> String {

		let f = ListableItem.requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: currentTabBarSet?.viewCriterion)
		let count = try! DataManager.main.count(for: f)
		let unreadCount = Int(currentTabBarSet?.prItem?.badgeValue ?? "0")!

		let pr = long ? "Pull Request" : "PR"
		if count == 0 {
			return "No \(pr)s"
		} else if count == 1 {
			let suffix = unreadCount > 0 ? "PR\(unreadCommentCount(count: unreadCount))" : pr
			return "1 \(suffix)"
		} else {
			let suffix = unreadCount > 0 ? "PRs\(unreadCommentCount(count: unreadCount))" : "\(pr)s"
			return "\(count) \(suffix)"
		}
	}

	private var issuesTitle: String {

		let f = ListableItem.requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: currentTabBarSet?.viewCriterion)
		let count = try! DataManager.main.count(for: f)
		let unreadCount = Int(currentTabBarSet?.issuesItem?.badgeValue ?? "0")!

		if count == 0 {
			return "No Issues"
		} else if count == 1 {
			let commentCount = unreadCommentCount(count: unreadCount)
			return "1 Issue\(commentCount)"
		} else {
			let commentCount = unreadCommentCount(count: unreadCount)
			return "\(count) Issues\(commentCount)"
		}
	}

	///////////////////////////// filtering

	override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		becomeFirstResponder()
	}

	func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
		if let r = refreshControl, r.isRefreshing {
			r.endRefreshing()
		}
		searchBar.setShowsCancelButton(true, animated: true)
	}

	func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
		searchBar.setShowsCancelButton(false, animated: true)
	}

	func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
		searchTimer.push()
	}

	func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
		searchBar.text = nil
		searchTimer.push()
		view.endEditing(false)
	}

	func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
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
			if let n = t?.numberOfSections, n > 0 {
				t?.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
			}
		}
	}

	func focusFilter() {
		tableView.contentOffset = CGPoint(x: 0, y: -tableView.contentInset.top)
		searchBar.becomeFirstResponder()
	}

	func resetView() {
		safeScrollToTop()
		_fetchedResultsController = nil
		updateStatus()
		tableView.reloadData()
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
