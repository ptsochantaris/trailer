
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
			usernameBackground.setBackgroundColor(.gray)
			commentL.setTextColor(.lightGray)
			margin.setBackgroundColor(.darkGray)
		} else {
			if unreadIndex < unreadCount {
				usernameBackground.setBackgroundColor(.red)
				margin.setBackgroundColor(.red)
				unreadIndex += 1
			} else {
				usernameBackground.setBackgroundColor(.lightGray)
				margin.setBackgroundColor(.lightGray)
			}
			commentL.setTextColor(.white)
		}
	}
}
