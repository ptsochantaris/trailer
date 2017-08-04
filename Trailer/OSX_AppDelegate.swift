
@NSApplicationMain
final class OSX_AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSUserNotificationCenterDelegate, NSOpenSavePanelDelegate {

	// Globals
	var refreshTimer: Timer?
	var openingWindow = false
	var isManuallyScrolling = false
	var ignoreNextFocusLoss = false
	var scrollBarWidth: CGFloat = 0.0

	private var systemSleeping = false
	private var globalKeyMonitor: Any?
	private var keyDownMonitor: Any?
	private var mouseIgnoreTimer: PopTimer!

	func setupWindows() {

		darkMode = currentSystemDarkMode

		for d in menuBarSets {
			d.throwAway()
		}
		menuBarSets.removeAll()

		var newSets = [MenuBarSet]()
		for groupLabel in Repo.allGroupLabels(in: DataManager.main) {
			let c = GroupingCriterion(repoGroup: groupLabel)
			let s = MenuBarSet(viewCriterion: c, delegate: self)
			s.setTimers()
			newSets.append(s)
		}

		if Settings.showSeparateApiServersInMenu {
			for a in ApiServer.allApiServers(in: DataManager.main) {
				if a.goodToGo {
					let c = GroupingCriterion(apiServerId: a.objectID)
					let s = MenuBarSet(viewCriterion: c, delegate: self)
					s.setTimers()
					newSets.append(s)
				}
			}
		}

		if newSets.count == 0 || (!Settings.showSeparateApiServersInMenu && Repo.anyVisibleRepos(in: DataManager.main, excludeGrouped: true)) {
			let s = MenuBarSet(viewCriterion: nil, delegate: self)
			s.setTimers()
			newSets.append(s)
		}

		menuBarSets.append(contentsOf: newSets.reversed())

		updateScrollBarWidth() // also updates menu

		for d in menuBarSets {
			d.prMenu.scrollToTop()
			d.issuesMenu.scrollToTop()

			d.prMenu.updateVibrancy()
			d.issuesMenu.updateVibrancy()
		}
	}

	func applicationWillFinishLaunching(_ notification: Notification) {
		app = self
		bootUp()
		NSTextField.setCellClass(CenterTextFieldCell.self)
	}

	func applicationDidFinishLaunching(_ notification: Notification) {

		if DataManager.main.persistentStoreCoordinator == nil {
			databaseErrorOnStartup()
			return
		}

		DistributedNotificationCenter.default().addObserver(self, selector: #selector(updateDarkModeDelayed), name: AppleInterfaceThemeChangedNotification, object: nil)

		DataManager.postProcessAllItems()

		mouseIgnoreTimer = PopTimer(timeInterval: 0.4) {
			app.isManuallyScrolling = false
		}

		updateDarkMode() // also sets up windows

		API.updateLimitsFromServer()

		let nc = NSUserNotificationCenter.default
		nc.delegate = self
		if let launchNotification = notification.userInfo?[NSApplicationLaunchUserNotificationKey] as? NSUserNotification {
			delay(0.5, self) { S in
				S.userNotificationCenter(nc, didActivate: launchNotification)
			}
		}

		if ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
			atNextEvent(self) { S in
				S.startRefresh()
			}
		} else if ApiServer.countApiServers(in: DataManager.main) == 1, let a = ApiServer.allApiServers(in: DataManager.main).first, a.authToken == nil || a.authToken!.isEmpty {
			startupAssistant()
		} else {
			preferencesSelected()
		}

		let n = NotificationCenter.default
		n.addObserver(self, selector: #selector(updateScrollBarWidth), name: .NSPreferredScrollerStyleDidChange, object: nil)

		addHotKeySupport()

		let s = SUUpdater.shared()
		setUpdateCheckParameters()
		if !(s?.updateInProgress)! && Settings.checkForUpdatesAutomatically {
			s?.checkForUpdatesInBackground()
		}

		let wn = NSWorkspace.shared().notificationCenter
		wn.addObserver(self, selector: #selector(systemWillSleep), name: .NSWorkspaceWillSleep, object: nil)
		wn.addObserver(self, selector: #selector(systemDidWake), name: .NSWorkspaceDidWake, object: nil)
	}

	func systemWillSleep() {
		systemSleeping = true
		DLog("System is going to sleep")
	}

	func systemDidWake() {
		DLog("System woke up")
		systemSleeping = false
		delay(1, self) { S in
			S.updateDarkMode()
			S.startRefreshIfItIsDue()
		}
	}

	func setUpdateCheckParameters() {
		if let s = SUUpdater.shared() {
			let autoCheck = Settings.checkForUpdatesAutomatically
			s.automaticallyChecksForUpdates = autoCheck
			if autoCheck {
				s.updateCheckInterval = TimeInterval(3600)*TimeInterval(Settings.checkForUpdatesInterval)
			}
			DLog("Check for updates set to %@, every %@ seconds", autoCheck, s.updateCheckInterval)
		}
	}

	func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
		return false
	}

	func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {

		if let userInfo = notification.userInfo {

			func saveAndRefresh(_ i: ListableItem) {
				DataManager.saveDB()
				updateRelatedMenus(for: i)
			}

			switch notification.activationType {
			case .additionalActionClicked:
				if notification.additionalActivationAction?.identifier == "mute" {
					if let (_,i) = ListableItem.relatedItems(from: userInfo) {
						i.setMute(to: true)
						saveAndRefresh(i)
					}
					break
				} else if notification.additionalActivationAction?.identifier == "read" {
					if let (_,i) = ListableItem.relatedItems(from: userInfo) {
						i.catchUpWithComments()
						saveAndRefresh(i)
					}
					break
				}
			case .actionButtonClicked, .contentsClicked:
				var urlToOpen = userInfo[NOTIFICATION_URL_KEY] as? String
				if urlToOpen == nil {
					if let (c,i) = ListableItem.relatedItems(from: userInfo) {
						urlToOpen = c?.webUrl ?? i.webUrl
						i.catchUpWithComments()
						saveAndRefresh(i)
					}
				}
				if let up = urlToOpen, let u = URL(string: up) {
					NSWorkspace.shared().open(u)
				}
			default: break
			}
		}
		NSUserNotificationCenter.default.removeDeliveredNotification(notification)
	}

	func postNotification(type: NotificationType, for item: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = NSUserNotification()

		func addPotentialExtraActions() {
			notification.additionalActions = [
				NSUserNotificationAction(identifier: "mute", title: "Mute this item"),
				NSUserNotificationAction(identifier: "read", title: "Mark this item as read")
			]
		}

		switch type {
		case .newMention:
			guard let c = item as? PRComment, let parent = c.parent, !parent.shouldSkipNotifications else { return }
			notification.title = "@\(S(c.userName)) Mentioned You:"
			notification.subtitle = c.notificationSubtitle
			notification.informativeText = c.body
			addPotentialExtraActions()
			
		case .newComment:
			guard let c = item as? PRComment, let parent = c.parent, !parent.shouldSkipNotifications else { return }
			notification.title = "@\(S(c.userName)) Commented:"
			notification.subtitle = c.notificationSubtitle
			notification.informativeText = c.body
			addPotentialExtraActions()

		case .newPr:
			guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
			notification.title = "New PR"
			notification.subtitle = p.repo.fullName
			notification.informativeText = p.title
			addPotentialExtraActions()

		case .prReopened:
			guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
			notification.title = "Re-Opened PR"
			notification.subtitle = p.repo.fullName
			notification.informativeText = p.title
			addPotentialExtraActions()

		case .prMerged:
			guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
			notification.title = "PR Merged!"
			notification.subtitle = p.repo.fullName
			notification.informativeText = p.title
			addPotentialExtraActions()

		case .prClosed:
			guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
			notification.title = "PR Closed"
			notification.subtitle = p.repo.fullName
			notification.informativeText = p.title
			addPotentialExtraActions()

		case .newRepoSubscribed:
			notification.title = "New Repository Subscribed"
			notification.subtitle = (item as! Repo).fullName

		case .newRepoAnnouncement:
			notification.title = "New Repository"
			notification.subtitle = (item as! Repo).fullName

		case .newPrAssigned:
			guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
			notification.title = "PR Assigned"
			notification.subtitle = p.repo.fullName
			notification.informativeText = p.title
			addPotentialExtraActions()

		case .newStatus:
			guard let s = item as? PRStatus, !s.pullRequest.shouldSkipNotifications else { return }
			notification.title = "PR Status Update"
			notification.subtitle = s.descriptionText
			notification.informativeText = s.pullRequest.title
			addPotentialExtraActions()

		case .newIssue:
			guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
			notification.title = "New Issue"
			notification.subtitle = i.repo.fullName
			notification.informativeText = i.title
			addPotentialExtraActions()

		case .issueReopened:
			guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
			notification.title = "Re-Opened Issue"
			notification.subtitle = i.repo.fullName
			notification.informativeText = i.title
			addPotentialExtraActions()

		case .issueClosed:
			guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
			notification.title = "Issue Closed"
			notification.subtitle = i.repo.fullName
			notification.informativeText = i.title
			addPotentialExtraActions()

		case .newIssueAssigned:
			guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
			notification.title = "Issue Assigned"
			notification.subtitle = i.repo.fullName
			notification.informativeText = i.title
			addPotentialExtraActions()

		case .changesApproved:
			guard let r = item as? Review else { return }
			let p = r.pullRequest
			if p.shouldSkipNotifications { return }
			notification.title = "@\(S(r.username)) Approved Changes"
			notification.subtitle = p.title
			notification.informativeText = r.body
			notification.contentImage = #imageLiteral(resourceName: "approvesChangesIcon")
			addPotentialExtraActions()

		case .changesRequested:
			guard let r = item as? Review else { return }
			let p = r.pullRequest
			if p.shouldSkipNotifications { return }
			notification.title = "@\(S(r.username)) Requests Changes"
			notification.subtitle = p.title
			notification.informativeText = r.body
			notification.contentImage = #imageLiteral(resourceName: "requestsChangesIcon")
			addPotentialExtraActions()

		case .changesDismissed:
			guard let r = item as? Review else { return }
			let p = r.pullRequest
			if p.shouldSkipNotifications { return }
			notification.title = "@\(S(r.username)) Dismissed A Review"
			notification.subtitle = p.title
			notification.informativeText = r.body
			addPotentialExtraActions()

		case .assignedForReview:
			guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
			notification.title = "PR Assigned For Review"
			notification.subtitle = p.repo.fullName
			notification.informativeText = p.title
			addPotentialExtraActions()

		case .newReaction:
			guard let r = item as? Reaction else { return }
			notification.title = r.displaySymbol
			notification.subtitle = "@\(S(r.userName))"
			if let c = r.comment, let p = c.pullRequest, !p.shouldSkipNotifications {
				notification.informativeText = c.body
				addPotentialExtraActions()
			} else if let p = r.pullRequest, !p.shouldSkipNotifications {
				notification.informativeText = p.title
				addPotentialExtraActions()
			} else if let i = r.issue, !i.shouldSkipNotifications {
				notification.informativeText = i.title
				addPotentialExtraActions()
			} else {
				return
			}
		}

		let t = S(notification.title)
		let s = S(notification.subtitle)
		let i = S(notification.informativeText)
		notification.identifier = "\(t) - \(s) - \(i)"

		notification.userInfo = DataManager.info(for: item)

		if let c = item as? PRComment, let url = c.avatarUrl, !Settings.hideAvatars {
			API.haveCachedAvatar(from: url) { image, _ in
				notification.contentImage = image
				NSUserNotificationCenter.default.deliver(notification)
			}
		} else {
			NSUserNotificationCenter.default.deliver(notification)
		}
	}

	func selected(_ item: ListableItem, alternativeSelect: Bool, window: NSWindow?) {

		guard let w = window as? MenuWindow, let menuBarSet = menuBarSet(for: w) else { return }

		ignoreNextFocusLoss = alternativeSelect

		let urlToOpen = item.urlForOpening
		item.catchUpWithComments()
		updateRelatedMenus(for: item)

		let window = item is PullRequest ? menuBarSet.prMenu : menuBarSet.issuesMenu
		let reSelectIndex = alternativeSelect ? window.table.selectedRow : -1
		window.filter.becomeFirstResponder()

		if reSelectIndex > -1 && reSelectIndex < window.table.numberOfRows {
			window.table.selectRowIndexes(IndexSet(integer: reSelectIndex), byExtendingSelection: false)
		}

		if let u = urlToOpen {
			NSWorkspace.shared().open(URL(string: u)!)
		}
	}

	func show(menu: MenuWindow) {
		if !menu.isVisible {

			if let w = visibleWindow {
				w.closeMenu()
			}

			menu.size(andShow: true)
		}
	}

	func removeSelected(on header: String) {

		guard let inMenu = visibleWindow, let menuBarSet = menuBarSet(for: inMenu) else { return }

		if inMenu === menuBarSet.prMenu {
			if header == Section.merged.prMenuName {
				if Settings.dontAskBeforeWipingMerged {
					removeAllMergedRequests(under: menuBarSet)
				} else {
					let mergedRequests = PullRequest.allMerged(in: DataManager.main, criterion: menuBarSet.viewCriterion)

					let alert = NSAlert()
					alert.messageText = "Clear \(mergedRequests.count) merged PRs?"
					alert.informativeText = "This will clear \(mergedRequests.count) merged PRs from this list.  This action cannot be undone, are you sure?"
					alert.addButton(withTitle: "No")
					alert.addButton(withTitle: "Yes")
					alert.showsSuppressionButton = true

					if alert.runModal() == NSAlertSecondButtonReturn {
						removeAllMergedRequests(under: menuBarSet)
						if alert.suppressionButton!.state == NSOnState {
							Settings.dontAskBeforeWipingMerged = true
						}
					}
				}
			} else if header == Section.closed.prMenuName {
				if Settings.dontAskBeforeWipingClosed {
					removeAllClosedRequests(under: menuBarSet)
				} else {
					let closedRequests = PullRequest.allClosed(in: DataManager.main, criterion: menuBarSet.viewCriterion)

					let alert = NSAlert()
					alert.messageText = "Clear \(closedRequests.count) closed PRs?"
					alert.informativeText = "This will remove \(closedRequests.count) closed PRs from this list.  This action cannot be undone, are you sure?"
					alert.addButton(withTitle: "No")
					alert.addButton(withTitle: "Yes")
					alert.showsSuppressionButton = true

					if alert.runModal() == NSAlertSecondButtonReturn {
						removeAllClosedRequests(under: menuBarSet)
						if alert.suppressionButton!.state == NSOnState {
							Settings.dontAskBeforeWipingClosed = true
						}
					}
				}
			}
			if !menuBarSet.prMenu.isVisible {
				show(menu: menuBarSet.prMenu)
			}
		} else if inMenu === menuBarSet.issuesMenu {
			if header == Section.closed.issuesMenuName {
				if Settings.dontAskBeforeWipingClosed {
					removeAllClosedIssues(under: menuBarSet)
				} else {
					let closedIssues = Issue.allClosed(in: DataManager.main, criterion: menuBarSet.viewCriterion)

					let alert = NSAlert()
					alert.messageText = "Clear \(closedIssues.count) closed issues?"
					alert.informativeText = "This will remove \(closedIssues.count) closed issues from this list.  This action cannot be undone, are you sure?"
					alert.addButton(withTitle: "No")
					alert.addButton(withTitle: "Yes")
					alert.showsSuppressionButton = true

					if alert.runModal() == NSAlertSecondButtonReturn {
						removeAllClosedIssues(under: menuBarSet)
						if alert.suppressionButton!.state == NSOnState {
							Settings.dontAskBeforeWipingClosed = true
						}
					}
				}
			}
			if !menuBarSet.issuesMenu.isVisible {
				show(menu: menuBarSet.issuesMenu)
			}
		}
	}

	private func removeAllMergedRequests(under menuBarSet: MenuBarSet) {
		for r in PullRequest.allMerged(in: DataManager.main, criterion: menuBarSet.viewCriterion) {
			DataManager.main.delete(r)
		}
		DataManager.saveDB()
		menuBarSet.updatePrMenu()
	}

	private func removeAllClosedRequests(under menuBarSet: MenuBarSet) {
		for r in PullRequest.allClosed(in: DataManager.main, criterion: menuBarSet.viewCriterion) {
			DataManager.main.delete(r)
		}
		DataManager.saveDB()
		menuBarSet.updatePrMenu()
	}

	private func removeAllClosedIssues(under menuBarSet: MenuBarSet) {
		for i in Issue.allClosed(in: DataManager.main, criterion: menuBarSet.viewCriterion) {
			DataManager.main.delete(i)
		}
		DataManager.saveDB()
		menuBarSet.updateIssuesMenu()
	}

	func unPinSelected(for item: ListableItem) {
		let menus = relatedMenus(for: item)
		DataManager.main.delete(item)
		DataManager.saveDB()
		if item is PullRequest {
			menus.forEach { $0.updatePrMenu() }
		} else if item is Issue {
			menus.forEach { $0.updateIssuesMenu() }
		}
	}

	override func controlTextDidChange(_ n: Notification) {
		if let obj = n.object as? NSSearchField {

			guard let w = obj.window as? MenuWindow, let menuBarSet = menuBarSet(for: w) else { return }

			if obj === menuBarSet.prMenu.filter {
				menuBarSet.prFilterTimer.push()
			} else if obj === menuBarSet.issuesMenu.filter {
				menuBarSet.issuesFilterTimer.push()
			}
		}
	}

	func markAllReadSelected(from window: MenuWindow) {

		guard let menuBarSet = menuBarSet(for: window) else { return }

		let type: ListableItem.Type = (window === menuBarSet.prMenu) ? PullRequest.self : Issue.self
		let f = ListableItem.requestForItems(of: type, withFilter: window.filter.stringValue, sectionIndex: -1, criterion: menuBarSet.viewCriterion)
		for r in try! DataManager.main.fetch(f) {
			r.catchUpWithComments()
		}
		updateAllMenus()
	}

	func preferencesSelected() {
		refreshTimer = nil
		showPreferencesWindow(andSelect: nil)
	}

	func application(_ sender: NSApplication, openFile filename: String) -> Bool {
		let url = URL(fileURLWithPath: filename)
		let ext = url.pathExtension
		if ext == "trailerSettings" {
			DLog("Will open %@", url.absoluteString)
			tryLoadSettings(from: url, skipConfirm: Settings.dontConfirmSettingsImport)
			return true
		}
		return false
	}

	@discardableResult
	func tryLoadSettings(from url: URL, skipConfirm: Bool) -> Bool {
		if appIsRefreshing {
			let alert = NSAlert()
			alert.messageText = "Trailer is currently refreshing data, please wait until it's done and try importing your settings again"
			alert.addButton(withTitle: "OK")
			alert.runModal()
			return false

		} else if !skipConfirm {
			let alert = NSAlert()
			alert.messageText = "Import settings from this file?"
			alert.informativeText = "This will overwrite all your current Trailer settings, are you sure?"
			alert.addButton(withTitle: "No")
			alert.addButton(withTitle: "Yes")
			alert.showsSuppressionButton = true
			if alert.runModal() == NSAlertSecondButtonReturn {
				if alert.suppressionButton!.state == NSOnState {
					Settings.dontConfirmSettingsImport = true
				}
			} else {
				return false
			}
		}

		if !Settings.readFromURL(url) {
			let alert = NSAlert()
			alert.messageText = "The selected settings file could not be imported due to an error"
			alert.addButton(withTitle: "OK")
			alert.runModal()
			return false
		}
		DataManager.postProcessAllItems()
		DataManager.saveDB()
		preferencesWindow?.reloadSettings()
		setupWindows()
		preferencesDirty = true
		startRefresh()

		return true
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplicationTerminateReply {
		DataManager.saveDB()
		return .terminateNow
	}

	func windowDidBecomeKey(_ notification: Notification) {
		if let window = notification.object as? MenuWindow {
			if ignoreNextFocusLoss {
				ignoreNextFocusLoss = false
			} else {
				window.scrollToTop()
				window.table.deselectAll(nil)
			}
		}
	}

	func windowDidResignKey(_ notification: Notification) {
		if ignoreNextFocusLoss {
			NSApp.activate(ignoringOtherApps: true)
		} else if !openingWindow {
			if let w = notification.object as? MenuWindow {
				w.closeMenu()
			}
		}
	}
	
	func startRefreshIfItIsDue() {

		if let l = Settings.lastSuccessfulRefresh {
			let howLongAgo = Date().timeIntervalSince(l)
			if fabs(howLongAgo) > TimeInterval(Settings.refreshPeriod) {
				startRefresh()
			} else {
				let howLongUntilNextSync = TimeInterval(Settings.refreshPeriod) - howLongAgo
				DLog("No need to refresh yet, will refresh in %@", howLongUntilNextSync)
				refreshTimer = Timer(repeats: false, interval: howLongUntilNextSync) { [weak self] in
					self?.refreshTimerDone()
				}
			}
		}
		else
		{
			startRefresh()
		}
	}

	private func checkApiUsage() {
		for apiServer in ApiServer.allApiServers(in: DataManager.main) {
			if apiServer.goodToGo && apiServer.hasApiLimit, let resetDate = apiServer.resetDate {
				if apiServer.shouldReportOverTheApiLimit {
					let apiLabel = S(apiServer.label)
					let resetDateString = itemDateFormatter.string(from: resetDate)

					let alert = NSAlert()
					alert.messageText = "Your API request usage for '\(apiLabel)' is over the limit!"
					alert.informativeText = "Your request cannot be completed until your hourly API allowance is reset \(resetDateString).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from 'Servers' preferences pane at any time."
					alert.addButton(withTitle: "OK")
					alert.runModal()
				} else if apiServer.shouldReportCloseToApiLimit {
					let apiLabel = S(apiServer.label)
					let resetDateString = itemDateFormatter.string(from: resetDate)

					let alert = NSAlert()
					alert.messageText = "Your API request usage for '\(apiLabel)' is close to full"
					alert.informativeText = "Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by GitHub \(resetDateString).\n\nYou can check your API usage from the 'Servers' preferences pane at any time."
					alert.addButton(withTitle: "OK")
					alert.runModal()
				}
			}
		}
	}

	func prepareForRefresh() {
		refreshTimer = nil

		DataManager.postMigrationTasks()

		appIsRefreshing = true
		
		preferencesWindow?.updateActivity()

		for d in menuBarSets {
			d.prepareForRefresh()
		}

		NotificationQueue.clear()

		DLog("Starting refresh")
	}

	func completeRefresh() {
		appIsRefreshing = false
		preferencesDirty = false
		preferencesWindow?.updateActivity()
		DataManager.saveDB()
		preferencesWindow?.projectsTable.reloadData()
		checkApiUsage()
		DataManager.sendNotificationsIndexAndSave()
		DLog("Refresh done")
		updateAllMenus()
	}

	func updateRelatedMenus(for i: ListableItem) {
		let menus = relatedMenus(for: i)
		if i is PullRequest {
			menus.forEach { $0.updatePrMenu() }
		} else if i is Issue {
			menus.forEach { $0.updateIssuesMenu() }
		}
	}

	private func relatedMenus(for i: ListableItem) -> [MenuBarSet] {
		return menuBarSets.flatMap{ ($0.viewCriterion?.isRelated(to: i) ?? true) ? $0 : nil }
	}

	func updateAllMenus() {
		var visibleMenuCount = 0
		for d in menuBarSets {
			d.forceVisible = false
			d.updatePrMenu()
			d.updateIssuesMenu()
			if d.prMenu.statusItem != nil { visibleMenuCount += 1 }
			if d.issuesMenu.statusItem != nil { visibleMenuCount += 1 }
		}
		if visibleMenuCount == 0 && menuBarSets.count > 0 {
			// Safety net: Ensure that at the very least (usually while importing
			// from an empty DB, with all repos in groups) *some* menu stays visible
			let m = menuBarSets.first!
			m.forceVisible = true
			m.updatePrMenu()
		}
	}

	func startRefresh() {
		if appIsRefreshing {
			DLog("Won't start refresh because refresh is already ongoing")
			return
		}

		if systemSleeping {
			DLog("Won't start refresh because the system is in power-nap / sleep")
			return
		}

		if !API.hasNetworkConnection {
			DLog("Won't start refresh because internet connectivity is down")
			return
		}

		if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
			DLog("Won't start refresh because there are no configured API servers")
			return
		}

		prepareForRefresh()

		for d in menuBarSets {
			d.allowRefresh = false
		}

		API.syncItemsForActiveReposAndCallback { [weak self] in

			guard let s = self else { return }

			for d in s.menuBarSets {
				d.allowRefresh = true
			}

			if !ApiServer.shouldReportRefreshFailure(in: DataManager.main) {
				Settings.lastSuccessfulRefresh = Date()
			}
			s.completeRefresh()
			s.refreshTimer = Timer(repeats: false, interval: TimeInterval(Settings.refreshPeriod)) {
				s.refreshTimerDone()
			}
		}
	}

	private func refreshTimerDone() {
		refreshTimer = nil
		if DataManager.appIsConfigured {
			if preferencesWindow != nil {
				preferencesDirty = true
			} else {
				startRefresh()
			}
		}
	}

	/////////////////////// keyboard shortcuts

	var statusItemList: [NSStatusItem] {
		var list = [NSStatusItem]()
		for s in menuBarSets {
			if let i = s.prMenu.statusItem, let v = i.view, v.frame.size.width > 0 {
				list.append(i)
			}
			if let i = s.issuesMenu.statusItem, let v = i.view, v.frame.size.width > 0 {
				list.append(i)
			}
		}
		return list
	}

	func addHotKeySupport() {
		if Settings.hotkeyEnable {
			if globalKeyMonitor == nil {
				let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
				let options = [key: NSNumber(value: (AXIsProcessTrusted() == false))] as CFDictionary
				if AXIsProcessTrustedWithOptions(options) == true {
					globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] incomingEvent in
						self?.checkForHotkey(in: incomingEvent)
					}
				}
			}
		} else {
			if globalKeyMonitor != nil {
				NSEvent.removeMonitor(globalKeyMonitor!)
				globalKeyMonitor = nil
			}
		}

		if keyDownMonitor != nil {
			return
		}

		keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] incomingEvent -> NSEvent? in

			guard let S = self else { return incomingEvent }

			if S.checkForHotkey(in: incomingEvent) {
				return nil
			}

			if let w = incomingEvent.window as? MenuWindow {
				//DLog("Keycode: %@", incomingEvent.keyCode)

				switch incomingEvent.keyCode {
				case 123, 124: // left, right
					if !incomingEvent.modifierFlags.contains([.command, .option]) {
						return incomingEvent
					}

					let statusItems = S.statusItemList
					if let s = w.statusItem, let ind = statusItems.index(of: s) {
						var nextIndex = incomingEvent.keyCode==123 ? ind+1 : ind-1
						if nextIndex < 0 {
							nextIndex = statusItems.count-1
						} else if nextIndex >= statusItems.count {
							nextIndex = 0
						}
						let newStatusItem = statusItems[nextIndex]
						for s in S.menuBarSets {
							if s.prMenu.statusItem === newStatusItem {
								S.show(menu: s.prMenu)
								break
							} else if s.issuesMenu.statusItem === newStatusItem {
								S.show(menu: s.issuesMenu)
								break
							}
						}
					}
					return nil

				case 125: // down
					if incomingEvent.modifierFlags.contains(.shift) {
						return incomingEvent
					}
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					var i = w.table.selectedRow + 1
					if i < w.table.numberOfRows {
						while w.itemDelegate.itemAtRow(i) == nil { i += 1 }
					} else if w.table.numberOfRows > 0 {
						i = 0
						while w.itemDelegate.itemAtRow(i) == nil { i += 1 }
					}
					S.scrollTo(index: i, inMenu: w)
					return nil

				case 126: // up
					if incomingEvent.modifierFlags.contains(.shift) {
						return incomingEvent
					}
					if app.isManuallyScrolling && w.table.selectedRow == -1 { return nil }
					var i = w.table.selectedRow - 1
					if i > 0 && w.table.numberOfRows > 0 {
						while w.itemDelegate.itemAtRow(i) == nil { i -= 1 }
					} else {
						i = w.table.numberOfRows - 1
					}
					S.scrollTo(index: i, inMenu: w)
					return nil

				case 36: // enter
					if let c = NSTextInputContext.current(), c.client.hasMarkedText() {
						return incomingEvent
					}
					if let dataItem = S.focusedItem(blink: true) {
						let isAlternative = incomingEvent.modifierFlags.contains(.option)
						S.selected(dataItem, alternativeSelect: isAlternative, window: w)
					}
					return nil

				case 53: // escape
					w.closeMenu()
					return nil

				default:
					if !incomingEvent.modifierFlags.contains(.command) {
						return incomingEvent
					}

					guard let selectedItem = S.focusedItem(blink: false) else { return incomingEvent }

					switch incomingEvent.charactersIgnoringModifiers ?? "" {
					case "m":
						selectedItem.setMute(to: !selectedItem.muted)
						DataManager.saveDB()
						app.updateRelatedMenus(for: selectedItem)
						return nil
					case "o":
						if let w = selectedItem.repo.webUrl, let u = URL(string: w) {
							NSWorkspace.shared().open(u)
							return nil
						}
					default:
						if !incomingEvent.modifierFlags.contains(.option) {
							return incomingEvent
						}
						if let snoozeIndex = Int(incomingEvent.charactersIgnoringModifiers ?? "") {
							if snoozeIndex > 0 && !selectedItem.isSnoozing {
								if S.snooze(item: selectedItem, snoozeIndex: snoozeIndex-1, window: w) {
									return nil
								}
							} else if snoozeIndex == 0 && selectedItem.isSnoozing {
								S.wake(item: selectedItem, window: w)
								return nil
							}
						}
					}
				}
			}
			return incomingEvent
		}
	}

	private func wake(item: ListableItem, window: MenuWindow) {
		let oldIndex = window.table.selectedRow
		item.wakeUp()
		DataManager.saveDB()
		app.updateRelatedMenus(for: item)
		scrollToNearest(index: oldIndex, window: window, preferDown : false)
	}

	private func snooze(item: ListableItem, snoozeIndex: Int, window: MenuWindow) -> Bool {
		let s = SnoozePreset.allSnoozePresets(in: DataManager.main)
		if s.count > snoozeIndex  {
			let oldIndex = window.table.selectedRow
			item.snooze(using: s[snoozeIndex])
			DataManager.saveDB()
			updateRelatedMenus(for: item)
			scrollToNearest(index: oldIndex, window: window, preferDown: true)
			return true
		}
		return false
	}

	private func scrollToNearest(index: Int, window: MenuWindow, preferDown: Bool) {
		let table = window.table!
		let maxRowIndex = table.numberOfRows-1
		if maxRowIndex >= 0 {
			var i = index + (preferDown ? 0 : 1)
			i = min(maxRowIndex, max(0, i))
			if window.itemDelegate.itemAtRow(i) == nil {
				i += preferDown ? -1 : 1
				i = min(maxRowIndex, max(0, i))
			}
			scrollTo(index: i, inMenu: window)
		}
	}

	private func scrollTo(index i: Int, inMenu: MenuWindow) {
		app.isManuallyScrolling = true
		mouseIgnoreTimer.push()
		inMenu.table.scrollRowToVisible(i)
		delay(0.01) {
			if let cell = inMenu.table.view(atColumn: 0, row: i, makeIfNecessary: false) as? TrailerCell {
				cell.selected = true
			}
		}
	}

	func focusedItem(blink: Bool) -> ListableItem? {
		if !isManuallyScrolling, let w = visibleWindow {
			return w.focusedItem(blink: blink)
		}
		return nil
	}

	@discardableResult
	private func checkForHotkey(in incomingEvent: NSEvent) -> Bool {
		var check = 0

		let cmdPressed = incomingEvent.modifierFlags.contains(.command)
		if Settings.hotkeyCommandModifier { check += cmdPressed ? 1 : -1 } else { check += cmdPressed ? -1 : 1 }

		let ctrlPressed = incomingEvent.modifierFlags.contains(.control)
		if Settings.hotkeyControlModifier { check += ctrlPressed ? 1 : -1 } else { check += ctrlPressed ? -1 : 1 }

		let altPressed = incomingEvent.modifierFlags.contains(.option)
		if Settings.hotkeyOptionModifier { check += altPressed ? 1 : -1 } else { check += altPressed ? -1 : 1 }

		let shiftPressed = incomingEvent.modifierFlags.contains(.shift)
		if Settings.hotkeyShiftModifier { check += shiftPressed ? 1 : -1 } else { check += shiftPressed ? -1 : 1 }

		let keyMap = [
			"A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4, "I": 34, "J": 38,
			"K": 40, "L": 37, "M": 46, "N": 45, "O": 31, "P": 35, "Q": 12, "R": 15, "S": 1,
			"T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6 ]

		if check == 4, let n = keyMap[Settings.hotkeyLetter], incomingEvent.keyCode == UInt16(n) {
			handleOpeningHotkey(from: incomingEvent)
			return true
		}

		return false
	}

	private func handleOpeningHotkey(from incomingEvent: NSEvent) {

		if let w = incomingEvent.window as? MenuWindow {
			w.closeMenu()
		} else {
			for s in menuBarSets.reversed() {
				if s.prMenu.statusItem != nil {
					show(menu: s.prMenu)
					break
				}
				if s.issuesMenu.statusItem != nil {
					show(menu: s.issuesMenu)
					break
				}
			}
		}
	}

	////////////// scrollbars
	
	func updateScrollBarWidth() {
		if let s = menuBarSets.first!.prMenu.scrollView.verticalScroller {
			if s.scrollerStyle == NSScrollerStyle.legacy {
				scrollBarWidth = s.frame.size.width
			} else {
				scrollBarWidth = 0
			}
		}
		updateAllMenus()
	}

	////////////////////// windows

	private var startupAssistantController: NSWindowController?
	private func startupAssistant() {
		if startupAssistantController == nil {
			startupAssistantController = NSWindowController(windowNibName:"SetupAssistant")
			if let w = startupAssistantController!.window as? SetupAssistant {
				w.level = Int(CGWindowLevelForKey(CGWindowLevelKey.floatingWindow))
				w.center()
				w.makeKeyAndOrderFront(self)
			}
		}
	}
	func closedSetupAssistant() {
		startupAssistantController = nil
	}

	private var aboutWindowController: NSWindowController?
	func showAboutWindow() {
		if aboutWindowController == nil {
			aboutWindowController = NSWindowController(windowNibName:"AboutWindow")
		}
		if let w = aboutWindowController!.window as? AboutWindow {
			w.level = Int(CGWindowLevelForKey(CGWindowLevelKey.floatingWindow))
			w.version.stringValue = versionString
			w.center()
			w.makeKeyAndOrderFront(self)
		}
	}
	func closedAboutWindow() {
		aboutWindowController = nil
	}

	private var preferencesWindowController: NSWindowController?
	private var preferencesWindow: PreferencesWindow?
	func showPreferencesWindow(andSelect selectTab: Int?) {
		if preferencesWindowController == nil {
			preferencesWindowController = NSWindowController(windowNibName:"PreferencesWindow")
		}
		if let w = preferencesWindowController!.window as? PreferencesWindow {
			w.level = Int(CGWindowLevelForKey(CGWindowLevelKey.floatingWindow))
			w.center()
			w.makeKeyAndOrderFront(self)
			preferencesWindow = w
			if let s = selectTab {
				w.tabs.selectTabViewItem(at: s)
			}
		}
	}
	func closedPreferencesWindow() {
		preferencesWindow = nil
		preferencesWindowController = nil
	}

	func statusItem(for view: NSView) -> NSStatusItem? {
		for d in menuBarSets {
			if d.prMenu.statusItem?.view === view { return d.prMenu.statusItem }
			if d.issuesMenu.statusItem?.view === view { return d.issuesMenu.statusItem }
		}
		return nil
	}

	var visibleWindow: MenuWindow? {
		for d in menuBarSets {
			if d.prMenu.isVisible { return d.prMenu }
			if d.issuesMenu.isVisible { return d.issuesMenu }
		}
		return nil
	}

	func updateVibrancies() {
		for d in menuBarSets {
			d.prMenu.updateVibrancy()
			d.issuesMenu.updateVibrancy()
		}
	}

	//////////////////////// Database error on startup

	private func databaseErrorOnStartup() {
		let alert = NSAlert()
		alert.messageText = "Database error"
		alert.informativeText = "Trailer encountered an error while trying to load the database.\n\nThis could be because of a failed upgrade or a software bug.\n\nPlease either quit and downgrade to the previous version, or reset Trailer's state and setup from a fresh state."
		alert.addButton(withTitle: "Quit")
		alert.addButton(withTitle: "Reset Trailer")

		if alert.runModal() == NSAlertSecondButtonReturn {
			DataManager.removeDatabaseFiles()
			restartApp()
		}
		NSApp.terminate(self)
	}

	// With many thanks to http://vgable.com/blog/2008/10/05/restarting-your-cocoa-application/
	private func restartApp() {
		let ourPID = "\(ProcessInfo.processInfo.processIdentifier)"
		let shArgs = ["-c", "kill -9 $1 \n sleep 1 \n open \"$2\"", "", ourPID, Bundle.main.bundlePath]
		let restartTask = Process.launchedProcess(launchPath: "/bin/sh", arguments: shArgs)
		restartTask.waitUntilExit()
	}

	//////////////////////// Dark mode

	var darkMode = false
	func updateDarkModeDelayed() {
		delay(0.1, self) { S in
			S.updateDarkMode()
		}
	}
	private func updateDarkMode() {
		if !systemSleeping {
			if menuBarSets.count == 0 || darkMode != currentSystemDarkMode {
				setupWindows()
			}
		}
	}

	private var currentSystemDarkMode: Bool {
		if let appearance = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") {
			return appearance == "Dark"
		} else {
			return false
		}
	}

	// Server display list
	private var menuBarSets = [MenuBarSet]()
	private func menuBarSet(for window: MenuWindow) -> MenuBarSet? {
		for d in menuBarSets {
			if d.prMenu === window || d.issuesMenu === window {
				return d
			}
		}
		return nil
	}
}
