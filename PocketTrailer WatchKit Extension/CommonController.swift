import WatchKit
import WatchConnectivity

class CommonController: WKInterfaceController {

	weak var _table: WKInterfaceTable!
	weak var _statusLabel: WKInterfaceLabel!

	override func willActivate() {
		super.willActivate()
		if let app = WKExtension.shared().delegate as? ExtensionDelegate, app.lastView != self {
			if showLoadingFeedback() {
				showStatus("Connecting...", hideTable: false)
			}
			app.lastView = self
		}
	}

	func showLoadingFeedback() -> Bool {
		return _table.numberOfRows == 0
	}

	func showStatus(_ status: String, hideTable: Bool) {
		_statusLabel.setText(status)
		if hideTable {
			_table.setHidden(hideTable)
		} else {
			_table.setHidden(false)
			_table.setAlpha(status.isEmpty ? 1.0 : 0.5)
		}
		_statusLabel.setHidden(status.isEmpty)
	}

	func requestData(_ command: String?) {
		// for subclassing
	}

	private var loading = 0
	func sendRequest(_ request: [String : AnyObject]) {
		if loading == 0 {
			if showLoadingFeedback() {
				showStatus("Loading...", hideTable: false)
			}
			attemptRequest(request)
		}
	}

	private func attemptRequest(_ request: [String : AnyObject]) {

		loading += 1

		WCSession.default().sendMessage(request, replyHandler: { response in
			atNextEvent(self) { S in
				if let errorIndicator = response["error"] as? Bool, errorIndicator == true {
					S.showTemporaryError(response["status"] as! String)
				} else {
					S.updateFromData(response)
				}
				S.loading = 0
			}
		}) { error in
			atNextEvent(self) { S in
				if S.loading==5 {
					S.loadingFailed(error)
				} else {
					delay(0.3, S) { S in
						S.attemptRequest(request)
					}
				}
			}
		}
	}

	private func showTemporaryError(_ error: String) {
		_statusLabel.setTextColor(UIColor.red)
		showStatus(error, hideTable: true)
		delay(3, self) { S in
			S._statusLabel.setTextColor(UIColor.white)
			S.showStatus("", hideTable: false)
		}
	}

	func updateFromData(_ response: [NSString : AnyObject]) {
		// for subclassing
	}

	func loadingFailed(_ error: NSError) {
		showTemporaryError("Error: \(error.localizedDescription)")
		loading = 0
	}
}
