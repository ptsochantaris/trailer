import Cocoa

final class TrailerCell: NSTableCellView {
    private static let statusAttributes: [NSAttributedString.Key: Any] = {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 17

        return [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .paragraphStyle: paragraphStyle
        ]
    }()

    private let detailFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    private let dataItemId: NSManagedObjectID

    private let title = CenterTextField(frame: .zero)
    private let labels = CenterTextField(frame: .zero)
    private let reviews = CenterTextField(frame: .zero)
    private let subtitle = CenterTextField(frame: .zero)
    private var trackingArea: NSTrackingArea?

    init(item: ListableItem, settings: Settings.Cache) {
        dataItemId = item.objectID

        super.init(frame: .zero)

        let faded = item.shouldSkipNotifications

        var W = MENU_WIDTH - LEFTPADDING - app.scrollBarWidth

        let showUnpin = item.condition != ItemCondition.open.rawValue
        if showUnpin { W -= REMOVE_BUTTON_WIDTH } else { W -= 4 }

        let showAvatar = !settings.hideAvatars
        let shift: CGFloat = showAvatar ? AVATAR_SIZE + AVATAR_PADDING : -4
        W -= shift

        var y: CGFloat = 8
        let widthLimit = CGSize(width: W, height: .greatestFiniteMagnitude)

        func append(_ field: CenterTextField) {
            let a = field.attributedStringValue
            if a.length == 0 { return }
            let height = a.boundingRect(with: widthLimit, options: stringDrawingOptions).integral.size.height + 2
            field.frame = CGRect(x: LEFTPADDING + shift, y: y, width: W, height: height)
            addSubview(field)
            y += height
        }

        if let pullRequest = item.asPr, item.section.shouldListStatuses(settings: settings) {
            let statuses = pullRequest.displayedStatusLines(settings: settings).reversed()
            if !statuses.isEmpty {
                for status in statuses {
                    let statusLabel = LinkField(frame: .zero)
                    statusLabel.targetUrl = status.targetUrl
                    statusLabel.needsCommand = !settings.makeStatusItemsSelectable
                    statusLabel.attributedStringValue = NSAttributedString(string: status.displayText, attributes: TrailerCell.statusAttributes)
                    statusLabel.textColor = status.colorForDisplay
                    statusLabel.alphaValue = faded ? DISABLED_FADE : 1.0
                    append(statusLabel)
                }
                y += 1
            }
        }

        updateText(for: item, settings: settings)
        append(subtitle)
        append(reviews)
        y += 1
        append(labels)
        append(title)

        let cellPadding: CGFloat = 5
        y += cellPadding

        let cellHeight = y

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: MENU_WIDTH),
            heightAnchor.constraint(equalToConstant: cellHeight)
        ])

        let accesoryCenterY = y - AVATAR_SIZE * 0.5 - cellPadding - 7

        let hasNewCommits = item.asPr?.hasNewCommits ?? false
        addCounts(total: item.totalComments, unread: item.unreadComments, alert: hasNewCommits, faded: faded, centerY: accesoryCenterY)

        if showAvatar {
            let avatarRect = CGRect(x: LEFTPADDING, y: accesoryCenterY - AVATAR_SIZE * 0.5, width: AVATAR_SIZE, height: AVATAR_SIZE)
            let userImage = AvatarView(frame: avatarRect, url: item.userAvatarUrl)
            userImage.alphaValue = faded ? DISABLED_FADE : 1
            addSubview(userImage)
        }

        if showUnpin {
            let pinRect = CGRect(x: LEFTPADDING + W + shift, y: floor((cellHeight - 24) * 0.5), width: REMOVE_BUTTON_WIDTH - 10, height: 24)
            let unpin = NSButton(frame: pinRect)
            unpin.title = "Remove"
            unpin.target = self
            unpin.action = #selector(unPinSelected)
            unpin.setButtonType(.momentaryLight)
            unpin.bezelStyle = .roundRect
            unpin.font = NSFont.systemFont(ofSize: 10)
            addSubview(unpin)
        }

        if faded {
            title.alphaValue = DISABLED_FADE
            subtitle.alphaValue = DISABLED_FADE
            reviews.alphaValue = DISABLED_FADE
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func unPinSelected() {
        if let associatedDataItem {
            app.unPinSelected(for: associatedDataItem)
        }
    }

    override func mouseEntered(with _: NSEvent?) {
        if !app.isManuallyScrolling { selected = true }
    }

    override func mouseExited(with _: NSEvent?) {
        selected = false
    }

    private func updateText(for item: ListableItem, settings: Settings.Cache) {
        title.attributedStringValue = item.title(with: titleFont, labelFont: detailFont, titleColor: .controlTextColor, numberColor: .secondaryLabelColor, settings: settings)
        labels.attributedStringValue = item.labelsAttributedString(labelFont: detailFont, settings: settings) ?? emptyAttributedString
        reviews.attributedStringValue = item.asPr?.reviewsAttributedString(labelFont: detailFont, settings: settings) ?? emptyAttributedString
        subtitle.attributedStringValue = item.subtitle(with: detailFont, lightColor: .tertiaryLabelColor, darkColor: .secondaryLabelColor, separator: "   ", settings: settings)
    }

    var selected = false {
        didSet {
            guard let table = app.visibleWindow?.table else { return }

            if let associatedDataItem {
                updateText(for: associatedDataItem, settings: Settings.cache)
            }

            if selected {
                table.selectRowIndexes(IndexSet(integer: table.row(for: self)), byExtendingSelection: false)
            } else {
                table.deselectRow(table.row(for: self))
            }

            highlight(selected)
        }
    }

    @objc private func openRepo() {
        if let u = associatedDataItem?.repo.webUrl, let url = URL(string: u) {
            openLink(url)
        }
    }

    @objc private func copyToClipboard() {
        if let s = associatedDataItem?.webUrl {
            let p = NSPasteboard.general
            p.clearContents()
            p.declareTypes([NSPasteboard.PasteboardType.string], owner: self)
            p.setString(s, forType: NSPasteboard.PasteboardType.string)
        }
    }

    @objc private func copyNumberToClipboard() {
        if let a = associatedDataItem, let name = a.repo.fullName {
            let p = NSPasteboard.general
            p.clearContents()
            p.declareTypes([NSPasteboard.PasteboardType.string], owner: self)
            p.setString("\(name)#\(a.number)", forType: NSPasteboard.PasteboardType.string)
        }
    }

    @objc private func copyBranchToClipboard() {
        if let a = associatedDataItem?.asPr, let name = a.headRefName {
            let p = NSPasteboard.general
            p.clearContents()
            p.declareTypes([NSPasteboard.PasteboardType.string], owner: self)
            p.setString(name, forType: NSPasteboard.PasteboardType.string)
        }
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        guard let associatedDataItem else {
            return nil
        }

        let title = associatedDataItem.contextMenuTitle

        let m = NSMenu(title: title)
        m.addItem(withTitle: title, action: #selector(copyNumberToClipboard), keyEquivalent: "")

        if let subtitle = associatedDataItem.contextMenuSubtitle {
            let c = m.addItem(withTitle: subtitle, action: #selector(copyBranchToClipboard), keyEquivalent: "c")
            c.keyEquivalentModifierMask = [.command, .option]
        }

        m.addItem(NSMenuItem.separator())

        for a in associatedDataItem.contextActions {
            switch a {
            case .copy:
                let c = m.addItem(withTitle: a.title, action: #selector(copyToClipboard), keyEquivalent: "c")
                c.keyEquivalentModifierMask = [.command]

            case .openRepo:
                let c = m.addItem(withTitle: a.title, action: #selector(openRepo), keyEquivalent: "o")
                c.keyEquivalentModifierMask = [.command]

            case .markRead:
                let c = m.addItem(withTitle: a.title, action: #selector(markReadSelected), keyEquivalent: "a")
                c.keyEquivalentModifierMask = [.command]

            case .markUnread:
                let c = m.addItem(withTitle: a.title, action: #selector(markUnreadSelected), keyEquivalent: "a")
                c.keyEquivalentModifierMask = [.command]

            case .wake:
                let c = m.addItem(withTitle: a.title, action: #selector(wakeUpSelected), keyEquivalent: "0")
                c.keyEquivalentModifierMask = [.command, .option]

            case let .snooze(presets):
                let s = NSMenu(title: "Snooze")
                var count = 1
                for i in presets {
                    let keyEquivalent = count < 10 ? "\(count)" : ""
                    let smi = s.addItem(withTitle: i.listDescription, action: #selector(snoozeSelected), keyEquivalent: keyEquivalent)
                    smi.representedObject = i.objectID
                    if !keyEquivalent.isEmpty {
                        smi.keyEquivalentModifierMask = [.command, .option]
                        count += 1
                    }
                }
                s.addItem(withTitle: "Configure…", action: #selector(snoozeConfigSelected), keyEquivalent: "")

                let c = m.addItem(withTitle: "Snooze…", action: nil, keyEquivalent: "")
                c.submenu = s

            case .mute:
                let c = m.addItem(withTitle: a.title, action: #selector(muteSelected), keyEquivalent: "m")
                c.keyEquivalentModifierMask = [.command]

            case .unmute:
                let c = m.addItem(withTitle: a.title, action: #selector(unMuteSelected), keyEquivalent: "m")
                c.keyEquivalentModifierMask = [.command]

            case .remove:
                m.addItem(withTitle: a.title, action: #selector(removeSelected), keyEquivalent: "")
            }
        }

        return m
    }

    @objc private func removeSelected() {
        if let associatedDataItem {
            associatedDataItem.sectionIndex = Section.hidden(cause: .unknown).sectionIndex
            Task {
                await app.updateRelatedMenus(for: associatedDataItem) // saveAndRequestMenuUpdate won't work in this case
                DataManager.main.delete(associatedDataItem)
                await DataManager.saveDB()
            }
        }
    }

    @objc private func snoozeConfigSelected() {
        app.showPreferencesWindow(andSelect: 6)
    }

    @objc private func snoozeSelected(_ sender: NSMenuItem) {
        if let associatedDataItem, let oid = sender.representedObject as? NSManagedObjectID, let snoozeItem = try? DataManager.main.existingObject(with: oid) as? SnoozePreset {
            associatedDataItem.snooze(using: snoozeItem, settings: Settings.cache)
            saveAndRequestMenuUpdate(associatedDataItem)
        }
    }

    @objc private func wakeUpSelected() {
        if let associatedDataItem {
            associatedDataItem.wakeUp(settings: Settings.cache)
            saveAndRequestMenuUpdate(associatedDataItem)
        }
    }

    @objc private func markReadSelected() {
        if let associatedDataItem {
            associatedDataItem.catchUpWithComments(settings: Settings.cache)
            saveAndRequestMenuUpdate(associatedDataItem)
        }
    }

    @objc private func markUnreadSelected() {
        if let associatedDataItem {
            associatedDataItem.latestReadCommentDate = .distantPast
            associatedDataItem.postProcess(settings: Settings.cache)
            saveAndRequestMenuUpdate(associatedDataItem)
        }
    }

    @objc private func muteSelected() {
        if let associatedDataItem {
            associatedDataItem.setMute(to: true, settings: Settings.cache)
            saveAndRequestMenuUpdate(associatedDataItem)
        }
    }

    @objc private func unMuteSelected() {
        if let associatedDataItem {
            associatedDataItem.setMute(to: false, settings: Settings.cache)
            saveAndRequestMenuUpdate(associatedDataItem)
        }
    }

    private func saveAndRequestMenuUpdate(_ item: ListableItem) {
        Task {
            await DataManager.saveDB()
            await app.updateRelatedMenus(for: item)
        }
    }

    var associatedDataItem: ListableItem? {
        try? DataManager.main.existingObject(with: dataItemId) as? ListableItem
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let t = NSTrackingArea(rect: bounds, options: [NSTrackingArea.Options.mouseEnteredAndExited, NSTrackingArea.Options.activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t

        if let mouseLocation = window?.mouseLocationOutsideOfEventStream {
            let localLocation = convert(mouseLocation, to: self)
            if bounds.contains(localLocation), !selected {
                mouseEntered(with: nil)
            } else if selected {
                mouseExited(with: nil)
            }
        }
    }

    //////////////////////////// Counts

    private var countBackground: FilledView?
    private var newBackground: FilledView?
    private var countView: CenterTextField?

    func addCounts(total: Int, unread: Int, alert: Bool, faded: Bool, centerY: CGFloat) {
        if total == 0 && !alert {
            return
        }

        let pCenter = NSMutableParagraphStyle()
        pCenter.alignment = .center

        let countString = NSAttributedString(string: numberFormatter.string(for: total)!, attributes: [
            NSAttributedString.Key.font: NSFont.menuFont(ofSize: 11),
            NSAttributedString.Key.foregroundColor: NSColor.controlTextColor,
            NSAttributedString.Key.paragraphStyle: pCenter
        ])

        var height: CGFloat = 20
        var width = max(height, countString.size().width + 10)
        var left = (LEFTPADDING - width) * 0.5

        let c = FilledView(frame: CGRect(x: left, y: centerY - height * 0.5, width: width, height: height).integral)
        c.cornerRadius = floor(height / 2.0)

        countView = CenterTextField(frame: c.bounds)
        countView!.vibrant = false
        countView!.attributedStringValue = countString
        if faded { countView!.alphaValue = DISABLED_FADE }
        c.addSubview(countView!)
        addSubview(c)

        countBackground = c

        if unread > 0 || alert {
            let alertText = unread == 0 ? "!" : numberFormatter.string(for: unread)!
            let alertString = NSAttributedString(string: alertText, attributes: [
                NSAttributedString.Key.font: NSFont.menuFont(ofSize: 8),
                NSAttributedString.Key.foregroundColor: NSColor.white,
                NSAttributedString.Key.paragraphStyle: pCenter
            ])

            height = 14
            width = max(height, alertString.size().width + 8.0)
            left -= width * 0.5

            let cc = FilledView(frame: CGRect(x: left, y: centerY, width: width, height: height).integral)
            cc.cornerRadius = floor(height * 0.5)

            let alertCount = CenterTextField(frame: cc.bounds)
            alertCount.vibrant = false
            alertCount.attributedStringValue = alertString
            if faded { alertCount.alphaValue = DISABLED_FADE }
            cc.addSubview(alertCount)
            addSubview(cc)

            newBackground = cc
        }

        highlight(false)
    }

    private func highlight(_ on: Bool) {
        guard let c = countBackground else { return }

        let color: NSColor
        switch app.theme {
        case .light:
            color = .controlTextColor
            newBackground?.backgroundColor = NSColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1.0)
            c.backgroundColor = NSColor(red: 0.92, green: 0.92, blue: 0.92, alpha: 1.0)

        case .dark:
            color = on ? .black : NSColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1.0)
            newBackground?.backgroundColor = NSColor(red: 1.0, green: 0.1, blue: 0.1, alpha: 1.0)
            c.backgroundColor = on ? NSColor.white.withAlphaComponent(DISABLED_FADE) : NSColor.controlShadowColor
        }

        if let a = countView?.attributedStringValue.mutableCopy() as? NSMutableAttributedString {
            a.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: NSRange(location: 0, length: a.length))
            countView?.attributedStringValue = a
        }
    }
}
