import WatchKit

final class PRRow: NSObject {

    @IBOutlet private var titleL: WKInterfaceLabel!
    @IBOutlet private var detailsL: WKInterfaceLabel!

    @IBOutlet private var totalCommentsL: WKInterfaceLabel!
    @IBOutlet private var totalCommentsGroup: WKInterfaceGroup!

    @IBOutlet private var unreadCommentsL: WKInterfaceLabel!
    @IBOutlet private var unreadCommentsGroup: WKInterfaceGroup!

    @IBOutlet private var counterGroup: WKInterfaceGroup!

	var itemId: String?
	var hasUnread: Bool!

	func populate(from itemData: [AnyHashable: Any]) {

		let title =  itemData["title"] as! NSAttributedString
		titleL.setAttributedText(title)

		let subtitle = itemData["subtitle"] as! NSAttributedString
		detailsL.setAttributedText(subtitle)

		itemId = itemData["localId"] as? String

		let c = itemData["commentCount"] as? Int ?? 0
		totalCommentsL.setText(String(c))
		totalCommentsGroup.setHidden(c == 0)

		let u = itemData["unreadCount"] as? Int ?? 0
		unreadCommentsL.setText(String(u))
		unreadCommentsGroup.setHidden(u == 0)
		hasUnread = u>0
	}
}
