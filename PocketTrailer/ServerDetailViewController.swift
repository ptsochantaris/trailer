
import SafariServices
import CoreData

final class ServerDetailViewController: UIViewController, UITextFieldDelegate {

	@IBOutlet weak var name: UITextField!
	@IBOutlet weak var apiPath: UITextField!
	@IBOutlet weak var webFrontEnd: UITextField!
	@IBOutlet weak var authToken: UITextField!
	@IBOutlet weak var reportErrors: UISwitch!
	@IBOutlet weak var scrollView: UIScrollView!
	@IBOutlet weak var authTokenLabel: UILabel!
	@IBOutlet weak var testButton: UIButton!

	var serverId: NSManagedObjectID?

	private var focusedField: UITextField?

	override func viewDidLoad() {
		super.viewDidLoad()
		var a: ApiServer
		if let sid = serverId {
			a = existingObjectWithID(sid) as! ApiServer
		} else {
			a = ApiServer.addDefaultGithubInMoc(mainObjectContext)
			try! mainObjectContext.save()
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
			api.testApiToServer(a) { error in
				sender.enabled = true
				showMessage(error != nil ? "Failed" : "Success", error?.localizedDescription)
			}
		}
	}

	private func updateServerFromForm() -> ApiServer? {
		if let sid = serverId {
			let a = existingObjectWithID(sid) as! ApiServer
			a.label = name.text?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			a.apiPath = apiPath.text?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			a.webPath = webFrontEnd.text?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			a.authToken = authToken.text?.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
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
			let newToken = textField.text?.stringByReplacingCharactersInRange(range, withString: string)
			processTokenStateFrom(newToken)
		}
		return true
	}

	@IBAction func watchListSelected(sender: UIBarButtonItem) {
		openGitHub("/watching")
	}

	@IBAction func createTokenSelected(sender: UIBarButtonItem) {
		openGitHub("/settings/tokens/new")
	}

	@IBAction func existingTokensSelected(sender: UIBarButtonItem) {
		openGitHub("/settings/applications")
	}

	private func checkForValidPath() -> NSURL? {
		if let text = webFrontEnd.text, u = NSURL(string: text) {
			return u
		} else {
			showMessage("Need a valid web server", "Please specify a valid URL for the 'Web Front End' for this server in order to visit it")
			return nil
		}
	}

	private func openGitHub(url: String) {
		if let u = checkForValidPath()?.absoluteString {
			let s = SFSafariViewController(URL: NSURL(string: u + url)!)
			s.view.tintColor = self.view.tintColor
			self.presentViewController(s, animated: true, completion: nil)
		}
	}

	@IBAction func deleteSelected(sender: UIBarButtonItem) {
		let a = UIAlertController(title: "Delete API Server",
			message: "Are you sure you want to remove this API server from your list?",
			preferredStyle: UIAlertControllerStyle.Alert)

		a.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel, handler: nil))
		a.addAction(UIAlertAction(title: "Delete", style: UIAlertActionStyle.Destructive, handler: { [weak self] action in
			self!.deleteServer()
		}))

		presentViewController(a, animated: true, completion: nil)
	}

	private func deleteServer() {
		if let a = existingObjectWithID(serverId!) {
			mainObjectContext.deleteObject(a)
			DataManager.saveDB()
		}
		serverId = nil
		navigationController?.popViewControllerAnimated(true)
	}

	///////////////////////// keyboard

	func keyboardWillShow(notification: NSNotification) {
		if focusedField?.superview == nil { return }

		if let info = notification.userInfo as [NSObject : AnyObject]?, keyboardFrameValue = info[UIKeyboardFrameEndUserInfoKey] as? NSValue {
			let keyboardFrame = keyboardFrameValue.CGRectValue()
			let keyboardHeight = max(0, view.bounds.size.height-keyboardFrame.origin.y)
			let firstResponderFrame = view.convertRect(focusedField!.frame, fromView: focusedField!.superview)
			let bottomOfFirstResponder = (firstResponderFrame.origin.y + firstResponderFrame.size.height) + 36

			let topOfKeyboard = view.bounds.size.height - keyboardHeight
			if bottomOfFirstResponder > topOfKeyboard {
				let distance = bottomOfFirstResponder - topOfKeyboard
				scrollView.contentOffset = CGPointMake(0, scrollView.contentOffset.y + distance)
			}
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
