import WatchKit
import WatchConnectivity

class CommonController: WKInterfaceController {

	weak var _table: WKInterfaceTable!
	weak var _statusLabel: WKInterfaceLabel!

	override func willActivate() {
		super.willActivate()
		if let app = WKExtension.sharedExtension().delegate as? ExtensionDelegate where app.lastView != self {
			app.lastView = self
			if showLoadingFeedback() {
				showStatus("Connecting...", hideTable: false)
			}
		}
	}

	func showLoadingFeedback() -> Bool {
		return _table.numberOfRows == 0
	}

	func showStatus(status: String, hideTable: Bool) {
		_statusLabel.setText(status)
		if hideTable {
			_table.setHidden(hideTable)
		} else {
			_table.setHidden(false)
			_table.setAlpha(status.isEmpty ? 1.0 : 0.5)
		}
		_statusLabel.setHidden(status.isEmpty)
	}

	func requestData(command: String?) {
		// for subclassing
	}

	private var loading = 0
	func sendRequest(request: [String : AnyObject]) {
		if loading == 0 {
			if showLoadingFeedback() {
				showStatus("Loading...", hideTable: false)
			}
			attemptRequest(request)
		}
	}

	private func attemptRequest(request: [String : AnyObject]) {

		loading++

		WCSession.defaultSession().sendMessage(request, replyHandler: { response in
			dispatch_async(dispatch_get_main_queue(), {
				if let errorIndicator = response["error"] as? Bool where errorIndicator == true {
					self.showTemporaryError(response["status"] as! String)
				} else {
					self.updateFromData(response)
				}
				self.loading = 0
			})
		}) { error in
			if self.loading==5 {
				dispatch_async(dispatch_get_main_queue()) {
					self.showTemporaryError("Error: "+error.localizedDescription)
					self.loading = 0
				}
			} else {
				dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(0.2 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
					self.attemptRequest(request)
				}
			}
		}
	}

	private func showTemporaryError(error: String) {
		_statusLabel.setTextColor(UIColor.redColor())
		showStatus(error, hideTable: true)
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(3.0 * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
			self._statusLabel.setTextColor(UIColor.whiteColor())
			self.showStatus("", hideTable: false)
		}
	}

	func updateFromData(response: [NSString : AnyObject]) {
		// for subclassing
	}
}
