
import WatchKit
import WatchConnectivity

final class PRListController: CommonController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet var statusLabel: WKInterfaceLabel!

	private var section: PullRequestSection!
	private var type: String!
	private var selectedIndex: Int?
	private var lastCount: Int = 0

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
		var params = ["list": "item_list", "type": type, "sectionIndex": NSNumber(integer: section.rawValue)]
		if let command = command {
			params["command"] = command
		}
		sendRequest(params)
	}

	override func updateFromData(response: [NSString : AnyObject]) {

		let result = response["result"] as! [[String : AnyObject]]

		if lastCount == 0 {
			table.setNumberOfRows(result.count, withRowType: "PRRow")
		} else if lastCount < result.count {
			table.removeRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(0, result.count-lastCount)))
		} else if lastCount > result.count {
			table.insertRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(0, lastCount-result.count)), withRowType: "PRRow")
		}

		lastCount = result.count

		var index = 0
		for itemData in result {
			if let c = table.rowControllerAtIndex(index++) as? PRRow {
				c.populateFrom(itemData)
			}
		}

		if result.count == 0 {
			showStatus("There are no items in this section", hideTable: true)
		} else {
			showStatus("", hideTable: false)
		}

		if let s = selectedIndex {
			table.scrollToRowAtIndex(s)
			selectedIndex = nil
		}
	}

	@IBAction func markAllReadSelected() {
		showStatus("Marking items as read", hideTable: true)
		if type=="prs" {
			requestData("markAllPrsRead")
		} else {
			requestData("markAllIssuesRead")
		}
	}

	@IBAction func refreshSelected() {
		showStatus("Refreshing", hideTable: true)
		requestData("refresh")
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		selectedIndex = rowIndex
		let row = table.rowControllerAtIndex(rowIndex) as! PRRow
		let key = (type=="prs" ? PULL_REQUEST_KEY : ISSUE_KEY)
		pushControllerWithName("DetailController", context: [ key: row.itemId! ])
	}
}
