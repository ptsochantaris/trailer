import WatchConnectivity
import WatchKit

class CommonController: WKInterfaceController {
    weak var _table: WKInterfaceTable!
    weak var _statusLabel: WKInterfaceLabel!

    override func willActivate() {
        super.willActivate()
        if let app = WKApplication.shared().delegate as? ExtensionDelegate, app.lastView != self {
            if showLoadingFeedback {
                if loading == 0 {
                    show(status: "Connecting…", hideTable: false)
                } else {
                    show(status: "Loading…", hideTable: false)
                }
            }
            app.lastView = self
        }
    }

    var showLoadingFeedback: Bool {
        _table.numberOfRows == 0
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

    func requestData(command _: String?) {
        // for subclassing
    }

    private var loading = 0
    func send(request: [String: Any]) {
        if loading == 0 {
            if showLoadingFeedback {
                show(status: "Loading…", hideTable: false)
            }
            attempt(request: request)
        }
    }

    private func attempt(request: [String: Any]) {
        loading += 1

        WCSession.default.sendMessage(request) { [weak self] response in
            guard let self else { return }
            if let errorIndicator = response["error"] as? Bool, errorIndicator == true {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    loading = 0
                    showTemporaryError(response["status"] as! String)
                }
            } else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    loading = 0
                }
                update(from: response)
            }
        } errorHandler: { error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if loading == 5 {
                    loadingFailed(with: error)
                } else {
                    try? await Task.sleep(nanoseconds: 300 * NSEC_PER_MSEC)
                    attempt(request: request)
                }
            }
        }
    }

    private func showTemporaryError(_ mesage: String) {
        _statusLabel.setTextColor(UIColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
        show(status: mesage, hideTable: true)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400 * NSEC_PER_MSEC)
            _statusLabel.setTextColor(.white)
            show(status: "", hideTable: false)
        }
    }

    func update(from _: [AnyHashable: Any]) {
        // for subclassing
    }

    func loadingFailed(with error: Error) {
        showTemporaryError("Error: \(error.localizedDescription)")
        loading = 0
    }
}
