
import WatchKit
import WatchConnectivity

final class PRListController: CommonController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet var statusLabel: WKInterfaceLabel!

	private var section: PullRequestSection!
	private var type: String!
	private var selectedIndex: Int?

	private let PAGE_SIZE = 50
	private var lastCount: Int = 0
	private var loadingBuffer: [[String : AnyObject]]?
	private var loading = false

	override func awakeWithContext(context: AnyObject?) {

		let c = context as! [NSObject : AnyObject]
		section = PullRequestSection(rawValue: c[SECTION_KEY] as! Int)
		type = c[TYPE_KEY] as! String

		_table = table
		_statusLabel = statusLabel
		super.awakeWithContext(context)

		setTitle(section.watchMenuName())
	}

	override func requestData(command: String?) {
		if !loading {
			_requestData(command)
			loading = true
		}
	}

	private func _requestData(command: String?) {

		if lastCount >= PAGE_SIZE {
			self.showStatus("Refreshing...", hideTable: true)
		}

		var params = ["list": "item_list", "type": type, "sectionIndex": NSNumber(integer: section.rawValue), "count": NSNumber(integer: PAGE_SIZE)]
		if let command = command {
			params["command"] = command
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

	override func updateFromData(response: [NSString : AnyObject]) {

		let page = response["result"] as! [[String : AnyObject]]

		loadingBuffer?.appendContentsOf(page)
		if page.count == PAGE_SIZE {
			NSOperationQueue.mainQueue().addOperationWithBlock { [weak self] in
				self?._requestData(nil)
				self?.showStatus("Loading \(self?.loadingBuffer?.count ?? 0) items...", hideTable: true)
			}
			return
		}

		if let l = loadingBuffer {

			if lastCount == 0 {
				table.setNumberOfRows(l.count, withRowType: "PRRow")
			} else if lastCount < l.count {
				table.removeRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(0, l.count-lastCount)))
			} else if lastCount > l.count {
				table.insertRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(0, lastCount-l.count)), withRowType: "PRRow")
			}

			lastCount = l.count

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
		showStatus("Refreshing", hideTable: true)
		requestData("refresh")
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		loading = false
		selectedIndex = rowIndex
		let row = table.rowControllerAtIndex(rowIndex) as! PRRow
		let key = (type=="prs" ? PULL_REQUEST_KEY : ISSUE_KEY)
		pushControllerWithName("DetailController", context: [ key: row.itemId! ])
	}
}
