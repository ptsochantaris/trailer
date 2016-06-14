
import WatchKit
import Foundation

final class PRDetailController: CommonController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet var statusLabel: WKInterfaceLabel!

	private var rowControllers = [PopulatableRow]()
	private var itemId: String!

	override func awakeWithContext(context: AnyObject?) {
		_statusLabel = statusLabel
		_table = table

		let c = context as! [NSObject : AnyObject]
		itemId = c[ITEM_KEY] as! String

		super.awakeWithContext(context)
	}

	override func requestData(command: String?) {
		var params = ["list": "item_detail", "localId": itemId!]
		if let command = command {
			params["command"] = command
		}
		sendRequest(params)
	}

	@IBAction func refreshSelected() {
		showStatus("Refreshing...", hideTable: true)
		requestData("refresh")
	}

	@IBAction func markAllReadSelected() {
		requestData("markItemsRead")
	}

	@IBAction func openOnDeviceSelected() {
		requestData("openItem")
	}

	override func updateFromData(response: [NSString : AnyObject]) {

		table.removeRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(0, table.numberOfRows)))

		rowControllers.removeAll(keepCapacity: false)
		let itemInfo = response["result"] as! [String : AnyObject]

		var rowCount = 0

		if let statuses = itemInfo["statuses"] as? [[NSString : AnyObject]] {
			table.insertRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(rowCount, statuses.count)), withRowType: "StatusRow")
			for status in statuses {
				if let s = table.rowControllerAtIndex(rowCount) as? StatusRow {
					s.labelL.setText(status["text"] as? String)
					let c = colourFromHex(status["color"] as! String)
					s.labelL.setTextColor(c)
					s.margin.setBackgroundColor(c)
				}
				rowCount += 1
			}
		}

		if let description = itemInfo["description"] as? String {
			table.insertRowsAtIndexes(NSIndexSet(index: rowCount), withRowType: "LabelRow")
			if let r = table.rowControllerAtIndex(rowCount) as? LabelRow {
				r.labelL.setText(description)
			}
			rowCount += 1
		}

		if let comments = itemInfo["comments"] as? [[String : AnyObject]] {
			if comments.count == 0 {
				setTitle("\(comments.count) Comments")
			} else {
				setTitle("Details")
			}
			table.insertRowsAtIndexes(NSIndexSet(indexesInRange: NSMakeRange(rowCount, comments.count)), withRowType: "CommentRow")
			var unreadIndex = 0
			let unreadCount = itemInfo["unreadCount"] as? Int ?? 0
			for comment in comments {
				if let s = table.rowControllerAtIndex(rowCount) as? CommentRow {
					s.setComment(comment, unreadCount: unreadCount, unreadIndex: &unreadIndex)
				}
				rowCount += 1
			}
		} else {
			setTitle("Details")
		}

		showStatus("", hideTable: false)
	}

	func colourFromHex(s: String) -> UIColor {

		let safe = s
			.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			.stringByTrimmingCharactersInSet(NSCharacterSet.symbolCharacterSet())
		let s = NSScanner(string: safe)
		var c:UInt32 = 0
		s.scanHexInt(&c)

		let red: UInt32 = (c & 0xFF0000)>>16
		let green: UInt32 = (c & 0x00FF00)>>8
		let blue: UInt32 = c & 0x0000FF
		let r = CGFloat(red)/255.0
		let g = CGFloat(green)/255.0
		let b = CGFloat(blue)/255.0

		return UIColor(red: r, green: g, blue: b, alpha: 1.0)
	}
}
