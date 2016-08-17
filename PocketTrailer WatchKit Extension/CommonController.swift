import WatchKit
import WatchConnectivity

class CommonController: WKInterfaceController {

	weak var _table: WKInterfaceTable!
	weak var _statusLabel: WKInterfaceLabel!

	override func willActivate() {
		super.willActivate()
		if let app = WKExtension.shared().delegate as? ExtensionDelegate, app.lastView != self {
			if showLoadingFeedback {
				show(status: "Connecting...", hideTable: false)
			}
			app.lastView = self
		}
	}

	var showLoadingFeedback: Bool {
		return _table.numberOfRows == 0
	}

	func show(status: String, hideTable: Bool) {
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
	func send(request: [String : Any]) {
		if loading == 0 {
			if showLoadingFeedback {
				show(status: "Loading...", hideTable: false)
			}
			attempt(request: request)
		}
	}

	private func attempt(request: [String : Any]) {

		loading += 1

		WCSession.default().sendMessage(request, replyHandler: { response in
			atNextEvent(self) { S in
				if let errorIndicator = response["error"] as? Bool, errorIndicator == true {
					S.showTemporaryError(response["status"] as! String)
				} else {
					S.update(from: response)
				}
				S.loading = 0
			}
		}) { error in
			atNextEvent(self) { S in
				if S.loading==5 {
					S.loadingFailed(with: error)
				} else {
					delay(0.3, S) { S in
						S.attempt(request: request)
					}
				}
			}
		}
	}

	private func showTemporaryError(_ mesage: String) {
		_statusLabel.setTextColor(.red)
		show(status: mesage, hideTable: true)
		delay(3, self) { S in
			S._statusLabel.setTextColor(.white)
			S.show(status: "", hideTable: false)
		}
	}

	func update(from response: [AnyHashable : Any]) {
		// for subclassing
	}

	func loadingFailed(with error: Error) {
		showTemporaryError("Error: \(error.localizedDescription)")
		loading = 0
	}
}
