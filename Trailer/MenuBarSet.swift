import Cocoa
import PopTimer

// from: https://stackoverflow.com/questions/11949250/how-to-resize-nsimage/42915296#42915296
extension NSImage {
    func resized(to destSize: NSSize, offset: NSPoint) -> NSImage {
        let finalSize = NSSize(width: destSize.width + offset.x * 2, height: destSize.height + offset.y * 2)
        let newImage = NSImage(size: finalSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: offset, size: destSize),
             from: NSRect(origin: .zero, size: size),
             operation: .sourceOver,
             fraction: 1)
        newImage.unlockFocus()
        newImage.size = destSize
        return NSImage(data: newImage.tiffRepresentation!)!
    }
}

@MainActor
final class MenuBarSet {
    private let prMenuController = NSWindowController(windowNibName: NSNib.Name("MenuWindow"))
    private let issuesMenuController = NSWindowController(windowNibName: NSNib.Name("MenuWindow"))

    let prMenu: MenuWindow
    let issuesMenu: MenuWindow
    let viewCriterion: GroupingCriterion?

    var prFilterTimer: PopTimer!
    var issuesFilterTimer: PopTimer!

    init(viewCriterion: GroupingCriterion?, delegate: NSWindowDelegate) {
        self.viewCriterion = viewCriterion

        prMenu = prMenuController.window as! MenuWindow
        let prMenuTitles = Section.allCases.map(\.prMenuName)
        prMenu.dataSource = MenuWindow.DataSource(type: PullRequest.self, sections: prMenuTitles, removeButtonsInSections: [Section.merged.prMenuName, Section.closed.prMenuName], viewCriterion: viewCriterion)
        prMenu.delegate = delegate

        issuesMenu = issuesMenuController.window as! MenuWindow
        let issueMenuTitles = Section.allCases.map(\.issuesMenuName)
        issuesMenu.dataSource = MenuWindow.DataSource(type: Issue.self, sections: issueMenuTitles, removeButtonsInSections: [Section.closed.issuesMenuName], viewCriterion: viewCriterion)
        issuesMenu.delegate = delegate
    }

    func throwAway() {
        prMenu.hideStatusItem()
        prMenu.close()
        issuesMenu.hideStatusItem()
        issuesMenu.close()
    }

    func setTimers() {
        prFilterTimer = PopTimer(timeInterval: 0.2) { [weak self] in
            guard let self else { return }
            await updatePrMenu(settings: Settings.cache)
            prMenu.scrollToTop()
        }

        issuesFilterTimer = PopTimer(timeInterval: 0.2) { [weak self] in
            guard let self else { return }
            await updateIssuesMenu(settings: Settings.cache)
            issuesMenu.scrollToTop()
        }
    }

    func prepareForRefresh() {
        allowRefresh = false

        let grayOut = Settings.grayOutWhenRefreshing

        if prMenu.messageView != nil {
            Task {
                await updatePrMenu(settings: Settings.cache)
            }
        }
        prMenu.refreshMenuItem.title = " Refreshing…"
        prMenu.statusItem?.statusView.grayOut = grayOut

        if issuesMenu.messageView != nil {
            Task {
                await updateIssuesMenu(settings: Settings.cache)
            }
        }
        issuesMenu.refreshMenuItem.title = " Refreshing…"
        issuesMenu.statusItem?.statusView.grayOut = grayOut
    }

    var allowRefresh = false {
        didSet {
            if allowRefresh {
                prMenu.refreshMenuItem.target = prMenu
                prMenu.refreshMenuItem.action = #selector(prMenu.refreshSelected)
                issuesMenu.refreshMenuItem.target = issuesMenu
                issuesMenu.refreshMenuItem.action = #selector(issuesMenu.refreshSelected)
            } else {
                prMenu.refreshMenuItem.action = nil
                prMenu.refreshMenuItem.target = nil
                issuesMenu.refreshMenuItem.action = nil
                issuesMenu.refreshMenuItem.target = nil
            }
        }
    }

    private static let redText = [NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 10),
                                  NSAttributedString.Key.foregroundColor: NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0)]

    private static let normalText = [NSAttributedString.Key.font: NSFont.menuBarFont(ofSize: 10),
                                     NSAttributedString.Key.foregroundColor: NSColor.controlTextColor]

    private func shouldShow(type: ListableItem.Type, settings: Settings.Cache) -> Bool {
        let fc = ListableItem.requestForItems(of: type, withFilter: nil, sectionIndex: -1, criterion: viewCriterion, settings: settings)
        fc.fetchLimit = 1
        return try! DataManager.main.count(for: fc) > 0
    }

    private func updateMenu(of type: ListableItem.Type,
                            menu: MenuWindow,
                            forceVisible: Bool,
                            hasUnread: Bool,
                            settings: Settings.Cache,
                            reasonForEmpty: @escaping @MainActor (String) async -> NSAttributedString) async {
        if forceVisible || shouldShow(type: type, settings: settings) {
            let isRefreshing = API.isRefreshing
            let shouldGray = Settings.grayOutWhenRefreshing && isRefreshing

            let somethingFailed = ApiServer.shouldReportRefreshFailure(in: DataManager.main) && (viewCriterion?.relatedServerFailed ?? true)
            let attributes = somethingFailed || hasUnread ? MenuBarSet.redText : MenuBarSet.normalText

            let excludeSnoozed = !Settings.countVisibleSnoozedItems
            let f = ListableItem.requestForItems(of: type, withFilter: menu.filter.stringValue, sectionIndex: -1, criterion: viewCriterion, excludeSnoozed: excludeSnoozed, settings: settings)
            let countString = somethingFailed ? "X" : (Settings.hideMenubarCounts ? "" : String(try! DataManager.main.count(for: f)))

            let label = viewCriterion?.label
            await Logging.shared.log("Updating \(label ?? "general") \(type) menu, \(countString) total items")

            let siv = StatusItemView(icon: type == PullRequest.self ? StatusItemView.prIcon : StatusItemView.issueIcon,
                                     textAttributes: attributes,
                                     highlighted: menu.isVisible,
                                     grayOut: shouldGray,
                                     countLabel: countString,
                                     title: label)

            if let existingItem = menu.statusItem {
                existingItem.length = siv.frame.width
                existingItem.button!.viewWithTag(siv.tag)?.removeFromSuperview()
            } else {
                menu.statusItem = NSStatusBar.system.statusItem(withLength: siv.frame.width)
            }
            let button = menu.statusItem!.button!
            button.addSubview(siv)
            button.target = menu
            button.action = #selector(MenuWindow.buttonSelected)

        } else {
            menu.hideStatusItem()
        }

        menu.reload()

        if menu.table.numberOfRows == 0 {
            let reason = await reasonForEmpty(menu.filter.stringValue)
            menu.messageView = MessageView(frame: CGRect(x: 0, y: 0, width: MENU_WIDTH, height: 100), message: reason)
        }

        menu.size(andShow: false)
    }

    func updateIssuesMenu(forceVisible: Bool = false, settings: Settings.Cache) async {
        if forceVisible || Repo.mayProvideIssuesForDisplay(fromServerWithId: viewCriterion?.apiServerId) {
            let hasUnread = Issue.badgeCount(in: DataManager.main, criterion: viewCriterion, settings: settings) > 0
            await updateMenu(of: Issue.self, menu: issuesMenu, forceVisible: forceVisible, hasUnread: hasUnread, settings: settings) {
                Issue.reasonForEmpty(with: $0, criterion: self.viewCriterion)
            }

        } else {
            issuesMenu.hideStatusItem()
        }
    }

    func updatePrMenu(forceVisible: Bool = false, settings: Settings.Cache) async {
        let sid = viewCriterion?.apiServerId
        if forceVisible || Repo.mayProvidePrsForDisplay(fromServerWithId: sid) || !Repo.mayProvideIssuesForDisplay(fromServerWithId: sid) {
            let hasUnread = PullRequest.badgeCount(in: DataManager.main, criterion: viewCriterion, settings: settings) > 0
            await updateMenu(of: PullRequest.self, menu: prMenu, forceVisible: forceVisible, hasUnread: hasUnread, settings: settings) {
                PullRequest.reasonForEmpty(with: $0, criterion: self.viewCriterion)
            }

        } else {
            prMenu.hideStatusItem()
        }
    }

    private func compare(dictionary from: [String: Sendable], to: [String: Sendable]) -> Bool {
        for (key, value) in from {
            if let v = to[key] {
                if String(describing: v) != String(describing: value) {
                    return false
                }
            } else {
                return false
            }
        }
        return true
    }
}
