import WebKit
import CoreData

final class DetailViewController: UIViewController, WKNavigationDelegate {

	@IBOutlet weak var spinner: UIActivityIndicatorView!
	@IBOutlet weak var statusLabel: UILabel!

	private var webView: WKWebView?
	private var alwaysRequestDesktopSite = false

	var isVisible = false
	var catchupWithDataItemWhenLoaded: NSManagedObjectID?

	var detailItem: NSURL? {
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
		w.autoresizingMask = [.FlexibleWidth, .FlexibleHeight]
		w.hidden = true
		view.addSubview(w)

		webView = w

		configureView()
	}

	func configureView() {
		if let w = webView {
			if let d = detailItem {
				if !alwaysRequestDesktopSite && Settings.alwaysRequestDesktopSite {
					DLog("Activating iPad webview user-agent")
					alwaysRequestDesktopSite = true
					w.evaluateJavaScript("navigator.userAgent") { result, error in
						w.customUserAgent = result?.stringByReplacingOccurrencesOfString("iPhone", withString: "iPad")
						self.configureView()
					}
					return
				} else if alwaysRequestDesktopSite && !Settings.alwaysRequestDesktopSite {
					DLog("Deactivating iPad webview user-agent")
					w.customUserAgent = nil
					alwaysRequestDesktopSite = false
				}
				DLog("Will load: %@", d.absoluteString)
				w.loadRequest(NSURLRequest(URL: d))
			} else {
				statusLabel.textColor = UIColor.lightGrayColor()
				statusLabel.text = "Please select an item from the list, or select 'Settings' to add servers, or show/hide repositories.\n\n(You may have to login to GitHub the first time you visit a private item)"
				statusLabel.hidden = false
				navigationItem.rightBarButtonItem?.enabled = false
				title = nil
				w.hidden = true
			}
		}
	}

	override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		navigationItem.leftBarButtonItem = (traitCollection.horizontalSizeClass == .Compact) ? nil : splitViewController?.displayModeButtonItem()
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		if let w = webView where w.loading {
			spinner.startAnimating()
		} else { // Same item re-selected
			spinner.stopAnimating()
			catchupWithComments()
		}
		isVisible = true
	}

	override func viewDidDisappear(animated: Bool) {
		isVisible = false
		super.viewDidDisappear(animated)
	}

	func webView(webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		spinner.startAnimating()
		statusLabel.hidden = true
		statusLabel.text = nil
		webView.hidden = true
		title = "Loading..."
		navigationItem.rightBarButtonItem = nil
		api.networkIndicationStart()
	}

	func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse, decisionHandler: (WKNavigationResponsePolicy) -> Void) {
		if let res = navigationResponse.response as? NSHTTPURLResponse where res.statusCode == 404 {
			showMessage("Not Found", "\nPlease ensure you are logged in with the correct account on GitHub\n\nIf you are using two-factor auth: There is a bug between GitHub and iOS which may cause your login to fail.  If it happens, temporarily disable two-factor auth and log in from here, then re-enable it afterwards.  You will only need to do this once.")
		}
		decisionHandler(.Allow)
	}

	func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
		spinner.stopAnimating()
		statusLabel.hidden = true
		webView.hidden = false
		navigationItem.rightBarButtonItem?.enabled = true
		title = webView.title
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Action, target: self, action: #selector(DetailViewController.shareSelected))
		api.networkIndicationEnd()

		catchupWithComments()
		if splitViewController?.collapsed ?? true {
			becomeFirstResponder()
		}
	}

	override var keyCommands: [UIKeyCommand]? {
		let ff = UIKeyCommand(input: UIKeyInputLeftArrow, modifierFlags: .Command, action: #selector(DetailViewController.focusOnMaster), discoverabilityTitle: "Focus keyboard on item list")
		let s = UIKeyCommand(input: "o", modifierFlags: .Command, action: #selector(DetailViewController.keyOpenInSafari), discoverabilityTitle: "Open in Safari")
		return [ff,s]
	}

	func keyOpenInSafari() {
		if let u = webView?.URL {
			UIApplication.sharedApplication().openURL(u)
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
		let m = popupManager.getMasterController()
		if splitViewController?.collapsed ?? true {
			m.navigationController?.popViewControllerAnimated(true)
		}
		m.becomeFirstResponder()
	}

	private func catchupWithComments() {
		if let oid = catchupWithDataItemWhenLoaded, dataItem = existingObjectWithID(oid) as? ListableItem {
			if let count = dataItem.unreadComments?.integerValue where count > 0 {
				dataItem.catchUpWithComments()
				DataManager.saveDB()
			}
		}
		catchupWithDataItemWhenLoaded = nil
	}

	func webView(webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: NSError) {
		loadFailed(error)
	}

	func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError error: NSError) {
		loadFailed(error)
	}

	private func loadFailed(error: NSError) {
		spinner.stopAnimating()
		statusLabel.textColor = UIColor.redColor()
		statusLabel.text = "Loading Error: \(error.localizedDescription)"
		statusLabel.hidden = false
		webView?.hidden = true
		title = "Error"
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Refresh, target: self, action: #selector(DetailViewController.configureView))
		api.networkIndicationEnd()
	}

	func shareSelected() {
		if let u = webView?.URL {
			popupManager.shareFromView(self, buttonItem: navigationItem.rightBarButtonItem!, url: u)
		}
	}
}
