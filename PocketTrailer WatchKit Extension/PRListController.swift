import WatchConnectivity
import WatchKit

let allowedClasses = [NSArray.self, NSDictionary.self, NSMutableAttributedString.self, NSString.self, NSNumber.self, NSDate.self]

final class PRListController: CommonController {
    @IBOutlet private var table: WKInterfaceTable!
    @IBOutlet private var statusLabel: WKInterfaceLabel!

    @IBOutlet private var markReeadButton: WKInterfaceButton!

    private var sectionIndex: Int!
    private var type: String!
    private var selectedIndex: Int?

    private let PAGE_SIZE = 200

    // View criterion
    private var groupLabel: String?
    private var apiServerUri: String?

    private var onlyUnread = false
    private var loadingBuffer = [[AnyHashable: Any]]()
    private var loading = false
    private var sleeping = false

    override func awake(withContext context: Any?) {
        let c = context as! [AnyHashable: Any]
        sectionIndex = (c[SECTION_KEY] as! Int)
        type = (c[TYPE_KEY] as! String)
        onlyUnread = (c[UNREAD_KEY] as! Bool)

        let g = c[GROUP_KEY] as! String
        groupLabel = g

        let a = c[API_URI_KEY] as! String
        apiServerUri = a

        _table = table
        _statusLabel = statusLabel
        super.awake(withContext: context)

        let s = Section(sectionIndex: sectionIndex)
        if s == .none {
            setTitle("All Unread")
        } else {
            setTitle(s.watchMenuName)
        }
    }

    override func didDeactivate() {
        if selectedIndex == nil {
            sleeping = true
        }
        super.didDeactivate()
    }

    override func didAppear() {
        super.didAppear()
        Task { @MainActor in
            sleeping = false
        }
    }

    override func requestData(command: String?) {
        if !loading, !sleeping {
            loadingBuffer.removeAll(keepingCapacity: false)
            _requestData(command)
            loading = true
        }
    }

    override func show(status: String, hideTable: Bool) {
        if hideTable {
            markReeadButton.setHidden(true)
        }
        super.show(status: status, hideTable: hideTable)
    }

    private func _requestData(_ command: String?) {
        var params: [String: Any] = ["list": "item_list",
                                     "type": type!,
                                     "group": groupLabel!,
                                     "apiUri": apiServerUri!,
                                     "sectionIndex": sectionIndex!,
                                     "onlyUnread": onlyUnread,
                                     "count": PAGE_SIZE]

        if let c = command {
            params["command"] = c
            if c == "markItemsRead" {
                var itemIds = [String]()
                for i in 0 ..< table.numberOfRows {
                    let controller = table.rowController(at: i) as! PRRow
                    if controller.hasUnread! {
                        itemIds.append(controller.itemId!)
                    }
                }
                params["itemUris"] = itemIds
            }
        }

        params["from"] = loadingBuffer.count

        send(request: params)
    }

    override func loadingFailed(with error: Error) {
        super.loadingFailed(with: error)
        loadingBuffer.removeAll(keepingCapacity: false)
    }

    override func update(from response: [AnyHashable: Any]) {
        guard let compressedData = response["result"] as? Data,
              let uncompressedData = compressedData.data(operation: .decompress),
              let pageArray = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: uncompressedData),
              let page = pageArray as? [[String: Any]]
        else { return }
        Task { @MainActor in
            completeUpdate(from: page)
        }
    }

    private func completeUpdate(from page: [[AnyHashable: Any]]) {
        loadingBuffer.append(contentsOf: page)

        if page.count == PAGE_SIZE {
            Task { @MainActor in
                _requestData(nil)
            }

        } else {
            loading = false

            let recordDelta = loadingBuffer.count - table.numberOfRows

            if recordDelta < 0 {
                table.removeRows(at: IndexSet(integersIn: Range(uncheckedBounds: (0, -recordDelta))))
            } else if recordDelta > 0 {
                table.insertRows(at: IndexSet(integersIn: Range(uncheckedBounds: (0, recordDelta))), withRowType: "PRRow")
            }

            if loadingBuffer.isEmpty {
                show(status: "There are no items in this section", hideTable: true)
                markReeadButton.setHidden(true)

            } else {
                var index = 0
                var showRead = false
                for itemData in loadingBuffer {
                    if let c = table.rowController(at: index) as? PRRow {
                        c.populate(from: itemData)
                        if c.hasUnread {
                            showRead = true
                        }
                    }
                    index += 1
                }

                markReeadButton.setHidden(!showRead)
                show(status: "", hideTable: false)

                if let s = selectedIndex {
                    table.scrollToRow(at: s)
                    selectedIndex = nil
                }
            }

            loadingBuffer.removeAll(keepingCapacity: false)
        }

        table.setHidden(false)
    }

    @IBAction private func markAllReadSelected() {
        loading = false
        show(status: "Marking items as read", hideTable: true)
        requestData(command: "markItemsRead")
    }

    override func table(_ table: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
        loading = false
        selectedIndex = rowIndex
        let row = table.rowController(at: rowIndex) as! PRRow
        pushController(withName: "DetailController", context: [ITEM_KEY: row.itemId!])
        if table.numberOfRows >= PAGE_SIZE {
            show(status: "Loading…", hideTable: true)
        }
    }
}
