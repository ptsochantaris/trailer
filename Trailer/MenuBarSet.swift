
final class MenuBarSet {
	
	private let prMenuController = NSWindowController(windowNibName:NSNib.Name("MenuWindow"))
	private let issuesMenuController = NSWindowController(windowNibName:NSNib.Name("MenuWindow"))
	
	let prMenu: MenuWindow
	let issuesMenu: MenuWindow
	let viewCriterion: GroupingCriterion?
	
	var prFilterTimer: PopTimer!
	var issuesFilterTimer: PopTimer!
	
	var forceVisible = false
	
	init(viewCriterion: GroupingCriterion?, delegate: NSWindowDelegate) {
		self.viewCriterion = viewCriterion
		
		prMenu = prMenuController.window as! MenuWindow
		prMenu.itemDelegate = ItemDelegate(type: PullRequest.self, sections: Section.prMenuTitles, removeButtonsInSections: [Section.merged.prMenuName, Section.closed.prMenuName], viewCriterion: viewCriterion)
		prMenu.delegate = delegate
		
		issuesMenu = issuesMenuController.window as! MenuWindow
		issuesMenu.itemDelegate = ItemDelegate(type: Issue.self, sections: Section.issueMenuTitles, removeButtonsInSections: [Section.closed.issuesMenuName], viewCriterion: viewCriterion)
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
			guard let s = self else { return }
			s.updatePrMenu()
			s.prMenu.scrollToTop()
		}
		
		issuesFilterTimer = PopTimer(timeInterval: 0.2) { [weak self] in
			guard let s = self else { return }
			s.updateIssuesMenu()
			s.issuesMenu.scrollToTop()
		}
	}
	
	func prepareForRefresh() {
		
		let grayOut = Settings.grayOutWhenRefreshing
		
		if prMenu.messageView != nil {
			updatePrMenu()
		}
		prMenu.refreshMenuItem.title = " Refreshing…"
		(prMenu.statusItem?.view as? StatusItemView)?.grayOut = grayOut
		
		if issuesMenu.messageView != nil {
			updateIssuesMenu()
		}
		issuesMenu.refreshMenuItem.title = " Refreshing…"
		(issuesMenu.statusItem?.view as? StatusItemView)?.grayOut = grayOut
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
	
	private static let redText = [ NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 10),
	                               NSAttributedString.Key.foregroundColor: NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) ]
	
	private static let normalText = [ NSAttributedString.Key.font: NSFont.menuBarFont(ofSize: 10),
	                                  NSAttributedString.Key.foregroundColor: NSColor.controlTextColor ]
	
	private func updateMenu(of type: ListableItem.Type,
	                        menu: MenuWindow,
	                        lengthOffset: CGFloat,
	                        hasUnread: () -> Bool,
	                        reasonForEmpty: (String) -> NSAttributedString) {
		
		let countString: String
		let somethingFailed = ApiServer.shouldReportRefreshFailure(in: DataManager.main) && (viewCriterion?.relatedServerFailed ?? true)
		let attributes = somethingFailed || hasUnread() ? MenuBarSet.redText : MenuBarSet.normalText
		let preFilterCount: Int

		let excludeSnoozed = !Settings.countVisibleSnoozedItems
		let f = ListableItem.requestForItems(of: type, withFilter: menu.filter.stringValue, sectionIndex: -1, criterion: viewCriterion, excludeSnoozed: excludeSnoozed)
		countString = somethingFailed ? "X" : String(try! DataManager.main.count(for: f))

		let fc = ListableItem.requestForItems(of: type, withFilter: nil, sectionIndex: -1, criterion: viewCriterion)
		preFilterCount = try! DataManager.main.count(for: fc)

		DLog("Updating \(type) menu, \(countString) total items")
		
		let itemLabel = viewCriterion?.label
		let disable = itemLabel != nil && preFilterCount == 0 && !(forceVisible && type == PullRequest.self)
		
		if disable {
			menu.hideStatusItem()
		} else {
			
			let shouldGray = Settings.grayOutWhenRefreshing && appIsRefreshing
			
			let siv = menu.showStatusItem
			
			if !(compare(dictionary: siv.textAttributes, to: attributes) && siv.statusLabel == countString && siv.grayOut == shouldGray) {
				// Info has changed, update
				DLog("Updating \(type) status item")
				siv.icon = NSImage(named: NSImage.Name("\(type)Icon"))!
				siv.textAttributes = attributes
				siv.labelOffset = lengthOffset
				siv.highlighted = menu.isVisible
				siv.grayOut = shouldGray
				siv.statusLabel = countString
				siv.title = itemLabel
				siv.sizeToFit()
			}
		}
		
		menu.reload()
		
		if menu.table.numberOfRows == 0 {
			menu.messageView = MessageView(frame: CGRect(x: 0, y: 0, width: MENU_WIDTH, height: 100), message: reasonForEmpty(menu.filter.stringValue))
		}
		
		menu.size(andShow: false)
	}
	
	func updateIssuesMenu() {
		
		if Repo.interestedInIssues(fromServerWithId: viewCriterion?.apiServerId) {
			
			updateMenu(of: Issue.self, menu: issuesMenu, lengthOffset: 2, hasUnread: { () -> Bool in
				return Issue.badgeCount(in: DataManager.main, criterion: viewCriterion) > 0
			}, reasonForEmpty: { filter -> NSAttributedString in
				return Issue.reasonForEmpty(with: filter, criterion: viewCriterion)
			})
			
		} else {
			issuesMenu.hideStatusItem()
		}
	}
	
	func updatePrMenu() {
		
		let sid = viewCriterion?.apiServerId
		if forceVisible || Repo.interestedInPrs(fromServerWithId: sid) || !Repo.interestedInIssues(fromServerWithId: sid) {
			
			updateMenu(of: PullRequest.self, menu: prMenu, lengthOffset: 0, hasUnread: { () -> Bool in
				return PullRequest.badgeCount(in: DataManager.main, criterion: viewCriterion) > 0
			}, reasonForEmpty: { filter -> NSAttributedString in
				return PullRequest.reasonForEmpty(with: filter, criterion: viewCriterion)
			})
			
		} else {
			prMenu.hideStatusItem()
		}
	}
	
	private func compare(dictionary from: [AnyHashable : Any], to: [AnyHashable : Any]) -> Bool {
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
