
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
			a = existingObject(with: sid) as! ApiServer
		} else {
			a = ApiServer.addDefaultGithub(in: DataManager.main)
			try! DataManager.main.save()
			serverId = a.objectID
		}
		name.text = a.label
		apiPath.text = a.apiPath
		webFrontEnd.text = a.webPath
		authToken.text = a.authToken
		reportErrors.isOn = a.reportRefreshFailures

		if UIDevice.current.userInterfaceIdiom != UIUserInterfaceIdiom.pad {
			let n = NotificationCenter.default
			n.addObserver(self, selector: #selector(keyboardWillShow), name: .UIKeyboardWillShow, object: nil)
			n.addObserver(self, selector: #selector(keyboardWillHide), name: .UIKeyboardWillHide, object: nil)
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		navigationController?.setToolbarHidden(false, animated: true)
		processTokenState(from: authToken.text)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		navigationController?.setToolbarHidden(true, animated: true)
	}

	@IBAction func testConnectionSelected(_ sender: UIButton) {
		if let a = updateServerFromForm() {
			sender.isEnabled = false
			API.testApi(to: a) { error in
				sender.isEnabled = true
				showMessage(error != nil ? "Failed" : "Success", error?.localizedDescription)
			}
		}
	}

	private func updateServerFromForm() -> ApiServer? {
		if let sid = serverId {
			let a = existingObject(with: sid) as! ApiServer
			a.label = name.text?.trim
			a.apiPath = apiPath.text?.trim
			a.webPath = webFrontEnd.text?.trim
			a.authToken = authToken.text?.trim
			a.reportRefreshFailures = reportErrors.isOn
			a.lastSyncSucceeded = true
			preferencesDirty = true

			processTokenState(from: a.authToken)
			return a
		} else {
			return nil
		}
	}

	private func processTokenState(from tokenText: String?) {
		if S(tokenText).isEmpty {
			authTokenLabel.textColor =  .red
			testButton.isEnabled = false
			testButton.alpha = 0.6
		} else {
			authTokenLabel.textColor =  .black
			testButton.isEnabled = true
			testButton.alpha = 1.0
		}
	}

	@IBAction func reportChanged(_ sender: UISwitch) {
		_ = updateServerFromForm()
	}

	func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
		_ = updateServerFromForm()
		return true
	}

	func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
		focusedField = textField
		return true
	}

	func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			textField.resignFirstResponder()
			return false
		}
		if textField == authToken {
			let newToken = textField.text?.replacingCharacters(in: range, with: string)
			processTokenState(from: newToken)
		}
		return true
	}

	@IBAction func watchListSelected(_ sender: UIBarButtonItem) {
		openGitHub(url: "/watching")
	}

	@IBAction func createTokenSelected(_ sender: UIBarButtonItem) {
		openGitHub(url: "/settings/tokens/new")
	}

	@IBAction func existingTokensSelected(_ sender: UIBarButtonItem) {
		openGitHub(url: "/settings/applications")
	}

	private var validatedPath: URL? {
		if let text = webFrontEnd.text, let u = URL(string: text) {
			return u
		} else {
			showMessage("Need a valid web server", "Please specify a valid URL for the 'Web Front End' for this server in order to visit it")
			return nil
		}
	}

	private func openGitHub(url: String) {
		if let u = validatedPath?.absoluteString {
			let s = SFSafariViewController(url: URL(string: u + url)!)
			s.view.tintColor = self.view.tintColor
			self.present(s, animated: true, completion: nil)
		}
	}

	@IBAction func deleteSelected(_ sender: UIBarButtonItem) {
		let a = UIAlertController(title: "Delete API Server",
			message: "Are you sure you want to remove this API server from your list?",
			preferredStyle: .alert)

		a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
		a.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] action in
			self?.deleteServer()
		})

		present(a, animated: true, completion: nil)
	}

	private func deleteServer() {
		if let a = existingObject(with: serverId!) {
			DataManager.main.delete(a)
			DataManager.saveDB()
		}
		serverId = nil
		_ = navigationController?.popViewController(animated: true)
	}

	///////////////////////// keyboard

	func keyboardWillShow(notification: NSNotification) {
		if focusedField?.superview == nil { return }

		if let info = notification.userInfo, let keyboardFrameValue = info[UIKeyboardFrameEndUserInfoKey] as? NSValue {
			let keyboardFrame = keyboardFrameValue.cgRectValue
			let keyboardHeight = max(0, view.bounds.size.height-keyboardFrame.origin.y)
			let firstResponderFrame = view.convert(focusedField!.frame, from: focusedField!.superview)
			let bottomOfFirstResponder = (firstResponderFrame.origin.y + firstResponderFrame.size.height) + 36

			let topOfKeyboard = view.bounds.size.height - keyboardHeight
			if bottomOfFirstResponder > topOfKeyboard {
				let distance = bottomOfFirstResponder - topOfKeyboard
				scrollView.contentOffset = CGPoint(x: 0, y: scrollView.contentOffset.y + distance)
			}
		}
	}

	func keyboardWillHide(notification: NSNotification) {
		if !scrollView.isDragging {
			scrollView.scrollRectToVisible(CGRect(x: 0,
			                                      y: min(scrollView.contentOffset.y, scrollView.contentSize.height - scrollView.bounds.size.height),
			                                      width: scrollView.bounds.size.width,
			                                      height: scrollView.bounds.size.height),
			                               animated: false)
		}
	}
}
