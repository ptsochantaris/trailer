import Cocoa

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
        prMenu.dataSource = MenuWindow.DataSource(type: PullRequest.self, sections: Section.prMenuTitles, removeButtonsInSections: [Section.merged.prMenuName, Section.closed.prMenuName], viewCriterion: viewCriterion)
		prMenu.delegate = delegate
		
		issuesMenu = issuesMenuController.window as! MenuWindow
        issuesMenu.dataSource = MenuWindow.DataSource(type: Issue.self, sections: Section.issueMenuTitles, removeButtonsInSections: [Section.closed.issuesMenuName], viewCriterion: viewCriterion)
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
		
        allowRefresh = false
        
		let grayOut = Settings.grayOutWhenRefreshing
		
		if prMenu.messageView != nil {
			updatePrMenu()
		}
		prMenu.refreshMenuItem.title = " Refreshing…"
		prMenu.statusItem?.statusView.grayOut = grayOut
		
		if issuesMenu.messageView != nil {
			updateIssuesMenu()
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
	
	private static let redText = [ NSAttributedString.Key.font: NSFont.boldSystemFont(ofSize: 10),
	                               NSAttributedString.Key.foregroundColor: NSColor(red: 0.8, green: 0.0, blue: 0.0, alpha: 1.0) ]
	
	private static let normalText = [ NSAttributedString.Key.font: NSFont.menuBarFont(ofSize: 10),
	                                  NSAttributedString.Key.foregroundColor: NSColor.controlTextColor ]
	
    private func shouldShow(type: ListableItem.Type) -> Bool {
        let fc = ListableItem.requestForItems(of: type, withFilter: nil, sectionIndex: -1, criterion: viewCriterion)
        fc.fetchLimit = 1
        return try! DataManager.main.count(for: fc) > 0
    }
    
    private func updateMenu(of type: ListableItem.Type,
                            menu: MenuWindow,
                            forceVisible: Bool,
                            lengthOffset: CGFloat,
                            hasUnread: Bool,
                            reasonForEmpty: @escaping (String) -> NSAttributedString) {
		
        if forceVisible || shouldShow(type: type) {
			let shouldGray = Settings.grayOutWhenRefreshing && API.isRefreshing
						
            let somethingFailed = ApiServer.shouldReportRefreshFailure(in: DataManager.main) && (viewCriterion?.relatedServerFailed ?? true)
            let attributes = somethingFailed || hasUnread ? MenuBarSet.redText : MenuBarSet.normalText

            let excludeSnoozed = !Settings.countVisibleSnoozedItems
            let f = ListableItem.requestForItems(of: type, withFilter: menu.filter.stringValue, sectionIndex: -1, criterion: viewCriterion, excludeSnoozed: excludeSnoozed)
            let countString = somethingFailed ? "X" : String(try! DataManager.main.count(for: f))

            DLog("Updating \(type) menu, \(countString) total items")
            
            let siv = StatusItemView()
			if siv.grayOut != shouldGray || siv.statusLabel != countString || !compare(dictionary: siv.textAttributes, to: attributes) {
				DLog("Updating \(type) status item")
                if let img = NSImage(named: NSImage.Name("\(type)Icon")) {
                    var size = img.size
                    let scale = 16.0 / size.height
                    size.width *= scale
                    size.height *= scale
                    siv.icon = img.resized(to: size, offset: NSPoint(x: 3, y: 3))
                }
				siv.textAttributes = attributes
				siv.labelOffset = lengthOffset
				siv.highlighted = menu.isVisible
				siv.grayOut = shouldGray
				siv.statusLabel = countString
				siv.title = viewCriterion?.label
				siv.sizeToFit()
			}
            
            menu.statusItem = NSStatusBar.system.statusItem(withLength: siv.frame.width)
            menu.statusItem!.button!.addSubview(siv)
            menu.statusItem!.button!.target = menu
            menu.statusItem!.button!.action = #selector(MenuWindow.buttonSelected)

        } else {
            menu.hideStatusItem()
        }
		
        DispatchQueue.main.async {
            menu.reload()
            
            if menu.table.numberOfRows == 0 {
                menu.messageView = MessageView(frame: CGRect(x: 0, y: 0, width: MENU_WIDTH, height: 100), message: reasonForEmpty(menu.filter.stringValue))
            }
            
            menu.size(andShow: false)
        }
	}
	
	func updateIssuesMenu(forceVisible: Bool = false) {
		if forceVisible || Repo.mayProvideIssuesForDisplay(fromServerWithId: viewCriterion?.apiServerId) {
			
            let hasUnread = Issue.badgeCount(in: DataManager.main, criterion: viewCriterion) > 0
            updateMenu(of: Issue.self, menu: issuesMenu, forceVisible: forceVisible, lengthOffset: 1.5, hasUnread: hasUnread) {
                Issue.reasonForEmpty(with: $0, criterion: self.viewCriterion)
			}
			
		} else {
			issuesMenu.hideStatusItem()
		}
	}
	
    func updatePrMenu(forceVisible: Bool = false) {
		let sid = viewCriterion?.apiServerId
		if forceVisible || Repo.mayProvidePrsForDisplay(fromServerWithId: sid) || !Repo.mayProvideIssuesForDisplay(fromServerWithId: sid) {
			
            let hasUnread = PullRequest.badgeCount(in: DataManager.main, criterion: viewCriterion) > 0
            updateMenu(of: PullRequest.self, menu: prMenu, forceVisible: forceVisible, lengthOffset: -2, hasUnread: hasUnread) {
                PullRequest.reasonForEmpty(with: $0, criterion: self.viewCriterion)
			}
			
		} else {
			prMenu.hideStatusItem()
        }
	}
	
	private func compare(dictionary from: [AnyHashable: Any], to: [AnyHashable: Any]) -> Bool {
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
