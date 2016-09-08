
import WatchKit

final class PRRow: NSObject {

    @IBOutlet weak var titleL: WKInterfaceLabel!
    @IBOutlet weak var detailsL: WKInterfaceLabel!

    @IBOutlet weak var totalCommentsL: WKInterfaceLabel!
    @IBOutlet weak var totalCommentsGroup: WKInterfaceGroup!

    @IBOutlet weak var unreadCommentsL: WKInterfaceLabel!
    @IBOutlet weak var unreadCommentsGroup: WKInterfaceGroup!

    @IBOutlet weak var counterGroup: WKInterfaceGroup!

	var itemId: String?
	var hasUnread: Bool!

	func populate(from itemData: [AnyHashable : Any]) {

		let titleData = itemData["title"] as! Data
		let title = NSKeyedUnarchiver.unarchiveObject(with: titleData) as! NSAttributedString
		titleL.setAttributedText(title)

		let subtitleData = itemData["subtitle"] as! Data
		let subtitle = NSKeyedUnarchiver.unarchiveObject(with: subtitleData) as! NSAttributedString
		detailsL.setAttributedText(subtitle)

		itemId = itemData["localId"] as? String

		let c = itemData["commentCount"] as? Int ?? 0
		totalCommentsL.setText("\(c)")
		totalCommentsGroup.setAlpha(c > 0 ? 1.0 : 0.4)

		let u = itemData["unreadCount"] as? Int ?? 0
		unreadCommentsL.setText("\(u)")
		unreadCommentsGroup.setAlpha(u > 0 ? 1.0 : 0.4)
		hasUnread = u>0
	}
}
