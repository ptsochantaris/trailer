import WatchConnectivity
import WatchKit

final class SectionController: CommonController {
    ////////////////////// List

    @IBOutlet private var table: WKInterfaceTable!
    @IBOutlet private var statusLabel: WKInterfaceLabel!

    @IBOutlet private var clearMergedButton: WKInterfaceButton!
    @IBOutlet private var clearClosedButton: WKInterfaceButton!
    @IBOutlet private var markReeadButton: WKInterfaceButton!
    @IBOutlet private var startRefreshButton: WKInterfaceButton!
    @IBOutlet private var updatedLabel: WKInterfaceLabel!

    private var rowControllers = [PopulatableRow]()

    override func awake(withContext context: Any?) {
        _statusLabel = statusLabel
        _table = table
        super.awake(withContext: context)
        updateUI()
    }

    override var showLoadingFeedback: Bool {
        false
    }

    override func requestData(command: String?) {
        if let c = command {
            send(request: ["command": c])
        } else {
            send(request: ["command": "overview", "list": "overview"])
        }
    }

    override func table(_: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
        let r = rowControllers[rowIndex] as! SectionRow
        let section = r.section?.rawValue ?? -1
        let list = [
            SECTION_KEY: section,
            TYPE_KEY: r.type!,
            UNREAD_KEY: section == -1,
            GROUP_KEY: r.groupLabel!,
            API_URI_KEY: r.apiServerUri!
        ] as [String: Any]
        pushController(withName: "ListController", context: list)
    }

    override func update(from response: [AnyHashable: Any]) {
        Task { @MainActor in
            if let overview = response["result"] as? [AnyHashable: Any] {
                ExtensionDelegate.storedOverview = overview
            }
            updateUI()
            startRefreshButton.setHidden(false)
            updatedLabel.setHidden(false)
        }
    }

    private func sectionFrom(apiName: String) -> Section {
        let index = Section.apiTitles.firstIndex(of: apiName)!
        return Section(rawValue: index)!
    }

    func resetUI() {
        if table.numberOfRows > 0 {
            table.scrollToRow(at: 0)
        }
    }

    private func updateUI() {
        rowControllers.removeAll(keepingCapacity: false)

        func addSectionsFor(_ entry: [AnyHashable: Any], itemType: String, label: String, apiServerUri: String, showEmptyDescriptions: Bool) {
            let items = entry[itemType] as! [AnyHashable: Any]
            let totalItems = items["total"] as! Int
            var showClearClosed = false
            var showClearMerged = false
            if totalItems > 0 {
                let pt = TitleRow()
                pt.prRelated = itemType == "prs"
                pt.label = label
                rowControllers.append(pt)
                var totalUnread = 0
                for itemSection in Section.apiTitles {
                    switch itemSection {
                    case Section.none.apiName:
                        continue
                    case Section.closed.apiName:
                        showClearClosed = true
                    case Section.merged.apiName:
                        showClearMerged = true
                    default: break
                    }

                    if let section = items[itemSection] as? [AnyHashable: Any], let count = section["total"] as? Int, let unread = section["unread"] as? Int, count > 0 {
                        let s = SectionRow()
                        s.section = sectionFrom(apiName: itemSection)
                        s.totalCount = count
                        s.unreadCount = unread
                        s.type = itemType
                        s.groupLabel = label
                        s.apiServerUri = apiServerUri
                        rowControllers.append(s)

                        totalUnread += unread
                    }
                }
                if totalUnread > 0 {
                    let s = SectionRow()
                    s.section = nil
                    s.totalCount = 0
                    s.unreadCount = totalUnread
                    s.type = itemType
                    s.groupLabel = label
                    s.apiServerUri = apiServerUri
                    rowControllers.append(s)
                }
                markReeadButton.setHidden(totalUnread == 0)

            } else if showEmptyDescriptions {
                let error = (items["error"] as? String) ?? ""
                let pt = TitleRow()
                pt.label = "\(label): \(error)"
                rowControllers.append(pt)
                markReeadButton.setHidden(true)

            } else {
                markReeadButton.setHidden(true)
            }

            clearMergedButton.setHidden(!showClearMerged)
            clearClosedButton.setHidden(!showClearClosed)
        }

        let session = WCSession.default
        guard let result = ExtensionDelegate.storedOverview else {
            if session.iOSDeviceNeedsUnlockAfterRebootForReachability {
                show(status: "To re-establish your connection, please unlock your iOS device.", hideTable: true)
            } else {
                switch session.activationState {
                case .inactive:
                    show(status: "Not connected to Trailer on your iOS device.", hideTable: true)
                case .notActivated:
                    show(status: "Connecting…", hideTable: true)
                case .activated:
                    show(status: "Loading…", hideTable: true)
                @unknown default:
                    break
                }
            }
            return
        }

        guard let views = result["views"] as? [[AnyHashable: Any]] else {
            show(status: "There is no data from Trailer on your iOS device yet. Please launch it once and configure your settings.", hideTable: true)
            return
        }

        if let update = result["lastUpdated"] as? Date {
            let agoString = agoFormat(prefix: "Updated", since: update)
            updatedLabel.setText(agoString)
        }

        let showEmptyDescriptions = views.count == 1

        for v in views {
            let label = v["title"] as! String
            let apiServerUri = v["apiUri"] as! String
            addSectionsFor(v, itemType: "prs", label: label, apiServerUri: apiServerUri, showEmptyDescriptions: showEmptyDescriptions)
            addSectionsFor(v, itemType: "issues", label: label, apiServerUri: apiServerUri, showEmptyDescriptions: showEmptyDescriptions)
        }

        table.setRowTypes(rowControllers.map {
            String(describing: type(of: $0))
        })

        var index = 0
        for rc in rowControllers {
            if let c = table.rowController(at: index) as? PopulatableRow {
                c.populate(from: rc)
            }
            index += 1
        }

        show(status: "", hideTable: false)
    }

    override func show(status: String, hideTable: Bool) {
        if hideTable {
            startRefreshButton.setHidden(true)
            clearMergedButton.setHidden(true)
            markReeadButton.setHidden(true)
            clearClosedButton.setHidden(true)
            updatedLabel.setHidden(true)
        }
        super.show(status: status, hideTable: hideTable)
    }

    @IBAction private func clearMergedSelected() {
        show(status: "Clearing merged", hideTable: true)
        requestData(command: "clearAllMerged")
    }

    @IBAction private func clearClosedSelected() {
        show(status: "Clearing closed", hideTable: true)
        requestData(command: "clearAllClosed")
    }

    @IBAction private func markAllReadSelected() {
        show(status: "Marking all as read", hideTable: true)
        requestData(command: "markEverythingRead")
    }

    @IBAction private func refreshSelected() {
        show(status: "Starting refresh", hideTable: true)
        requestData(command: "refresh")
    }
}
