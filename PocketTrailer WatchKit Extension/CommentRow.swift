
import WatchKit

final class CommentRow: NSObject {
    @IBOutlet private var usernameL: WKInterfaceLabel!
	@IBOutlet private var dateL: WKInterfaceLabel!
    @IBOutlet private var commentL: WKInterfaceLabel!
	@IBOutlet private var usernameBackground: WKInterfaceGroup!
	@IBOutlet private var margin: WKInterfaceGroup!
	var commentId: String?

	func set(comment: [AnyHashable : Any], unreadCount: Int, unreadIndex: inout Int) {

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
