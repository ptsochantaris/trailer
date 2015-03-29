import WebKit
import CoreData

class DetailViewController: UIViewController, WKNavigationDelegate {

	@IBOutlet weak var spinner: UIActivityIndicatorView!
	@IBOutlet weak var statusLabel: UILabel!

	private var _webView: WKWebView?

	var isVisible: Bool = false
	var catchupWithDataItemWhenLoaded : NSManagedObjectID?

	var detailItem: NSURL? {
		didSet {
			if detailItem != oldValue && _webView != nil {
				configureView()
			}
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		title = "Loading..."

		let webConfiguration = WKWebViewConfiguration()
		_webView = WKWebView(frame: view.bounds, configuration: webConfiguration)
		_webView!.navigationDelegate = self
		_webView!.scrollView.contentInset = UIEdgeInsetsMake(64, 0, 0, 0)
		_webView!.autoresizingMask = UIViewAutoresizing.FlexibleWidth | UIViewAutoresizing.FlexibleHeight
		_webView!.setTranslatesAutoresizingMaskIntoConstraints(true)
		_webView!.hidden = true
		view.addSubview(_webView!)

		if detailItem == nil {
			showEmpty()
		} else {
			configureView()
		}
	}

	func configureView() {
		if let d = detailItem {
			DLog("Will load: %@", d.absoluteString)
			_webView!.loadRequest(NSURLRequest(URL: d))
		} else {
			showEmpty()
		}
	}

	private func showEmpty() {
		statusLabel.textColor = UIColor.lightGrayColor()
		statusLabel.text = "Please select a Pull Request from the list on the left, or select 'Settings' to add servers, or show/hide repositories.\n\n(You may have to login to GitHub the first time you visit a private PR)"
		statusLabel.hidden = false
		navigationItem.rightBarButtonItem?.enabled = false
		title = nil
		_webView?.hidden = true
	}

	override func traitCollectionDidChange(previousTraitCollection: UITraitCollection?) {
		super.traitCollectionDidChange(previousTraitCollection)
		navigationItem.leftBarButtonItem = (traitCollection.horizontalSizeClass==UIUserInterfaceSizeClass.Compact) ? nil : splitViewController?.displayModeButtonItem()
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		if _webView != nil && _webView!.loading {
			spinner.startAnimating()
		} else {
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
		statusLabel.text = ""
		_webView?.hidden = true
		title = "Loading..."
		navigationItem.rightBarButtonItem = nil
		api.networkIndicationStart()
	}

	func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse, decisionHandler: (WKNavigationResponsePolicy) -> Void) {
		let res = navigationResponse.response as! NSHTTPURLResponse
		if res.statusCode == 404 {
			UIAlertView(title: "Not Found",
			message: "\nPlease ensure you are logged in with the correct account on GitHub\n\nIf you are using two-factor auth: There is a bug between Github and iOS which may cause your login to fail.  If it happens, temporarily disable two-factor auth and log in from here, then re-enable it afterwards.  You will only need to do this once.",
			delegate: nil,
			cancelButtonTitle: "OK").show()
		}
		decisionHandler(WKNavigationResponsePolicy.Allow)
	}

	func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
		spinner.stopAnimating()
		statusLabel.hidden = true
		_webView?.hidden = false
		navigationItem.rightBarButtonItem?.enabled = true
		title = _webView?.title
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Action, target: self, action: Selector("shareSelected"))
		api.networkIndicationEnd()

		catchupWithComments()
	}

	private func catchupWithComments()
	{
		if let oid = catchupWithDataItemWhenLoaded {
			let dataItem = mainObjectContext.existingObjectWithID(oid, error: nil)
			if let pr = dataItem as? PullRequest {
				if (pr.unreadComments?.integerValue ?? 0) > 0 {
					pr.catchUpWithComments()
					DataManager.saveDB()
				}
			} else if let i = dataItem as? Issue {
				if (i.unreadComments?.integerValue ?? 0) > 0 {
					i.catchUpWithComments()
					DataManager.saveDB()
				}
			}
			catchupWithDataItemWhenLoaded = nil
		}
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
		statusLabel.text = "There was an error loading this pull request page: " + error.localizedDescription
		statusLabel.hidden = false
		_webView?.hidden = true
		title = "Error"
		navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.Refresh, target: self, action: Selector("configureView"))
		api.networkIndicationEnd()
	}


	func shareSelected() {
		if let u = _webView?.URL {
			app.shareFromView(self, buttonItem: navigationItem.rightBarButtonItem!, url: u)
		}
	}
}
