
import UIKit
import CoreData

class ServerDetailViewController: UIViewController, UITextFieldDelegate {

	@IBOutlet var name: UITextField!
	@IBOutlet var apiPath: UITextField!
	@IBOutlet var webFrontEnd: UITextField!
	@IBOutlet var authToken: UITextField!
	@IBOutlet var reportErrors: UISwitch!
	@IBOutlet var scrollView: UIScrollView!
	@IBOutlet var authTokenLabel: UILabel!
	@IBOutlet var testButton: UIButton!

	var serverId: NSManagedObjectID?

	private var targetUrl: String?
	private var focusedField: UITextField?

	override func viewDidLoad() {
		super.viewDidLoad()
		var a: ApiServer
		if let sid = serverId {
			a = mainObjectContext.existingObjectWithID(sid, error: nil) as ApiServer
		} else {
			a = ApiServer.addDefaultGithubInMoc(mainObjectContext)
			mainObjectContext.save(nil)
			serverId = a.objectID
		}
		name.text = a.label
		apiPath.text = a.apiPath
		webFrontEnd.text = a.webPath
		authToken.text = a.authToken
		reportErrors.on = a.reportRefreshFailures.boolValue

		if UIDevice.currentDevice().userInterfaceIdiom != UIUserInterfaceIdiom.Pad {
			let n = NSNotificationCenter.defaultCenter()
			n.addObserver(self, selector: Selector("keyboardWillShow:"), name: UIKeyboardWillShowNotification, object: nil)
			n.addObserver(self, selector: Selector("keyboardWillHide:"), name:UIKeyboardWillHideNotification, object:nil)
		}
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setToolbarHidden(false, animated: true)
		processTokenStateFrom(authToken.text)
	}

	override func viewWillDisappear(animated: Bool) {
		super.viewWillDisappear(animated)
		navigationController?.setToolbarHidden(true, animated: true)
	}

	@IBAction func testConnectionSelected(sender: UIButton) {
		if let a = updateServerFromForm() {
			sender.enabled = false
			api.testApiToServer(a, andCallback: { (error) in
				sender.enabled = true
				UIAlertView(title: error != nil ? "Failed" : "Success",
					message: error?.localizedDescription,
					delegate: nil,
					cancelButtonTitle: "OK").show()
			})
		}
	}

	private func updateServerFromForm() -> ApiServer? {
		if let sid = serverId {
			let a = mainObjectContext.existingObjectWithID(sid, error: nil) as ApiServer
			a.label = name.text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			a.apiPath = apiPath.text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			a.webPath = webFrontEnd.text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			a.authToken = authToken.text.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			a.reportRefreshFailures = reportErrors.on
			a.lastSyncSucceeded = true
			app.preferencesDirty = true

			processTokenStateFrom(a.authToken)
			return a
		} else {
			return nil
		}
	}

	private func processTokenStateFrom(tokenText: String?) {
		if (tokenText ?? "").isEmpty {
			authTokenLabel.textColor =  UIColor.redColor()
			testButton.enabled = false
			testButton.alpha = 0.6
		} else {
			authTokenLabel.textColor =  UIColor.blackColor()
			testButton.enabled = true
			testButton.alpha = 1.0
		}
	}

	@IBAction func reportChanged(sender: UISwitch) {
		updateServerFromForm()
	}

	func textFieldShouldEndEditing(textField: UITextField) -> Bool {
		updateServerFromForm()
		return true
	}

	func textFieldShouldBeginEditing(textField: UITextField) -> Bool {
		focusedField = textField
		return true
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			textField.resignFirstResponder()
			return false
		}
		if textField == authToken {
			let newToken = (textField.text as NSString).stringByReplacingCharactersInRange(range, withString: string)
			processTokenStateFrom(newToken)
		}
		return true
	}

	@IBAction func watchListSelected(sender: UIBarButtonItem) {
		if let u = checkForValidPath()?.absoluteString {
			targetUrl = u + "/watching"
			performSegueWithIdentifier("openGithub", sender: self)
		}
	}

	@IBAction func createTokenSelected(sender: UIBarButtonItem) {
		if let u = checkForValidPath()?.absoluteString {
			targetUrl = u + "/settings/tokens/new"
			performSegueWithIdentifier("openGithub", sender: self)
		}
	}

	@IBAction func existingTokensSelected(sender: UIBarButtonItem) {
		if let u = checkForValidPath()?.absoluteString {
			targetUrl = u + "/settings/applications"
			performSegueWithIdentifier("openGithub", sender: self)
		}
	}

	private func checkForValidPath() -> NSURL? {
		if let u = NSURL(string: webFrontEnd.text) {
			return u
		} else {
			UIAlertView(title: "Need a valid web server",
				message: "Please specify a valid URL for the 'Web Front End' for this server in order to visit it",
				delegate: nil,
				cancelButtonTitle: "OK").show()
			return nil
		}
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let destination = segue.destinationViewController as? GithubViewController {
			destination.pathToLoad = targetUrl
		} else if let destination = segue.destinationViewController as? UINavigationController {
			(destination.topViewController as? GithubViewController)?.pathToLoad = targetUrl
		}
		targetUrl = nil
	}

	@IBAction func deleteSelected(sender: UIBarButtonItem) {
		let a = UIAlertController(title: "Delete API Server",
			message: "Are you sure you want to remove this API server from your list?",
			preferredStyle: UIAlertControllerStyle.Alert)

		a.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: nil))
		a.addAction(UIAlertAction(title: "Delete", style: UIAlertActionStyle.Destructive, handler: { [weak self] (action) in
			self!.deleteServer()
		}))

		presentViewController(a, animated: true, completion: nil)
	}

	private func deleteServer() {
		if let a = mainObjectContext.existingObjectWithID(serverId!, error: nil) {
			mainObjectContext.deleteObject(a)
			DataManager.saveDB()
		}
		serverId = nil
		navigationController?.popViewControllerAnimated(true)
	}

	///////////////////////// keyboard

	func keyboardWillShow(notification: NSNotification) {
		if focusedField?.superview == nil { return }

		let info = notification.userInfo as NSDictionary!
		let keyboardFrame = (info.objectForKey(UIKeyboardFrameEndUserInfoKey) as NSValue).CGRectValue()
		let keyboardHeight = max(0, view.bounds.size.height-keyboardFrame.origin.y)
		let firstResponderFrame = view.convertRect(focusedField!.frame, fromView: focusedField!.superview)
		let bottomOfFirstResponder = (firstResponderFrame.origin.y + firstResponderFrame.size.height) + 36

		let topOfKeyboard = view.bounds.size.height - keyboardHeight
		if bottomOfFirstResponder > topOfKeyboard {
			let distance = bottomOfFirstResponder - topOfKeyboard
			scrollView.contentOffset = CGPointMake(0, scrollView.contentOffset.y + distance)
		}
	}

	func keyboardWillHide(notification: NSNotification) {
		if !scrollView.dragging {
			scrollView.scrollRectToVisible(CGRectMake(0,
				min(scrollView.contentOffset.y, scrollView.contentSize.height - scrollView.bounds.size.height),
				scrollView.bounds.size.width, scrollView.bounds.size.height), animated: false)
		}
	}
}
