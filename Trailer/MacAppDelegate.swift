import Cocoa
import CoreSpotlight
import PopTimer
import Sparkle

enum Theme {
    case light, dark
}

@main
final class MacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSUserNotificationCenterDelegate, NSOpenSavePanelDelegate, NSControlTextEditingDelegate {
    // Globals
    var refreshTask: Task<Void, Never>?
    var openingWindow = false
    var isManuallyScrolling = false
    var ignoreNextFocusLoss = false
    var scrollBarWidth: CGFloat = 0

    private var systemSleeping = false
    private var globalKeyMonitor: Any?
    private var keyDownMonitor: Any?
    private var mouseIgnoreTimer: PopTimer!

    @MainActor
    func setupWindows() {
        menuBarSets.forEach { $0.throwAway() }
        menuBarSets.removeAll()

        var newSets = [MenuBarSet]()
        for groupLabel in Repo.allGroupLabels(in: DataManager.main) {
            let c = GroupingCriterion.group(groupLabel)
            let s = MenuBarSet(viewCriterion: c, delegate: self)
            s.setTimers()
            newSets.append(s)
        }

        if Settings.showSeparateApiServersInMenu {
            for a in ApiServer.allApiServers(in: DataManager.main) where a.goodToGo {
                let c = GroupingCriterion.server(a.objectID)
                let s = MenuBarSet(viewCriterion: c, delegate: self)
                s.setTimers()
                newSets.append(s)
            }
        }

        if newSets.isEmpty || (!Settings.showSeparateApiServersInMenu && Repo.anyVisibleRepos(in: DataManager.main, excludeGrouped: true)) {
            let s = MenuBarSet(viewCriterion: nil, delegate: self)
            s.setTimers()
            newSets.append(s)
        }

        menuBarSets = newSets.reversed()

        updateScrollBarWidth() // also updates menus

        for d in menuBarSets {
            d.prMenu.scrollToTop()
            d.issuesMenu.scrollToTop()

            d.prMenu.updateVibrancy()
            d.issuesMenu.updateVibrancy()
        }
    }

    @MainActor
    func applicationWillFinishLaunching(_: Notification) {
        app = self
        bootUp()
        NSTextField.cellClass = CenterTextFieldCell.self
    }

    @MainActor
    func applicationDidFinishLaunching(_: Notification) {
        LauncherCommon.killHelper()

        if DataManager.main.persistentStoreCoordinator == nil {
            databaseErrorOnStartup()
            return
        }

        mouseIgnoreTimer = PopTimer(timeInterval: 0.4) {
            app.isManuallyScrolling = false
        }

        theme = getTheme() // also sets up windows

        NotificationManager.shared.setup()

        Task {
            await DataManager.postProcessAllItems(in: DataManager.main, settings: Settings.cache)
            await API.updateLimitsFromServer()
        }

        if ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
            Task {
                await startRefreshIfItIsDue()
            }
        } else if ApiServer.countApiServers(in: DataManager.main) == 1, let a = ApiServer.allApiServers(in: DataManager.main).first, a.authToken == nil || a.authToken!.isEmpty {
            startupAssistant()
        } else {
            preferencesSelected()
        }

        let n = NotificationCenter.default
        n.addObserver(self, selector: #selector(updateScrollBarWidth), name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        n.addObserver(self, selector: #selector(refreshStarting), name: .RefreshStarting, object: nil)
        n.addObserver(self, selector: #selector(refreshDone), name: .RefreshEnded, object: nil)

        let dn = DistributedNotificationCenter.default()
        dn.addObserver(self, selector: #selector(themeCheck), name: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        addHotKeySupport()
        setUpdateCheckParameters()

        let wn = NSWorkspace.shared.notificationCenter
        wn.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wn.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @MainActor
    @objc private func themeCheck() {
        let c = getTheme()
        if theme != c {
            theme = c
        }
    }

    @objc private func systemWillSleep() {
        systemSleeping = true
        Task {
            await Logging.shared.log("System is going to sleep")
        }
    }

    @objc private func systemDidWake() {
        Task {
            await Logging.shared.log("System woke up")
        }
        systemSleeping = false
        Task {
            try? await Task.sleep(nanoseconds: 2 * NSEC_PER_SEC)
            await themeCheck()
            await startRefreshIfItIsDue()
        }
    }

    @MainActor
    func performUpdateCheck() {
        updater.updater.checkForUpdates()
    }

    @MainActor
    func setUpdateCheckParameters() {
        updater.updater.updateCheckInterval = TimeInterval(Settings.checkForUpdatesInterval)
    }

    @MainActor
    private lazy var updater = SPUStandardUpdaterController(startingUpdater: Settings.checkForUpdatesAutomatically, updaterDelegate: self, userDriverDelegate: nil)

    @MainActor
    func selected(_ item: ListableItem, alternativeSelect: Bool, window: NSWindow?) {
        guard let w = window as? MenuWindow, let menuBarSet = menuBarSet(for: w) else { return }

        ignoreNextFocusLoss = alternativeSelect

        let urlToOpen = item.urlForOpening
        item.catchUpWithComments(settings: Settings.cache)
        Task {
            await updateRelatedMenus(for: item)

            let window = item.isPr ? menuBarSet.prMenu : menuBarSet.issuesMenu
            let reSelectIndex = alternativeSelect ? window.table.selectedRow : -1
            _ = window.filter.becomeFirstResponder()

            if reSelectIndex > -1, reSelectIndex < window.table.numberOfRows {
                window.table.selectRowIndexes(IndexSet(integer: reSelectIndex), byExtendingSelection: false)
            }

            if let urlToOpen, let url = URL(string: urlToOpen) {
                openItem(url)
            }
        }
    }

    func show(menu: MenuWindow) {
        if menu.isVisible {
            return
        }
        visibleWindow?.closeMenu()
        menu.size(andShow: true)
    }

    @MainActor
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
                    _ = alert.addButton(withTitle: "No")
                    _ = alert.addButton(withTitle: "Yes")
                    alert.showsSuppressionButton = true

                    if alert.runModal() == .alertSecondButtonReturn {
                        removeAllMergedRequests(under: menuBarSet)
                        if alert.suppressionButton!.state == .on {
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
                    _ = alert.addButton(withTitle: "No")
                    _ = alert.addButton(withTitle: "Yes")
                    alert.showsSuppressionButton = true

                    if alert.runModal() == .alertSecondButtonReturn {
                        removeAllClosedRequests(under: menuBarSet)
                        if alert.suppressionButton!.state == .on {
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
                    _ = alert.addButton(withTitle: "No")
                    _ = alert.addButton(withTitle: "Yes")
                    alert.showsSuppressionButton = true

                    if alert.runModal() == .alertSecondButtonReturn {
                        removeAllClosedIssues(under: menuBarSet)
                        if alert.suppressionButton!.state == .on {
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

    @MainActor
    private func removeAllMergedRequests(under menuBarSet: MenuBarSet) {
        for r in PullRequest.allMerged(in: DataManager.main, criterion: menuBarSet.viewCriterion) {
            DataManager.main.delete(r)
        }
        Task {
            await DataManager.saveDB()
            await menuBarSet.updatePrMenu(settings: Settings.cache)
            await ensureAtLeastOneMenuVisible()
        }
    }

    @MainActor
    private func removeAllClosedRequests(under menuBarSet: MenuBarSet) {
        for r in PullRequest.allClosed(in: DataManager.main, criterion: menuBarSet.viewCriterion) {
            DataManager.main.delete(r)
        }
        Task {
            await DataManager.saveDB()
            await menuBarSet.updatePrMenu(settings: Settings.cache)
            await ensureAtLeastOneMenuVisible()
        }
    }

    @MainActor
    private func removeAllClosedIssues(under menuBarSet: MenuBarSet) {
        for i in Issue.allClosed(in: DataManager.main, criterion: menuBarSet.viewCriterion) {
            DataManager.main.delete(i)
        }
        Task {
            await DataManager.saveDB()
            await menuBarSet.updateIssuesMenu(settings: Settings.cache)
            await ensureAtLeastOneMenuVisible()
        }
    }

    @MainActor
    func unPinSelected(for item: ListableItem) {
        let menus = relatedMenus(for: item)
        DataManager.main.delete(item)
        Task {
            await DataManager.saveDB()
            let settings = Settings.cache
            if item.isPr {
                for menu in menus {
                    await menu.updatePrMenu(settings: settings)
                }
            } else {
                for menu in menus {
                    await menu.updateIssuesMenu(settings: settings)
                }
            }
            await ensureAtLeastOneMenuVisible()
        }
    }

    func controlTextDidChange(_ n: Notification) {
        guard let obj = n.object as? NSSearchField, let w = obj.window as? MenuWindow, let menuBarSet = menuBarSet(for: w) else { return }

        Task { @MainActor in
            if obj === menuBarSet.prMenu.filter {
                menuBarSet.prFilterTimer.push()
            } else if obj === menuBarSet.issuesMenu.filter {
                menuBarSet.issuesFilterTimer.push()
            }
        }
    }

    @MainActor
    func markAllReadSelected(from window: MenuWindow) {
        guard let menuBarSet = menuBarSet(for: window) else { return }

        let prMenu = window === menuBarSet.prMenu
        let type: ListableItem.Type = prMenu ? PullRequest.self : Issue.self
        let f = ListableItem.requestForItems(of: type, withFilter: window.filter.stringValue, sectionIndex: -1, criterion: menuBarSet.viewCriterion, settings: Settings.cache)
        let settings = Settings.cache
        for r in try! DataManager.main.fetch(f) {
            r.catchUpWithComments(settings: settings)
        }

        Task {
            await DataManager.saveDB()
            if prMenu {
                await menuBarSet.updatePrMenu(settings: Settings.cache)
            } else {
                await menuBarSet.updateIssuesMenu(settings: Settings.cache)
            }
            await ensureAtLeastOneMenuVisible()
        }
    }

    func preferencesSelected() {
        refreshTask?.cancel()
        refreshTask = nil
        showPreferencesWindow(andSelect: nil)
    }

    func application(_: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        let ext = url.pathExtension
        if ext == "trailerSettings" {
            Task {
                await Logging.shared.log("Will open \(url.absoluteString)")
                await tryLoadSettings(from: url, skipConfirm: Settings.dontConfirmSettingsImport)
            }
            return true
        }
        return false
    }

    @discardableResult
    @MainActor
    func tryLoadSettings(from url: URL, skipConfirm: Bool) async -> Bool {
        if API.isRefreshing {
            let alert = NSAlert()
            alert.messageText = "Trailer is currently refreshing data, please wait until it's done and try importing your settings again"
            _ = alert.addButton(withTitle: "OK")
            _ = alert.runModal()
            return false

        } else if !skipConfirm {
            let alert = NSAlert()
            alert.messageText = "Import settings from this file?"
            alert.informativeText = "This will overwrite all your current Trailer settings, are you sure?"
            _ = alert.addButton(withTitle: "No")
            _ = alert.addButton(withTitle: "Yes")
            alert.showsSuppressionButton = true
            if alert.runModal() == .alertSecondButtonReturn {
                if alert.suppressionButton!.state == .on {
                    Settings.dontConfirmSettingsImport = true
                }
            } else {
                return false
            }
        }

        let readSucceeded = await Settings.readFromURL(url)
        if !readSucceeded {
            let alert = NSAlert()
            alert.messageText = "The selected settings file could not be imported due to an error"
            _ = alert.addButton(withTitle: "OK")
            _ = alert.runModal()
            return false
        }
        await DataManager.postProcessAllItems(in: DataManager.main, settings: Settings.cache)
        await DataManager.saveDB()
        preferencesWindow?.reloadSettings()
        setupWindows()
        preferencesDirty = true
        await startRefresh()

        return true
    }

    @MainActor
    func applicationShouldTerminate(_ app: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await DataManager.saveDB()
            app.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
        } else if !openingWindow, let w = notification.object as? MenuWindow {
            w.closeMenu()
        }
    }

    @MainActor
    func startRefreshIfItIsDue() async {
        if let l = Settings.lastSuccessfulRefresh {
            let howLongAgo = Date().timeIntervalSince(l).rounded()
            let howLongUntilNextSync = Settings.refreshPeriod - howLongAgo
            if howLongUntilNextSync > 0 {
                Task {
                    await Logging.shared.log("No need to refresh yet, will refresh in \(howLongUntilNextSync) sec")
                }
                setupRefreshTask(in: howLongUntilNextSync)
                return
            }
        }
        await startRefresh()
    }

    @MainActor
    private func checkApiUsage() {
        for apiServer in ApiServer.allApiServers(in: DataManager.main) {
            if apiServer.goodToGo, apiServer.hasApiLimit, let resetDate = apiServer.resetDate {
                if apiServer.shouldReportOverTheApiLimit {
                    let apiLabel = apiServer.label.orEmpty
                    let resetDateString = Date.Formatters.itemDateFormat.format(resetDate)

                    let alert = NSAlert()
                    alert.messageText = "Your API request usage for '\(apiLabel)' is over the limit!"
                    alert.informativeText = "Your request cannot be completed until your hourly API allowance is reset \(resetDateString).\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from 'Servers' preferences pane at any time."
                    _ = alert.addButton(withTitle: "OK")
                    _ = alert.runModal()
                } else if apiServer.shouldReportCloseToApiLimit {
                    let apiLabel = apiServer.label.orEmpty
                    let resetDateString = Date.Formatters.itemDateFormat.format(resetDate)

                    let alert = NSAlert()
                    alert.messageText = "Your API request usage for '\(apiLabel)' is close to full"
                    alert.informativeText = "Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by GitHub \(resetDateString).\n\nYou can check your API usage from the 'Servers' preferences pane at any time."
                    _ = alert.addButton(withTitle: "OK")
                    _ = alert.runModal()
                }
            }
        }
    }

    @MainActor
    @objc private func refreshStarting() {
        refreshTask?.cancel()
        refreshTask = nil

        preferencesWindow?.updateActivity()

        for d in menuBarSets {
            d.prepareForRefresh()
        }

        Task {
            await ensureAtLeastOneMenuVisible()
        }
    }

    @MainActor
    @objc private func refreshDone() {
        for d in menuBarSets {
            d.allowRefresh = true
        }

        preferencesWindow?.updateActivity()
        preferencesWindow?.reloadRepositories()

        Task {
            await updateAllMenus()
        }

        setupRefreshTask(in: Settings.refreshPeriod)

        checkApiUsage()
    }

    @MainActor
    func updateRelatedMenus(for i: ListableItem) async {
        let menus = relatedMenus(for: i)
        let settings = Settings.cache
        if i.isPr {
            for menu in menus {
                await menu.updatePrMenu(settings: settings)
            }
        } else {
            for menu in menus {
                await menu.updateIssuesMenu(settings: settings)
            }
        }
        await ensureAtLeastOneMenuVisible()
    }

    @MainActor
    private func relatedMenus(for i: ListableItem) -> [MenuBarSet] {
        menuBarSets.compactMap { ($0.viewCriterion?.isRelated(to: i) ?? true) ? $0 : nil }
    }

    @MainActor
    func application(_: NSApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        if userActivity.activityType == CSSearchableItemActionType,
           let uriPath = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
           let itemId = DataManager.id(for: uriPath),
           let item = try? DataManager.main.existingObject(with: itemId) as? ListableItem,
           let urlString = item.webUrl,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return true
        }
        return false
    }

    @MainActor
    func updateAllMenus() async {
        let settings = Settings.cache
        for d in menuBarSets {
            await d.updatePrMenu(settings: settings)
            await d.updateIssuesMenu(settings: settings)
        }
        await ensureAtLeastOneMenuVisible()
    }

    @MainActor
    private func ensureAtLeastOneMenuVisible() async {
        let atLeastOneMenuVisible = menuBarSets.contains { $0.prMenu.statusItem != nil || $0.issuesMenu.statusItem != nil }
        if !atLeastOneMenuVisible, let firstMenu = menuBarSets.first(where: { $0.viewCriterion?.label == nil }) ?? menuBarSets.first {
            // Safety net: Ensure that at the very least (usually while importing
            // from an empty DB, with all repos in groups) *some* menu stays visible
            await firstMenu.updatePrMenu(forceVisible: true, settings: Settings.cache)
        }
    }

    @MainActor
    func startRefresh() async {
        if API.isRefreshing {
            await Logging.shared.log("Won't start refresh because refresh is already ongoing")
            return
        }

        if systemSleeping {
            await Logging.shared.log("Won't start refresh because the system is in power-nap / sleep")
            return
        }

        let hasConnection = API.hasNetworkConnection
        if !hasConnection {
            await Logging.shared.log("Won't start refresh because internet connectivity is down")
            return
        }

        if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
            await Logging.shared.log("Won't start refresh because there are no configured API servers")
            return
        }

        Task {
            await API.performSync(settings: Settings.cache)

            if Settings.V4IdMigrationPhase == .failedPending {
                let alert = NSAlert()
                alert.messageText = "ID migration failed"
                alert.informativeText = "Trailer tried to automatically migrate your IDs during the most recent sync but it failed for some reason. Since GitHub servers require using a new set of IDs soon please visit Trailer Preferences -> Servers -> V4 API Settings and select the option to try migrating IDs again soon."
                _ = alert.addButton(withTitle: "OK")
                _ = alert.runModal()

                Settings.V4IdMigrationPhase = .failedAnnounced
            }
        }
    }

    @MainActor
    private func setupRefreshTask(in timeToWait: TimeInterval) {
        if let refreshTask, !refreshTask.isCancelled {
            refreshTask.cancel()
        }
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(timeToWait * 1000) * NSEC_PER_MSEC)
            if !Task.isCancelled, DataManager.appIsConfigured {
                await startRefresh()
            }
        }
    }

    /////////////////////// keyboard shortcuts

    var statusItemList: [NSStatusItem] {
        var list = [NSStatusItem]()
        for s in menuBarSets {
            if let i = s.prMenu.statusItem, i.statusView.frame.size.width > 0 {
                list.append(i)
            }
            if let i = s.issuesMenu.statusItem, i.statusView.frame.size.width > 0 {
                list.append(i)
            }
        }
        return list
    }

    @MainActor
    func addHotKeySupport() {
        if Settings.hotkeyEnable {
            if globalKeyMonitor == nil {
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                let options = [key: NSNumber(value: AXIsProcessTrusted() == false)] as CFDictionary
                if AXIsProcessTrustedWithOptions(options) {
                    globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] incomingEvent in
                        _ = self?.checkForHotkey(in: incomingEvent)
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
            guard let self else { return incomingEvent }

            if checkForHotkey(in: incomingEvent) {
                return nil
            }

            if let w = incomingEvent.window as? MenuWindow {
                // Logging.shared.log("Keycode: %@", incomingEvent.keyCode)

                switch incomingEvent.keyCode {
                case 123, 124:
                    // left, right
                    if !incomingEvent.modifierFlags.contains([.command, .option]) {
                        return incomingEvent
                    }

                    let statusItems = statusItemList
                    if let s = w.statusItem, let ind = statusItems.firstIndex(of: s) {
                        var nextIndex = incomingEvent.keyCode == 123 ? ind + 1 : ind - 1
                        if nextIndex < 0 {
                            nextIndex = statusItems.count - 1
                        } else if nextIndex >= statusItems.count {
                            nextIndex = 0
                        }
                        let newStatusItem = statusItems[nextIndex]
                        for s in menuBarSets {
                            if s.prMenu.statusItem === newStatusItem {
                                show(menu: s.prMenu)
                                break
                            } else if s.issuesMenu.statusItem === newStatusItem {
                                show(menu: s.issuesMenu)
                                break
                            }
                        }
                    }
                    return nil

                case 125:
                    // down
                    if incomingEvent.modifierFlags.contains(.shift) {
                        return incomingEvent
                    }
                    if app.isManuallyScrolling, w.table.selectedRow == -1 { return nil }
                    var i = w.table.selectedRow + 1
                    if i < w.table.numberOfRows {
                        while w.dataSource.itemAtRow(i) == nil {
                            i += 1
                        }
                    } else if w.table.numberOfRows > 0 {
                        i = 0
                        while w.dataSource.itemAtRow(i) == nil {
                            i += 1
                        }
                    }
                    scrollTo(index: i, inMenu: w)
                    return nil

                case 126:
                    // up
                    if incomingEvent.modifierFlags.contains(.shift) {
                        return incomingEvent
                    }
                    if app.isManuallyScrolling, w.table.selectedRow == -1 { return nil }
                    var i = w.table.selectedRow - 1
                    if i > 0, w.table.numberOfRows > 0 {
                        while w.dataSource.itemAtRow(i) == nil {
                            i -= 1
                        }
                    } else {
                        i = w.table.numberOfRows - 1
                    }
                    scrollTo(index: i, inMenu: w)
                    return nil

                case 36:
                    // enter
                    if let c = NSTextInputContext.current, c.client.hasMarkedText() {
                        return incomingEvent
                    }
                    if let dataItem = focusedItem(blink: true) {
                        let isAlternative = incomingEvent.modifierFlags.contains(.option)
                        selected(dataItem, alternativeSelect: isAlternative, window: w)
                    }
                    return nil

                case 53:
                    // escape
                    w.closeMenu()
                    return nil

                default:
                    if !incomingEvent.modifierFlags.contains(.command) {
                        return incomingEvent
                    }

                    guard let selectedItem = focusedItem(blink: false) else { return incomingEvent }

                    let chars = incomingEvent.charactersIgnoringModifiers.orEmpty
                    switch chars {
                    case "m":
                        selectedItem.setMute(to: !selectedItem.muted, settings: Settings.cache)
                        Task {
                            await DataManager.saveDB()
                            await app.updateRelatedMenus(for: selectedItem)
                        }
                        return nil
                    case "o":
                        if let w = selectedItem.repo.webUrl, let u = URL(string: w) {
                            openItem(u)
                            return nil
                        }
                    default:
                        guard incomingEvent.modifierFlags.contains(.option), let snoozeIndex = Int(chars) else {
                            return incomingEvent
                        }
                        if snoozeIndex > 0, !selectedItem.isSnoozing {
                            if snooze(item: selectedItem, snoozeIndex: snoozeIndex - 1, window: w) {
                                return nil
                            }
                        } else if snoozeIndex == 0, selectedItem.isSnoozing {
                            wake(item: selectedItem, window: w)
                            return nil
                        }
                    }
                }
            }
            return incomingEvent
        }
    }

    @MainActor
    private func wake(item: ListableItem, window: MenuWindow) {
        let oldIndex = window.table.selectedRow
        item.wakeUp(settings: Settings.cache)
        Task {
            await DataManager.saveDB()
            await app.updateRelatedMenus(for: item)
            scrollToNearest(index: oldIndex, window: window, preferDown: false)
        }
    }

    @MainActor
    private func snooze(item: ListableItem, snoozeIndex: Int, window: MenuWindow) -> Bool {
        let s = SnoozePreset.allSnoozePresets(in: DataManager.main)
        if s.count > snoozeIndex {
            let oldIndex = window.table.selectedRow
            item.snooze(using: s[snoozeIndex], settings: Settings.cache)
            Task {
                await DataManager.saveDB()
                await updateRelatedMenus(for: item)
                scrollToNearest(index: oldIndex, window: window, preferDown: true)
            }
            return true
        }
        return false
    }

    @MainActor
    private func scrollToNearest(index: Int, window: MenuWindow, preferDown: Bool) {
        let table = window.table!
        let maxRowIndex = table.numberOfRows - 1
        if maxRowIndex >= 0 {
            var i = index + (preferDown ? 0 : 1)
            i = min(maxRowIndex, max(0, i))
            if window.dataSource.itemAtRow(i) == nil {
                i += preferDown ? -1 : 1
                i = min(maxRowIndex, max(0, i))
            }
            scrollTo(index: i, inMenu: window)
        }
    }

    @MainActor
    private func scrollTo(index i: Int, inMenu: MenuWindow) {
        app.isManuallyScrolling = true
        mouseIgnoreTimer.push()
        inMenu.table.scrollRowToVisible(i)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
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
    @MainActor
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
            "T": 17, "U": 32, "V": 9, "W": 13, "X": 7, "Y": 16, "Z": 6,
            "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
            "8": 28, "9": 25, "0": 29, "=": 24, "-": 27, "]": 30, "[": 33,
            "'": 39, ";": 41, ",": 43, "/": 44, ".": 47, "`": 50, "\\": 42
        ]

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

    @objc private func updateScrollBarWidth() {
        if let s = menuBarSets.first?.prMenu.scrollView.verticalScroller {
            if s.scrollerStyle == .legacy {
                scrollBarWidth = s.frame.size.width
            } else {
                scrollBarWidth = 0
            }
        }
        Task {
            await updateAllMenus()
        }
    }

    ////////////////////// windows

    private var startupAssistantController: NSWindowController?
    private func startupAssistant() {
        if startupAssistantController == nil {
            startupAssistantController = NSWindowController(windowNibName: NSNib.Name("SetupAssistant"))
            if let w = startupAssistantController!.window as? SetupAssistant {
                w.level = .floating
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
            aboutWindowController = NSWindowController(windowNibName: NSNib.Name("AboutWindow"))
        }
        if let w = aboutWindowController!.window as? AboutWindow {
            w.level = .floating
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
    @discardableResult
    func showPreferencesWindow(andSelect selectTab: Int?) -> PreferencesWindow? {
        if preferencesWindowController == nil {
            preferencesWindowController = NSWindowController(windowNibName: NSNib.Name("PreferencesWindow"))
        }
        if let w = preferencesWindowController!.window as? PreferencesWindow {
            w.level = .floating
            w.center()
            w.makeKeyAndOrderFront(self)
            preferencesWindow = w
            if let selectTab {
                w.tabs.selectTabViewItem(at: selectTab)
            }
            return w
        }
        return nil
    }

    func closedPreferencesWindow() {
        preferencesWindow = nil
        preferencesWindowController = nil
    }

    func statusItem(for view: NSView) -> NSStatusItem? {
        for d in menuBarSets {
            if let prItem = d.prMenu.statusItem, prItem.statusView === view {
                return prItem
            } else if let issueItem = d.issuesMenu.statusItem, issueItem.statusView === view {
                return issueItem
            }
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

    //////////////////////// Database error on startup

    @MainActor
    private func databaseErrorOnStartup() {
        let alert = NSAlert()
        alert.messageText = "Database error"
        alert.informativeText = "Trailer encountered an error while trying to load the database.\n\nThis could be because of a failed upgrade or a software bug.\n\nPlease either quit and downgrade to the previous version, or reset Trailer's state and setup from a fresh state."
        _ = alert.addButton(withTitle: "Quit")
        _ = alert.addButton(withTitle: "Reset Trailer")

        if alert.runModal() == .alertSecondButtonReturn {
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

    @MainActor
    var theme = Theme.light {
        didSet {
            setupWindows()
        }
    }

    private func getTheme() -> Theme {
        // with many thanks from https://medium.com/@ruiaureliano/check-light-dark-appearance-for-macos-mojave-catalina-fb2343af875f
        let d = UserDefaults.standard
        let autoSwitching = d.bool(forKey: "AppleInterfaceStyleSwitchesAutomatically")
        let interfaceStyle = d.string(forKey: "AppleInterfaceStyle")
        if autoSwitching, interfaceStyle == nil {
            let isDark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .dark : .light
        }
        return (interfaceStyle == "Dark") ? .dark : .light
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

extension MacAppDelegate: SPUUpdaterDelegate {
    func updaterDidNotFindUpdate(_: SPUUpdater) {
        Task {
            await Logging.shared.log("No app updates available")
        }
    }

    func updaterDidNotFindUpdate(_: SPUUpdater, error: Error) {
        Task {
            await Logging.shared.log("Could not look for update: \(error.localizedDescription)")
        }
    }

    func updater(_: SPUUpdater, didFindValidUpdate _: SUAppcastItem) {
        Task {
            await Logging.shared.log("Found update")
        }
    }
}
