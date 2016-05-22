
import WatchKit

final class CommentRow: NSObject {
    @IBOutlet weak var usernameL: WKInterfaceLabel!
	@IBOutlet weak var dateL: WKInterfaceLabel!
    @IBOutlet weak var commentL: WKInterfaceLabel!
	@IBOutlet weak var usernameBackground: WKInterfaceGroup!
	@IBOutlet weak var margin: WKInterfaceGroup!
	var commentId: String?

	func setComment(comment: [String : AnyObject], unreadCount: Int, inout unreadIndex: Int) {

		let username = S(comment["user"] as? String)
		usernameL.setText("@\(username)")
		dateL.setText(shortDateFormatter.stringFromDate(comment["date"] as! NSDate))
		commentL.setText(comment["text"] as? String)
		if(comment["mine"] as! Bool) {
			usernameBackground.setBackgroundColor(UIColor.grayColor())
			commentL.setTextColor(UIColor.lightGrayColor())
			margin.setBackgroundColor(UIColor.darkGrayColor())
		} else {
			if unreadIndex < unreadCount {
				usernameBackground.setBackgroundColor(UIColor.redColor())
				margin.setBackgroundColor(UIColor.redColor())
				unreadIndex += 1
			} else {
				usernameBackground.setBackgroundColor(UIColor.lightGrayColor())
				margin.setBackgroundColor(UIColor.lightGrayColor())
			}
			commentL.setTextColor(UIColor.whiteColor())
		}
	}
}
