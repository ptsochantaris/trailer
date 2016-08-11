
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
	private var loadingBuffer: [[String : AnyObject]]?
	private var loading = false

	override func awake(withContext context: AnyObject?) {

		let c = context as! [NSObject : AnyObject]
		sectionIndex = (c[SECTION_KEY] as! NSNumber).int64Value
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

	override func requestData(_ command: String?) {
		if !loading {
			_requestData(command)
			loading = true
		}
	}

	private func _requestData(_ command: String?) {

		var params = ["list": "item_list",
		              "type": type,
		              "group": groupLabel!,
		              "apiUri": apiServerUri!,
		              "sectionIndex": NSNumber(value: sectionIndex),
		              "onlyUnread": NSNumber(value: onlyUnread),
		              "count": NSNumber(value: PAGE_SIZE)]

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
			params["from"] = NSNumber(value: l.count)
		} else {
			loadingBuffer = [[String : AnyObject]]()
			params["from"] = NSNumber(value: 0)
		}

		sendRequest(params)
	}

	override func loadingFailed(_ error: NSError) {
		super.loadingFailed(error)
		loadingBuffer = nil
	}

	private var progressiveLoading = false

	override func updateFromData(_ response: [NSString : AnyObject]) {

		let page = response["result"] as! [[String : AnyObject]]

		loadingBuffer?.append(contentsOf: page)
		if page.count == PAGE_SIZE {
			atNextEvent(self) { S in
				S._requestData(nil)
				S.showStatus("Loaded \(S.loadingBuffer?.count ?? 0) items...", hideTable: true)
				S.progressiveLoading = true
			}
			return
		}

		if let l = loadingBuffer {
			if progressiveLoading {
				showStatus("Loaded \(l.count) items.\n\nDisplaying...", hideTable: true)
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
					c.populateFrom(itemData)
				}
				index += 1
			}

			if l.count == 0 {
				showStatus("There are no items in this section", hideTable: true)
			} else {
				showStatus("", hideTable: false)
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
		showStatus("Marking items as read", hideTable: true)
		requestData("markItemsRead")
	}

	@IBAction func refreshSelected() {
		loading = false
		showStatus("Refreshing...", hideTable: true)
		requestData("refresh")
	}

	override func table(_ table: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
		loading = false
		selectedIndex = rowIndex
		let row = table.rowController(at: rowIndex) as! PRRow
		pushController(withName: "DetailController", context: [ ITEM_KEY: row.itemId! ])
		if lastCount >= PAGE_SIZE {
			self.showStatus("Loading...", hideTable: true)
		}
	}
}
