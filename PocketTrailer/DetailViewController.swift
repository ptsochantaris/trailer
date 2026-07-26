import CoreData
import PopTimer
import UIKit
import UserNotifications

final class DetailViewController: UITableViewController, NSFetchedResultsControllerDelegate, UISearchResultsUpdating, UITableViewDragDelegate {
    private var fetchedResultsController: NSFetchedResultsController<ListableItem>?
    private var searchTimer: PopTimer!
    private var animatedUpdates = false
    private var sectionsChanged = false
    private var lastTabCount = 0
    private let watchManager = WatchManager()

    private var observers = [NotificationObserver]()

    private var viewingPrs: Bool {
        currentTabBar?.isPr == true
    }

    private var pluralNameForItems: String {
        viewingPrs ? "pull requests" : "issues"
    }

    var currentTabBar: TabInfo? {
        didSet {
            updateSectionInfo()
            Task {
                tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
            }
        }
    }

    @IBAction private func editSelected(_ sender: UIBarButtonItem) {
        let promptTitle: String = if let l = currentTabBar?.viewCriterion?.label {
            "\(pluralNameForItems.capitalized) in '\(l)'"
        } else {
            pluralNameForItems.capitalized
        }

        let a = UIAlertController(title: promptTitle, message: nil, preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "Mark All As Read", style: .default) { _ in
            self.markAllAsRead()
        })
        if !SectionListViewController.tabBarSets.isEmpty {
            a.addAction(UIAlertAction(title: "On Other Sections Too", style: .destructive) { _ in
                app.markEverythingRead(settings: Settings.cache)
            })
        }
        present(a, animated: true)
        a.popoverPresentationController?.barButtonItem = sender
    }

    func removeAllMerged() {
        Task { [weak self] in
            guard let self else { return }
            if Settings.dontAskBeforeWipingMerged {
                removeAllMergedConfirmed()
            } else {
                let a = UIAlertController(title: "Sure?", message: "Remove all \(pluralNameForItems) in the Merged section?", preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                a.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                    self?.removeAllMergedConfirmed()
                })
                present(a, animated: true)
            }
        }
    }

    func removeAllClosed() {
        Task { [weak self] in
            guard let self else { return }
            if Settings.dontAskBeforeWipingClosed {
                removeAllClosedConfirmed()
            } else {
                let a = UIAlertController(title: "Sure?", message: "Remove all \(pluralNameForItems) in the Closed section?", preferredStyle: .alert)
                a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                a.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
                    self?.removeAllClosedConfirmed()
                })
                present(a, animated: true)
            }
        }
    }

    private func removeAllClosedConfirmed() {
        if viewingPrs {
            for p in PullRequest.allClosed(in: DataManager.main, criterion: currentTabBar?.viewCriterion) {
                DataManager.main.delete(p)
            }
        } else {
            for p in Issue.allClosed(in: DataManager.main, criterion: currentTabBar?.viewCriterion) {
                DataManager.main.delete(p)
            }
        }
    }

    private func removeAllMergedConfirmed() {
        if viewingPrs {
            for p in PullRequest.allMerged(in: DataManager.main, criterion: currentTabBar?.viewCriterion) {
                DataManager.main.delete(p)
            }
        }
    }

    private func markAllAsRead() {
        let settings = Settings.cache
        for i in fetchedResultsController?.fetchedObjects ?? [] {
            i.catchUpWithComments(settings: settings)
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

        if let splitViewController, !splitViewController.isCollapsed {
            return
        } else if let i = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: i, animated: true)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Replaces `traitCollectionDidChange`, deprecated in iOS 17. That fired for *any* trait change;
        // these are the ones that actually change how a cell draws — appearance for colours, content
        // size category for fonts, size class for layout. Declaring the first closure parameter as
        // `self: Self` is what keeps this from capturing self strongly.
        registerForTraitChanges([UITraitUserInterfaceStyle.self,
                                 UITraitPreferredContentSizeCategory.self,
                                 UITraitHorizontalSizeClass.self,
                                 UITraitVerticalSizeClass.self]) { (self: Self, _: UITraitCollection) in
            self.tableView.reloadData()
        }

        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.tintColor = view.tintColor
        searchController.searchBar.placeholder = "Filter"
        searchController.searchBar.autocapitalizationType = .none
        if #available(iOS 26.0, *) {
            navigationItem.preferredSearchBarPlacement = .integrated
        }
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

        observers = [
            NotificationObserver(.SyncProgressUpdate, debounce: 0.1) { [weak self] _ in
                self?.refreshUpdated()
            },
            NotificationObserver(.RefreshStarting, debounce: 0.1) { [weak self] _ in
                self?.updateStatus(becauseOfChanges: false)
            },
            NotificationObserver(.RefreshEnded, debounce: 0.1) { [weak self] _ in
                self?.refreshEnded()
            },
            NotificationObserver(.focusFilter, debounce: 0.1) { [weak self] notification in
                self?.focusFilter(terms: notification.object as? String)
            },
            NotificationObserver(.highlightItem, debounce: 0.1) { [weak self] notification in
                if let uri = notification.object as? String {
                    self?.highlightItemWithUriPath(uriPath: uri)
                }
            },
            NotificationObserver(.NSManagedObjectContextObjectsDidChange, debounce: 0.1) { [weak self] notification in
                self?.dataUpdated(notification)
            },
            NotificationObserver(.dbSaved, debounce: 0.1) { [weak self] _ in
                self?.updateStatus(becauseOfChanges: true)
            },
            NotificationObserver(.resetView) { [weak self] _ in
                self?.resetView()
            },
            NotificationObserver(.notificationSelected) { [weak self] notification in
                if let (item, url) = notification.object as? (ListableItem, String?) {
                    self?.notificationSelected(for: item, urlToOpen: url)
                }
            },
            NotificationObserver(.openComment, debounce: 0.1) { [weak self] notification in
                if let id = notification.object as? String {
                    self?.openCommentWithId(cId: id)
                }
            }
        ]

        newTabBarSets()

        updateSectionInfo()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if currentTabBar == nil, let splitViewController, splitViewController.isCollapsed {
            splitViewController.show(.primary)
        }
    }

    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        if let p = fetchedResultsController?.object(at: indexPath) {
            return [p.dragItemForUrl(settings: Settings.cache)]
        }
        return []
    }

    func tableView(_: UITableView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point _: CGPoint) -> [UIDragItem] {
        let p = fetchedResultsController?.object(at: indexPath)
        if let dragItem = p?.dragItemForUrl(settings: Settings.cache) {
            return session.items.contains(dragItem) ? [] : [dragItem]
        }
        return []
    }

    private func dataUpdated(_ notification: Notification) {
        guard let relatedMoc = notification.object as? NSManagedObjectContext, relatedMoc === DataManager.main else { return }

        if let items = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>, items.contains(where: { $0 is ListableItem }) {
            // Logging.shared.log(">>>>>>>>>>>>>>> detected inserted items")
            Task {
                updateStatus(becauseOfChanges: true)
            }
            return
        }

        if let items = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject>, items.contains(where: { $0 is ListableItem }) {
            // Logging.shared.log(">>>>>>>>>>>>>>> detected deleted items")
            Task {
                updateStatus(becauseOfChanges: true)
            }
            return
        }

        if let items = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject>, items.contains(where: { ($0 as? ListableItem)?.hasPersistentChangedValues ?? false }) {
            // Logging.shared.log(">>>>>>>>>>>>>>> detected permanently changed items")
            Task {
                updateStatus(becauseOfChanges: true)
            }
            return
        }
    }

    private func refreshEnded() {
        refreshControl?.endRefreshing()
        if fetchedResultsController?.sections?.count ?? 0 == 0 {
            updateStatus(becauseOfChanges: false)
        }
    }

    private func updateTitle() {
        let newTitle: String

        if API.isRefreshing {
            newTitle = "Refreshing…"

        } else if let item = currentTabBar {
            if item.isPr {
                let unreadCount = Int(item.badgeValue ?? "0")!
                let t = item.title
                if unreadCount > 0 {
                    newTitle = t.appending(" (\(unreadCount))")
                } else {
                    newTitle = t
                }

            } else {
                let unreadCount = Int(item.badgeValue ?? "0")!
                let t = item.title
                if unreadCount > 0 {
                    newTitle = t.appending(" (\(unreadCount))")
                } else {
                    newTitle = t
                }
            }
        } else {
            newTitle = "Not Selected"
        }

        if title != newTitle {
            title = newTitle
        }
    }

    private func refreshUpdated() {
        updateTitle()
        let name = API.currentOperationName
        refreshControl?.attributedTitle = NSAttributedString(string: name, attributes: nil)
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    override var keyCommands: [UIKeyCommand]? {
        [
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
        guard let actions = fetchedResultsController?.object(at: indexPath).contextActions(settings: Settings.cache) else {
            return false
        }
        if actions.contains(action) {
            return true
        } else {
            showMessage("\(action.title) not available", "This command cannot be used on this item")
            return false
        }
    }

    @objc private func keyToggleSnooze() {
        if let ip = tableView.indexPathForSelectedRow {
            guard let i = fetchedResultsController?.object(at: ip) else {
                return
            }
            if i.isSnoozing {
                if canIssueKeyForIndexPath(action: .wake(date: i.snoozeUntil), indexPath: ip) {
                    i.wakeUp(settings: Settings.cache)
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
            guard let i = fetchedResultsController?.object(at: ip) else {
                return
            }
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
        if let ip = tableView.indexPathForSelectedRow, let i = fetchedResultsController?.object(at: ip) {
            let isMuted = i.muted
            if (!isMuted && canIssueKeyForIndexPath(action: .mute, indexPath: ip)) || (isMuted && canIssueKeyForIndexPath(action: .unmute, indexPath: ip)) {
                i.setMute(to: !isMuted, settings: Settings.cache)
            }
        }
    }

    @objc private func keyForceRefresh() {
        Task {
            switch await app.startRefresh() {
            case .alreadyRefreshing, .started:
                break
            case .noConfiguredServers:
                showMessage("No Configured Servers", "There are no configured servers to sync from, please check your settings")
            case .noNetwork:
                showMessage("No Network", "There is no network connectivity, please try again later")
            }
            updateStatus(becauseOfChanges: false)
        }
    }

    @objc private func keyShowSelectedItem() {
        if let ip = tableView.indexPathForSelectedRow {
            tableView(tableView, didSelectRowAt: ip)
        }
    }

    @objc private func keyMoveToNextItem() {
        if let ip = tableView.indexPathForSelectedRow {
            var newRow = ip.row + 1
            var newSection = ip.section
            if newRow >= tableView.numberOfRows(inSection: ip.section) {
                newSection += 1
                if newSection >= tableView.numberOfSections {
                    return // end of the table
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
            var newRow = ip.row - 1
            var newSection = ip.section
            if newRow < 0 {
                newSection -= 1
                if newSection < 0 {
                    return // start of the table
                }
                newRow = tableView.numberOfRows(inSection: newSection) - 1
            }
            tableView.selectRow(at: IndexPath(row: newRow, section: newSection), animated: true, scrollPosition: .middle)
        } else if numberOfSections(in: tableView) > 0 {
            tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: true, scrollPosition: .top)
        }
    }

    @objc private func keyMoveToPreviousSection() {
        if let ip = tableView.indexPathForSelectedRow {
            let newSection = ip.section - 1
            if newSection < 0 {
                return // start of table
            }
            tableView.selectRow(at: IndexPath(row: 0, section: newSection), animated: true, scrollPosition: .middle)
        } else if numberOfSections(in: tableView) > 0 {
            tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: true, scrollPosition: .top)
        }
    }

    @objc private func keyMoveToNextSection() {
        if let ip = tableView.indexPathForSelectedRow {
            let newSection = ip.section + 1
            if newSection >= tableView.numberOfSections {
                return // end of table
            }
            tableView.selectRow(at: IndexPath(row: 0, section: newSection), animated: true, scrollPosition: .middle)
        } else if numberOfSections(in: tableView) > 0 {
            tableView.selectRow(at: IndexPath(row: 0, section: 0), animated: true, scrollPosition: .top)
        }
    }

    @objc private func moveToNextTab() {
        let items = SectionListViewController.tabBarSets

        if items.count > 1, let i = currentTabBar, let ind = items.firstIndex(of: i) {
            let nextIndex = (ind < items.count - 1) ? ind + 1 : 0
            currentTabBar = SectionListViewController.tabBarSets[nextIndex]
        }
    }

    @objc private func moveToPreviousTab() {
        let items = SectionListViewController.tabBarSets

        if items.count > 1, let i = currentTabBar, let ind = items.firstIndex(of: i) {
            let nextIndex = (ind > 0) ? ind - 1 : items.count - 1
            currentTabBar = SectionListViewController.tabBarSets[nextIndex]
        }
    }

    private func selectInCurrentTab(item: ListableItem, overrideUrl: String?, andOpen: Bool) {
        guard let ip = fetchedResultsController?.indexPath(forObject: item) else { return }

        tableView.selectRow(at: ip, animated: false, scrollPosition: .middle)
        if andOpen {
            Task { @MainActor in
                if let overrideUrl, let url = URL(string: overrideUrl) {
                    showDetail(url: url, objectId: item.objectID)
                } else if let u = item.webUrl, let url = URL(string: u) {
                    showDetail(url: url, objectId: item.objectID)
                }
            }
        } else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
                tableView.deselectRow(at: ip, animated: true)
            }
        }
    }

    private func updateSearch() {
        let r = Range(uncheckedBounds: (lower: 0, upper: fetchedResultsController?.sections?.count ?? 0))
        let currentIndexes = IndexSet(integersIn: r)

        let settings = Settings.cache
        updateQuery(newFetchRequest: itemFetchRequest(settings: settings))

        let r2 = Range(uncheckedBounds: (lower: 0, upper: fetchedResultsController?.sections?.count ?? 0))
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
        if currentTabBar == nil {
            return
        }

        if fetchedResultsController == nil || fetchedResultsController?.fetchRequest.entityName != newFetchRequest.entityName {
            let c = NSFetchedResultsController(fetchRequest: newFetchRequest, managedObjectContext: DataManager.main, sectionNameKeyPath: "sectionName", cacheName: nil)
            fetchedResultsController = c
            try! c.performFetch()
            c.delegate = self

        } else if let fetchedResultsController {
            let fr = fetchedResultsController.fetchRequest
            fr.relationshipKeyPathsForPrefetching = newFetchRequest.relationshipKeyPathsForPrefetching
            fr.sortDescriptors = newFetchRequest.sortDescriptors
            fr.predicate = newFetchRequest.predicate
            try! fetchedResultsController.performFetch()
        }
    }

    private func newTabBarSets() {
        var newSets = [TabInfo]()

        for groupLabel in Repo.allGroupLabels(in: DataManager.main) {
            let c = GroupingCriterion.group(groupLabel)
            let s = TabInfo.items(for: c)
            newSets.append(contentsOf: s)
        }

        if Settings.showSeparateApiServersInMenu {
            for a in ApiServer.allApiServers(in: DataManager.main) where a.goodToGo {
                let c = GroupingCriterion.server(a.objectID)
                let s = TabInfo.items(for: c)
                newSets.append(contentsOf: s)
            }
        } else {
            let s = TabInfo.items(for: nil)
            newSets.append(contentsOf: s)
        }

        SectionListViewController.tabBarSets = newSets
    }

    private func updateSectionInfo() {
        let settings = Settings.cache
        let newFetchRequest = itemFetchRequest(settings: settings)
        if fetchedResultsController == nil {
            updateQuery(newFetchRequest: newFetchRequest)
            tableView.reloadData()
        } else {
            let latestFetchRequest = fetchedResultsController?.fetchRequest
            let newCount = SectionListViewController.tabBarSets.count
            if newCount != lastTabCount || latestFetchRequest != newFetchRequest {
                updateQuery(newFetchRequest: newFetchRequest)
                tableView.reloadData()
            }
        }

        lastTabCount = SectionListViewController.tabBarSets.count

        updateTitle()
        updateFooter()
    }

    private func selectTab(for item: ListableItem, overrideUrl: String?, andOpen: Bool) {
        var tabItem: TabInfo?
        for d in SectionListViewController.tabBarSets {
            if d.viewCriterion == nil || d.viewCriterion?.isRelated(to: item) ?? false {
                tabItem = d
                break
            }
        }
        Task {
            if let tabItem {
                currentTabBar = tabItem
                try? await Task.sleep(for: .seconds(0.3))
            }
            selectInCurrentTab(item: item, overrideUrl: overrideUrl, andOpen: andOpen)
        }
    }

    private func highlightItemWithUriPath(uriPath: String) {
        guard let itemId = DataManager.id(for: uriPath),
              let item = try? DataManager.main.existingObject(with: itemId) as? ListableItem else {
            return
        }
        selectTab(for: item, overrideUrl: nil, andOpen: false)
    }

    private func openCommentWithId(cId: String) {
        guard let itemId = DataManager.id(for: cId),
              let comment = try? DataManager.main.existingObject(with: itemId) as? PRComment,
              let item = comment.parent else {
            return
        }
        selectTab(for: item, overrideUrl: nil, andOpen: true)
    }

    private func notificationSelected(for item: ListableItem, urlToOpen: String?) {
        if let sc = navigationItem.searchController, sc.isActive {
            sc.searchBar.text = nil
            sc.isActive = false
        }
        Task {
            try? await Task.sleep(for: .seconds(0.1))
            selectTab(for: item, overrideUrl: urlToOpen, andOpen: true)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func numberOfSections(in _: UITableView) -> Int {
        fetchedResultsController?.sections?.count ?? 0
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        fetchedResultsController?.sections?[section].numberOfObjects ?? 0
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        if let o = fetchedResultsController?.object(at: indexPath) {
            configureCell(cell: cell, withObject: o)
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if !isFirstResponder {
            becomeFirstResponder()
        }

        if let p = fetchedResultsController?.object(at: indexPath), let u = p.urlForOpening(settings: Settings.cache), let url = URL(string: u) {
            showDetail(url: url, objectId: p.objectID)
        }

        tableView.deselectRow(at: indexPath, animated: true)
    }

    private func showDetail(url: URL, objectId: NSManagedObjectID) {
        if let item = try? DataManager.main.existingObject(with: objectId) as? ListableItem {
            item.catchUpWithComments(settings: Settings.cache)
        }
        UIApplication.shared.open(url, options: [:])
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let v = tableView.dequeueReusableHeaderFooterView(withIdentifier: "SectionHeaderView") as! SectionHeaderView
        let name = (fetchedResultsController?.sections?[section].name).orEmpty
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

    override func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
        40
    }

    private func createShortcutActions(for item: ListableItem, settings: Settings.Cache) -> UIMenu? {
        var children = item.contextActions(settings: settings).map { action -> UIMenuElement in
            switch action {
            case .copy:
                return UIAction(title: action.title, image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = item.webUrl
                }

            case .markUnread:
                return UIAction(title: action.title, image: UIImage(systemName: "envelope.badge")) { _ in
                    self.markItemAsUnRead(itemUri: item.objectID.uriRepresentation().absoluteString)
                }

            case .markRead:
                return UIAction(title: action.title, image: UIImage(systemName: "checkmark")) { _ in
                    self.markItemAsRead(itemUri: item.objectID.uriRepresentation().absoluteString)
                }

            case .mute:
                return UIAction(title: action.title, image: UIImage(systemName: "speaker.slash")) { _ in
                    item.setMute(to: true, settings: settings)
                }

            case .unmute:
                return UIAction(title: action.title, image: UIImage(systemName: "speaker.2")) { _ in
                    item.setMute(to: false, settings: settings)
                }

            case .openRepo:
                return UIAction(title: action.title, image: UIImage(systemName: "list.dash")) { _ in
                    if let urlString = item.repo.webUrl, let url = URL(string: urlString) {
                        UIApplication.shared.open(url, options: [:])
                    }
                }

            case .remove:
                return UIAction(title: action.title, image: UIImage(systemName: "bin.xmark"), attributes: .destructive) { _ in
                    DataManager.main.delete(item)
                }

            case let .snooze(presets):
                var presetItems = presets.map { preset -> UIAction in
                    UIAction(title: preset.listDescription) { _ in
                        item.snooze(using: preset, settings: settings)
                    }
                }
                presetItems.append(UIAction(title: "Configure...", image: UIImage(systemName: "gear"), identifier: nil) { _ in
                    NotificationCenter.default.post(name: .showPreferences, object: 3)
                })
                return UIMenu(title: action.title, image: UIImage(systemName: "moon.zzz"), children: presetItems)

            case .wake:
                return UIAction(title: action.title, image: UIImage(systemName: "sun.max")) { _ in
                    item.wakeUp(settings: settings)
                }
            }
        }

        var title = item.contextMenuTitle

        if let subtitle = item.contextMenuSubtitle {
            title += " | " + subtitle
            children.append(UIAction(title: "Copy Branch Name", image: UIImage(systemName: "arrow.branch")) { _ in
                UIPasteboard.general.string = subtitle
            })
        }

        return UIMenu(title: title, image: nil, identifier: nil, options: [], children: children)
    }

    override func tableView(_: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = fetchedResultsController?.object(at: indexPath) else { return nil }

        return UIContextMenuConfiguration(identifier: item.objectID, previewProvider: nil) { [weak self] _ in
            self?.createShortcutActions(for: item, settings: Settings.cache)
        }
    }

    override func tableView(_: UITableView, willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration, animator: UIContextMenuInteractionCommitAnimating) {
        animator.preferredCommitStyle = .dismiss
        animator.addCompletion {
            if let id = configuration.identifier as? NSManagedObjectID, let item = try? DataManager.main.existingObject(with: id) as? ListableItem, let urlString = item.urlForOpening(settings: Settings.cache), let url = URL(string: urlString) {
                item.catchUpWithComments(settings: Settings.cache)
                UIApplication.shared.open(url, options: [:])
            }
        }
    }

    private func markItemAsRead(itemUri: String?) {
        if let
            i = itemUri,
            let oid = DataManager.id(for: i),
            let o = try? DataManager.main.existingObject(with: oid) as? ListableItem {
            o.catchUpWithComments(settings: Settings.cache)
        }
    }

    private func markItemAsUnRead(itemUri: String?) {
        if let
            i = itemUri,
            let oid = DataManager.id(for: i),
            let o = try? DataManager.main.existingObject(with: oid) as? ListableItem {
            o.latestReadCommentDate = .distantPast
            o.postProcess(settings: Settings.cache)
        }
    }

    private func showSnoozeMenuFor(i: ListableItem) {
        let snoozePresets = SnoozePreset.allSnoozePresets(in: DataManager.main)
        let hasPresets = !snoozePresets.isEmpty
        let a = UIAlertController(title: hasPresets ? "Snooze" : nil,
                                  message: hasPresets ? i.title.orEmpty : "You do not currently have any snoozing presets configured. Please add some in the relevant preferences tab.",
                                  preferredStyle: .alert)
        for preset in snoozePresets {
            a.addAction(UIAlertAction(title: preset.listDescription, style: .default) { _ in
                i.snooze(using: preset, settings: Settings.cache)
            })
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
    }

    private func itemFetchRequest(settings: Settings.Cache) -> NSFetchRequest<ListableItem> {
        let type: ListableItem.Type = viewingPrs ? PullRequest.self : Issue.self
        let text = navigationItem.searchController?.searchBar.text
        return ListableItem.requestForItems(of: type, withFilter: text, sectionIndex: -1, criterion: currentTabBar?.viewCriterion, settings: settings, moc: DataManager.main)
    }

    func controllerWillChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        animatedUpdates = UIApplication.shared.applicationState != .background
        sectionsChanged = false
        if animatedUpdates {
            tableView.beginUpdates()
        }
    }

    func controller(_: NSFetchedResultsController<NSFetchRequestResult>, didChange _: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        guard animatedUpdates else { return }

        switch type {
        case .insert:
            tableView.insertSections(IndexSet(integer: sectionIndex), with: .fade)
        case .delete:
            tableView.deleteSections(IndexSet(integer: sectionIndex), with: .fade)
        case .move, .update:
            break
        @unknown default:
            break
        }

        sectionsChanged = true
    }

    func controller(_: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        guard animatedUpdates else { return }

        switch type {
        case .insert:
            if let newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: .fade)
            }
        case .delete:
            if let indexPath {
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
        case .update:
            if let indexPath, let object = anObject as? ListableItem, let cell = tableView.cellForRow(at: indexPath) {
                configureCell(cell: cell, withObject: object)
            }
        case .move:
            if let indexPath, let newIndexPath {
                if sectionsChanged {
                    tableView.deleteRows(at: [indexPath], with: .fade)
                    tableView.insertRows(at: [newIndexPath], with: .fade)
                } else {
                    tableView.moveRow(at: indexPath, to: newIndexPath)
                }
            }
        @unknown default:
            break
        }
    }

    func controllerDidChangeContent(_: NSFetchedResultsController<NSFetchRequestResult>) {
        if animatedUpdates {
            tableView.endUpdates()
        } else {
            tableView.reloadData()
        }
    }

    private func configureCell(cell: UITableViewCell, withObject: ListableItem) {
        guard let c = cell as? PRCell else { return }
        if let o = withObject.asPr {
            c.setPullRequest(pullRequest: o, settings: Settings.cache)
        } else if let o = withObject.asIssue {
            c.setIssue(issue: o, settings: Settings.cache)
        }
    }

    private func updateStatus(becauseOfChanges: Bool, updateItems: Bool = false) {
        guard isViewLoaded else {
            return
        }

        if becauseOfChanges || updateItems {
            if becauseOfChanges {
                watchManager.updateContext()
            }
            newTabBarSets()
            updateSectionInfo()
        }

        updateFooter()
        refreshUpdated()
        updateTitle()
    }

    private func updateFooter() {
        let count = fetchedResultsController?.fetchedObjects?.count ?? 0
        if count > 0 {
            tableView.tableFooterView = nil
            return
        }

        let reasonForEmpty: NSAttributedString

        if currentTabBar == nil {
            reasonForEmpty = NSAttributedString(string: "← Select a section")

        } else {
            let searchBarText = navigationItem.searchController?.searchBar.text
            if viewingPrs {
                reasonForEmpty = PullRequest.reasonForEmpty(with: searchBarText, criterion: currentTabBar?.viewCriterion)
            } else {
                reasonForEmpty = Issue.reasonForEmpty(with: searchBarText, criterion: currentTabBar?.viewCriterion)
            }
        }
        tableView.tableFooterView = EmptyView(message: reasonForEmpty)
    }

    private func unreadCommentCount(count: Int) -> String {
        count == 0 ? "" : count == 1 ? " (1 update)" : " (\(count) updates)"
    }

    ///////////////////////////// filtering

    override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        becomeFirstResponder()
        if scrollView.contentOffset.y <= 0 {
            let refreshing = API.isRefreshing
            if !refreshing {
                let last = API.lastSuccessfulSyncAt
                refreshControl?.attributedTitle = NSAttributedString(string: last, attributes: nil)
            }
        }
    }

    func updateSearchResults(for _: UISearchController) {
        searchTimer.push()
    }

    private func safeScrollToTop() async {
        tableView.contentOffset = tableView.contentOffset // halt any inertial scrolling
        if tableView.numberOfSections > 0 {
            tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: false)
        }
        try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
    }

    @objc func focusFilter(terms: String?) {
        tableView.contentOffset = CGPoint(x: 0, y: -tableView.contentInset.top)
        let searchBar = navigationItem.searchController?.searchBar
        searchBar?.becomeFirstResponder()
        searchBar?.text = terms
        searchTimer.push()
    }

    private func resetView() {
        Task {
            await safeScrollToTop()
            updateQuery(newFetchRequest: itemFetchRequest(settings: Settings.cache))
            updateStatus(becauseOfChanges: true)
            tableView.reloadData()
        }
    }
}
