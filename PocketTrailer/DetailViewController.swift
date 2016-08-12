import WebKit
import CoreData

final class DetailViewController: UIViewController, WKNavigationDelegate {

	@IBOutlet weak var spinner: UIActivityIndicatorView!
	@IBOutlet weak var statusLabel: UILabel!

	private var webView: WKWebView?
	private var alwaysRequestDesktopSite = false

	var isVisible = false
	var catchupWithDataItemWhenLoaded: NSManagedObjectID?

	var detailItem: URL? {
		didSet {
			if detailItem != oldValue {
				configureView()
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "Loading..."

		let webConfiguration = WKWebViewConfiguration()
		let w = WKWebView(frame: view.bounds, configuration: webConfiguration)
		w.navigationDelegate = self
		w.scrollView.contentInset = UIEdgeInsetsMake(64, 0, 0, 0)
		w.scrollView.scrollIndicatorInsets = w.scrollView.contentInset
		w.autoresizingMask = [.flexibleWidth, .flexibleHeight]
		w.isHidden = true
		view.addSubview(w)

		webView = w

		configureView()
	}

	override func viewDidLayoutSubviews() {
		super.viewDidLayoutSubviews()
		popupManager.masterController.layoutTabs()
	}

	func configureView() {
		if let w = webView {
			if let d = detailItem {
				if !alwaysRequestDesktopSite && Settings.alwaysRequestDesktopSite {
					DLog("Activating iPad webview user-agent")
					alwaysRequestDesktopSite = true
					w.evaluateJavaScript("navigator.userAgent") { result, error in
						w.customUserAgent = result?.replacingOccurrences(of: "iPhone", with: "iPad")
						self.configureView()
					}
					return
				} else if alwaysRequestDesktopSite && !Settings.alwaysRequestDesktopSite {
					DLog("Deactivating iPad webview user-agent")
					w.customUserAgent = nil
					alwaysRequestDesktopSite = false
				}
				DLog("Will load: %@", d.absoluteString)
				w.load(URLRequest(url: d))
			} else {
				statusLabel.textColor = .lightGray
				statusLabel.text = "Please select an item from the list, or select 'Settings' to add servers, or show/hide repositories.\n\n(You may have to login to GitHub the first time you visit a private item)"
				statusLabel.isHidden = false
				navigationItem.rightBarButtonItem?.isEnabled = false
				title = nil
				w.isHidden = true
			}
		}
	}

	override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		navigationItem.leftBarButtonItem = (traitCollection.horizontalSizeClass == .compact) ? nil : splitViewController?.displayModeButtonItem
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		if let w = webView, w.isLoading {
			spinner.startAnimating()
		} else { // Same item re-selected
			spinner.stopAnimating()
			catchupWithComments()
		}
		isVisible = true
	}

	override func viewDidDisappear(_ animated: Bool) {
		isVisible = false
		super.viewDidDisappear(animated)
	}

	func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		spinner.startAnimating()
		statusLabel.isHidden = true
		statusLabel.text = nil
		webView.isHidden = true
		title = "Loading..."
		navigationItem.rightBarButtonItem = nil
	}

	func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: (WKNavigationResponsePolicy) -> Void) {
		if let res = navigationResponse.response as? HTTPURLResponse, res.statusCode == 404 {
			showMessage("Not Found", "\nPlease ensure you are logged in with the correct account on GitHub\n\nIf you are using two-factor auth: There is a bug between GitHub and iOS which may cause your login to fail.  If it happens, temporarily disable two-factor auth and log in from here, then re-enable it afterwards.  You will only need to do this once.")
		}
		decisionHandler(.allow)
	}

	func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
		spinner.stopAnimating()
		statusLabel.isHidden = true
		webView.isHidden = false
		navigationItem.rightBarButtonItem?.isEnabled = true
		title = webView.title
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .action, target: self, action: #selector(shareSelected))

		catchupWithComments()
		if splitViewController?.isCollapsed ?? true {
			_ = becomeFirstResponder()
		}
	}

	override var keyCommands: [UIKeyCommand]? {
		let ff = UIKeyCommand(input: UIKeyInputLeftArrow, modifierFlags: .command, action: #selector(focusOnMaster), discoverabilityTitle: "Focus keyboard on item list")
		let s = UIKeyCommand(input: "o", modifierFlags: .command, action: #selector(keyOpenInSafari), discoverabilityTitle: "Open in Safari")
		return [ff,s]
	}

	func keyOpenInSafari() {
		if let u = webView?.url {
			UIApplication.shared.open(u, options: [:], completionHandler: nil)
		}
	}

	override func becomeFirstResponder() -> Bool {
		if detailItem != nil {
			return webView?.becomeFirstResponder() ?? false
		} else {
			return false
		}
	}

	func focusOnMaster() {
		let m = popupManager.masterController
		if splitViewController?.isCollapsed ?? true {
			_ = m.navigationController?.popViewController(animated: true)
		}
		m.becomeFirstResponder()
	}

	private func catchupWithComments() {
		if let oid = catchupWithDataItemWhenLoaded, let dataItem = existingObject(with: oid) as? ListableItem {
			if dataItem.unreadComments > 0 {
				dataItem.catchUpWithComments()
				DataManager.saveDB()
			}
		}
		catchupWithDataItemWhenLoaded = nil
	}

	func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
		loadFailed(error: error)
	}

	func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
		loadFailed(error: error)
	}

	private func loadFailed(error: NSError) {
		spinner.stopAnimating()
		statusLabel.textColor = .red
		statusLabel.text = "Loading Error: \(error.localizedDescription)"
		statusLabel.isHidden = false
		webView?.isHidden = true
		title = "Error"
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(configureView))
	}

	func shareSelected() {
		if let u = webView?.url {
			popupManager.shareFromView(view: self, buttonItem: navigationItem.rightBarButtonItem!, url: u)
		}
	}
}
