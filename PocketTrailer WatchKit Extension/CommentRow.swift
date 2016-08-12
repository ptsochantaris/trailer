
import WatchKit

final class CommentRow: NSObject {
    @IBOutlet weak var usernameL: WKInterfaceLabel!
	@IBOutlet weak var dateL: WKInterfaceLabel!
    @IBOutlet weak var commentL: WKInterfaceLabel!
	@IBOutlet weak var usernameBackground: WKInterfaceGroup!
	@IBOutlet weak var margin: WKInterfaceGroup!
	var commentId: String?

	func set(comment: [String : AnyObject], unreadCount: Int, unreadIndex: inout Int) {

		let username = S(comment["user"] as? String)
		usernameL.setText("@\(username)")
		dateL.setText(shortDateFormatter.string(from: comment["date"] as! Date))
		commentL.setText(comment["text"] as? String)
		if(comment["mine"] as! Bool) {
			usernameBackground.setBackgroundColor(UIColor.gray)
			commentL.setTextColor(UIColor.lightGray)
			margin.setBackgroundColor(UIColor.darkGray)
		} else {
			if unreadIndex < unreadCount {
				usernameBackground.setBackgroundColor(UIColor.red)
				margin.setBackgroundColor(UIColor.red)
				unreadIndex += 1
			} else {
				usernameBackground.setBackgroundColor(UIColor.lightGray)
				margin.setBackgroundColor(UIColor.lightGray)
			}
			commentL.setTextColor(UIColor.white)
		}
	}
}
