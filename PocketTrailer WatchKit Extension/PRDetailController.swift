
import WatchKit
import Foundation

final class PRDetailController: CommonController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet var statusLabel: WKInterfaceLabel!

	private var rowControllers = [PopulatableRow]()
	private var itemId: String!

	override func awake(withContext context: Any?) {
		_statusLabel = statusLabel
		_table = table

		let c = context as! [AnyHashable : Any]
		itemId = c[ITEM_KEY] as! String

		super.awake(withContext: context)
	}

	override func requestData(command: String?) {
		var params = ["list": "item_detail", "localId": itemId!]
		if let command = command {
			params["command"] = command
		}
		send(request: params)
	}

	@IBAction func refreshSelected() {
		show(status: "Refreshing…", hideTable: true)
		requestData(command: "refresh")
	}

	@IBAction func markAllReadSelected() {
		requestData(command: "markItemsRead")
	}

	@IBAction func openOnDeviceSelected() {
		requestData(command: "openItem")
	}

	override func update(from response: [AnyHashable : Any]) {

		table.removeRows(at: IndexSet(integersIn: Range(uncheckedBounds: (0, table.numberOfRows))))

		rowControllers.removeAll(keepingCapacity: false)
		let itemInfo = response["result"] as! [AnyHashable : Any]

		var rowCount = 0

		if let statuses = itemInfo["statuses"] as? [[AnyHashable : Any]] {
			table.insertRows(at: IndexSet(integersIn: Range(uncheckedBounds: (rowCount, statuses.count))), withRowType: "StatusRow")
			for status in statuses {
				if let s = table.rowController(at: rowCount) as? StatusRow {
					s.labelL.setText(status["text"] as? String)
					let c = colour(from: status["color"] as! String)
					s.labelL.setTextColor(c)
					s.margin.setBackgroundColor(c)
				}
				rowCount += 1
			}
		}

		if let description = itemInfo["description"] as? String {
			table.insertRows(at: IndexSet(integer: rowCount), withRowType: "LabelRow")
			if let r = table.rowController(at: rowCount) as? LabelRow {
				r.labelL.setText(description)
			}
			rowCount += 1
		}

		if let comments = itemInfo["comments"] as? [[AnyHashable : Any]] {
			if comments.count == 0 {
				setTitle("\(comments.count) Comments")
			} else {
				setTitle("Details")
			}
			table.insertRows(at: IndexSet(integersIn: Range(uncheckedBounds: (rowCount, comments.count))), withRowType: "CommentRow")
			var unreadIndex = 0
			let unreadCount = itemInfo["unreadCount"] as? Int ?? 0
			for comment in comments {
				if let s = table.rowController(at: rowCount) as? CommentRow {
					s.set(comment: comment, unreadCount: unreadCount, unreadIndex: &unreadIndex)
				}
				rowCount += 1
			}
		} else {
			setTitle("Details")
		}

		show(status: "", hideTable: false)
	}

	func colour(from hex: String) -> UIColor {

		let safe = hex
			.trimmingCharacters(in: .whitespacesAndNewlines)
			.trimmingCharacters(in: .symbols)
		let s = Scanner(string: safe)
		var c: UInt32 = 0
		s.scanHexInt32(&c)

		let red: UInt32 = (c & 0xFF0000)>>16
		let green: UInt32 = (c & 0x00FF00)>>8
		let blue: UInt32 = c & 0x0000FF
		let r = CGFloat(red)/255.0
		let g = CGFloat(green)/255.0
		let b = CGFloat(blue)/255.0

		return UIColor(red: r, green: g, blue: b, alpha: 1.0)
	}
}
