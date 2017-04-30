
import WatchKit
import WatchConnectivity

final class PRListController: CommonController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet var statusLabel: WKInterfaceLabel!

	private var sectionIndex: Int64!
	private var type: String!
	private var selectedIndex: Int?

	private let PAGE_SIZE = 50

	// View criterion
	private var groupLabel: String?
	private var apiServerUri: String?

	private var onlyUnread = false
	private var lastCount = 0
	private var loadingBuffer: [[AnyHashable : Any]]?
	private var loading = false

	override func awake(withContext context: Any?) {

		let c = context as! [AnyHashable : Any]
		sectionIndex = c[SECTION_KEY] as! Int64
		type = c[TYPE_KEY] as! String
		onlyUnread = c[UNREAD_KEY] as! Bool

		let g = c[GROUP_KEY] as! String
		groupLabel = g

		let a = c[API_URI_KEY] as! String
		apiServerUri = a

		_table = table
		_statusLabel = statusLabel
		super.awake(withContext: context)

		if let s = Section(sectionIndex) {
			setTitle(s.watchMenuName)
		} else {
			setTitle("All Unread")
		}
	}

	override func requestData(command: String?) {
		if !loading {
			_requestData(command)
			loading = true
		}
	}

	private func _requestData(_ command: String?) {

		var params: [String: Any] = [ "list": "item_list",
									  "type": type,
									  "group": groupLabel!,
									  "apiUri": apiServerUri!,
									  "sectionIndex": sectionIndex,
									  "onlyUnread": onlyUnread,
									  "count": PAGE_SIZE ]

		if let c = command {
			params["command"] = c
			if c == "markItemsRead" {
				var itemIds = [String]()
				for i in 0..<table.numberOfRows {
					let controller = table.rowController(at: i) as! PRRow
					if controller.hasUnread! {
						itemIds.append(controller.itemId!)
					}
				}
				params["itemUris"] = itemIds
			}
		}
		if let l = loadingBuffer {
			params["from"] = l.count
		} else {
			loadingBuffer = [[AnyHashable : Any]]()
			params["from"] = 0
		}

		send(request: params)
	}

	override func loadingFailed(with error: Error) {
		super.loadingFailed(with: error)
		loadingBuffer = nil
	}

	private var progressiveLoading = false

	override func update(from response: [AnyHashable : Any]) {

		let page = response["result"] as! [[AnyHashable : Any]]

		loadingBuffer?.append(contentsOf: page)
		if page.count == PAGE_SIZE {
			atNextEvent(self) { S in
				S._requestData(nil)
				S.show(status: "Loaded \(S.loadingBuffer?.count ?? 0) items…", hideTable: true)
				S.progressiveLoading = true
			}
			return
		}

		if let l = loadingBuffer {
			if progressiveLoading {
				show(status: "Loaded \(l.count) items.\n\nDisplaying…", hideTable: true)
				atNextEvent(self) { S in
					S.completeLoadingBuffer()
				}
			} else {
				completeLoadingBuffer()
			}
		}
	}

	private func completeLoadingBuffer() {

		if let l = loadingBuffer {
			let C = l.count

			if lastCount == 0 {
				table.setNumberOfRows(C, withRowType: "PRRow")
			} else if lastCount < C {
				table.removeRows(at: IndexSet(integersIn: NSMakeRange(0, C-lastCount).toRange()!))
			} else if lastCount > C {
				table.insertRows(at: IndexSet(integersIn: NSMakeRange(0, lastCount-C).toRange()!), withRowType: "PRRow")
			}

			lastCount = C

			var index = 0
			for itemData in l {
				if let c = table.rowController(at: index) as? PRRow {
					c.populate(from: itemData)
				}
				index += 1
			}

			if l.count == 0 {
				show(status: "There are no items in this section", hideTable: true)
			} else {
				show(status: "", hideTable: false)
			}

			if let s = selectedIndex {
				table.scrollToRow(at: s)
				selectedIndex = nil
			}

			loadingBuffer = nil
		}
	}

	@IBAction func markAllReadSelected() {
		loading = false
		show(status: "Marking items as read", hideTable: true)
		requestData(command: "markItemsRead")
	}

	@IBAction func refreshSelected() {
		loading = false
		show(status: "Refreshing…", hideTable: true)
		requestData(command: "refresh")
	}

	override func table(_ table: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
		loading = false
		selectedIndex = rowIndex
		let row = table.rowController(at: rowIndex) as! PRRow
		pushController(withName: "DetailController", context: [ ITEM_KEY: row.itemId! ])
		if lastCount >= PAGE_SIZE {
			self.show(status: "Loading…", hideTable: true)
		}
	}
}
