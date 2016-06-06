
import WatchKit
import WatchConnectivity

final class PRListController: CommonController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet var statusLabel: WKInterfaceLabel!

	private var sectionIndex: Int!
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

	override func awakeWithContext(context: AnyObject?) {

		let c = context as! [NSObject : AnyObject]
		sectionIndex = c[SECTION_KEY] as! Int
		type = c[TYPE_KEY] as! String
		onlyUnread = c[UNREAD_KEY] as! Bool

		let g = c[GROUP_KEY] as! String
		groupLabel = g

		let a = c[API_URI_KEY] as! String
		apiServerUri = a

		_table = table
		_statusLabel = statusLabel
		super.awakeWithContext(context)

		if let s = Section(rawValue: sectionIndex) {
			setTitle(s.watchMenuName())
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

	private func _requestData(command: String?) {

		var params = ["list": "item_list",
		              "type": type,
		              "group": groupLabel!,
		              "apiUri": apiServerUri!,
		              "sectionIndex": NSNumber(integer: sectionIndex),
		              "onlyUnread": NSNumber(bool: onlyUnread),
		              "count": NSNumber(integer: PAGE_SIZE)]

		if let c = command {
			params["command"] = c
		}
		if let l = loadingBuffer {
			params["from"] = NSNumber(integer: l.count)
		} else {
			loadingBuffer = [[String : AnyObject]]()
			params["from"] = NSNumber(integer: 0)
		}

		sendRequest(params)
	}

	override func loadingFailed(error: NSError) {
		super.loadingFailed(error)
		loadingBuffer = nil
	}

	private var progressiveLoading = false

	override func updateFromData(response: [NSString : AnyObject]) {

		let page = response["result"] as! [[String : AnyObject]]

		loadingBuffer?.appendContentsOf(page)
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
				table.removeRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(0, C-lastCount)))
			} else if lastCount > C {
				table.insertRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(0, lastCount-C)), withRowType: "PRRow")
			}

			lastCount = C

			var index = 0
			for itemData in l {
				if let c = table.rowControllerAtIndex(index) as? PRRow {
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
				table.scrollToRowAtIndex(s)
				selectedIndex = nil
			}

			loadingBuffer = nil
		}
	}

	@IBAction func markAllReadSelected() {
		loading = false
		showStatus("Marking items as read", hideTable: true)
		if type=="prs" {
			requestData("markAllPrsRead")
		} else {
			requestData("markAllIssuesRead")
		}
	}

	@IBAction func refreshSelected() {
		loading = false
		showStatus("Refreshing...", hideTable: true)
		requestData("refresh")
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		loading = false
		selectedIndex = rowIndex
		let row = table.rowControllerAtIndex(rowIndex) as! PRRow
		let key = (type=="prs" ? PULL_REQUEST_KEY : ISSUE_KEY)
		pushControllerWithName("DetailController", context: [ key: row.itemId! ])
		if lastCount >= PAGE_SIZE {
			self.showStatus("Loading...", hideTable: true)
		}
	}
}
