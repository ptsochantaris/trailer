
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

	func populateFrom(itemData: [String : AnyObject]) {

		let documentType = [NSDocumentTypeDocumentAttribute: NSRTFTextDocumentType]

		let titleData = itemData["title"] as! NSData
		let title = try! NSAttributedString(data: titleData, options: documentType, documentAttributes: nil)
		titleL.setAttributedText(title)

		let subtitleData = itemData["subtitle"] as! NSData
		let subtitle = try! NSAttributedString(data: subtitleData, options: documentType, documentAttributes: nil)
		detailsL.setAttributedText(subtitle)

		itemId = itemData["localId"] as? String

		let c = itemData["commentCount"] as? Int ?? 0
		totalCommentsL.setText("\(c)")
		totalCommentsGroup.setHidden(c==0)

		let u = itemData["unreadCount"] as? Int ?? 0
		unreadCommentsL.setText("\(u)")
		unreadCommentsGroup.setHidden(u==0)

		counterGroup.setHidden(c+u==0)
	}
}
