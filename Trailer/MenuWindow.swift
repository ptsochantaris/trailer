import Cocoa

extension NSStatusItem {
    var statusView: StatusItemView {
        button!.viewWithTag(1947) as! StatusItemView
    }
}

final class MenuWindow: NSWindow, NSControlTextEditingDelegate {
    @IBOutlet var scrollView: NSScrollView!
    @IBOutlet private var header: ViewAllowsVibrancy!
    @IBOutlet var table: PrTable!
    @IBOutlet var filter: NSSearchField!
    @IBOutlet var refreshMenuItem: NSMenuItem!

    var statusItem: NSStatusItem?

    var messageView: MessageView? {
        didSet {
            if let oldValue {
                oldValue.removeFromSuperview()
            }
            if let messageView {
                contentView?.addSubview(messageView)
            }
        }
    }

    var dataSource: DataSource! {
        didSet {
            if let newFilter = Settings.filter(for: dataSource.uniqueIdentifier) {
                filter.stringValue = newFilter
            }
            table.dataSource = dataSource
            table.delegate = dataSource
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        contentView?.wantsLayer = true

        isOpaque = false
        backgroundColor = .clear
        contentView?.layer?.maskedCorners = [.layerMaxXMinYCorner, .layerMinXMinYCorner]
        contentView?.layer?.cornerRadius = 5

        let w = NSVisualEffectView(frame: header.bounds)
        w.autoresizingMask = [.height, .width]
        w.blendingMode = .behindWindow
        w.state = .active
        header.addSubview(w, positioned: .below, relativeTo: filter)

        NotificationCenter.default.addObserver(self, selector: #selector(refreshUpdate), name: .SyncProgressUpdate, object: nil)
    }

    @objc func buttonSelected() {
        if isVisible {
            closeMenu()
        } else {
            app.show(menu: self)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        app.controlTextDidChange(obj)
    }

    func updateVibrancy() {
        switch app.theme {
        case .light:
            appearance = NSAppearance(named: .vibrantLight)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }
    }

    func statusItemViewSelected() {
        if isVisible {
            closeMenu()
        } else {
            app.show(menu: self)
        }
    }

    func hideStatusItem() {
        if let s = statusItem {
            s.statusBar?.removeStatusItem(s)
            statusItem = nil
        }
    }

    override var canBecomeKey: Bool {
        true
    }

    @objc private func menuWillOpen(_: NSMenu) {
        if API.isRefreshing {
            refreshUpdate()
        } else {
            let lastSync = API.lastSuccessfulSyncAt
            refreshMenuItem.title = " Refresh (\(lastSync))"
        }
    }

    @objc private func refreshUpdate() {
        let operation = API.currentOperationName
        refreshMenuItem.title = " Refresh: " + operation
    }

    func scrollToTop() {
        table.scrollToBeginningOfDocument(nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @IBAction private func markAllReadSelected(_: NSMenuItem) {
        app.markAllReadSelected(from: self)
    }

    @IBAction private func preferencesSelected(_: NSMenuItem) {
        app.preferencesSelected()
    }

    @IBAction func refreshSelected(_: NSMenuItem) {
        if Repo.countItems(in: DataManager.main) == 0 {
            app.preferencesSelected()
            return
        }
        Task {
            await app.startRefresh()
        }
    }

    @IBAction private func aboutSelected(_: NSMenuItem) {
        app.showAboutWindow()
    }

    func size(andShow makeVisible: Bool) {
        guard let siv = statusItem?.statusView,
              let windowFrame = siv.window?.frame,
              let screenFrame = NSScreen.screens.first(where: { $0.frame.contains(windowFrame) })?.visibleFrame
        else { return }

        var menuHeight: CGFloat = 54
        let rowCount = table.numberOfRows
        var screenHeight = screenFrame.size.height

        if NSApp.presentationOptions.contains(.autoHideMenuBar) {
            screenHeight -= 25
        }

        if rowCount == 0 {
            menuHeight += 95
        } else {
            for f in 0 ..< rowCount {
                let rowView = table.view(atColumn: 0, row: f, makeIfNecessary: true)!
                rowView.layoutSubtreeIfNeeded()
                menuHeight += rowView.frame.size.height
                if menuHeight >= screenHeight {
                    break
                }
            }
        }

        var menuWidth = MENU_WIDTH
        if #available(macOS 11.0, *) {
            if rowCount > 0 {
                menuWidth += table.layoutMarginsGuide.frame.origin.x * 2
            }
        }

        var menuLeft = windowFrame.origin.x
        let rightSide = screenFrame.origin.x + screenFrame.size.width
        let overflow = (menuLeft + menuWidth) - rightSide
        if overflow > 0 {
            menuLeft -= overflow
        }

        var bottom = screenFrame.origin.y
        if menuHeight < screenHeight {
            bottom += screenHeight - menuHeight
        } else {
            menuHeight = screenHeight
        }

        setFrame(CGRect(x: menuLeft, y: bottom, width: menuWidth, height: menuHeight), display: false, animate: false)

        if makeVisible {
            siv.highlighted = true
            table.deselectAll(nil)
            app.openingWindow = true
            level = .mainMenu
            makeKeyAndOrderFront(self)
            NSApp.activate(ignoringOtherApps: true)
            app.openingWindow = false

        } else if statusItem == nil {
            closeMenu()
        }
    }

    func reload() {
        messageView = nil
        let filterString = filter.stringValue
        dataSource.reloadData(filter: filterString)
        table.reloadData()
        Settings.setFilter(to: filterString, for: dataSource.uniqueIdentifier)
    }

    func closeMenu() {
        if isVisible {
            if let siv = statusItem?.statusView {
                siv.highlighted = false
            }
            table.deselectAll(nil)
            orderOut(nil)
        }
    }

    func focusedItem(blink: Bool) -> ListableItem? {
        let row = table.selectedRow
        var i: ListableItem?
        if row >= 0 {
            i = dataSource.itemAtRow(row)
            if blink {
                table.deselectAll(nil)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)
                    let i = IndexSet(integer: row)
                    table.selectRowIndexes(i, byExtendingSelection: false)
                }
            }
        }
        return i
    }
}
