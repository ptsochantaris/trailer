import WebKit

final class GithubViewController: UIViewController, WKNavigationDelegate {
	
	@IBOutlet weak var spinner: UIActivityIndicatorView!
	var pathToLoad: String?
	private var _webView: WKWebView?

	override func viewDidLoad() {
		super.viewDidLoad()

		let webConfiguration = WKWebViewConfiguration()
		_webView = WKWebView(frame: view.bounds, configuration: webConfiguration)
		_webView!.navigationDelegate = self
		_webView!.scrollView.contentInset = UIEdgeInsetsMake(64, 0, 0, 0)
		_webView!.autoresizingMask = UIViewAutoresizing.FlexibleWidth.union(UIViewAutoresizing.FlexibleHeight)
		_webView!.translatesAutoresizingMaskIntoConstraints = true
		view.addSubview(_webView!)
		_webView!.loadRequest(NSURLRequest(URL: NSURL(string: pathToLoad!)!))
	}

	func webView(webView: WKWebView, didFailNavigation navigation: WKNavigation!, withError error: NSError) {
		loadingFailed()
	}

	func webView(webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: NSError) {
		loadingFailed()
	}

	private func loadingFailed() {
		_webView!.hidden = false
		spinner.stopAnimating()
		title = "Loading Failed"
		showMessage("Loading Failed", "URL: '"+pathToLoad!+"'")
	}

	func webView(webView: WKWebView, didFinishNavigation navigation: WKNavigation!) {
		webView.hidden = false
		spinner.stopAnimating()
		title = webView.title

	}

	@IBAction func doneSelected(sender: UIBarButtonItem) {
		dismissViewControllerAnimated(true, completion: nil)
	}

	func webView(webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
		webView.hidden = true
		spinner.startAnimating()
	}
}
