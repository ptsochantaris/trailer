import CoreData
import SafariServices

final class ServerDetailViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet private var name: UITextField!
    @IBOutlet private var apiPath: UITextField!
    @IBOutlet private var graphQLPath: UITextField!
    @IBOutlet private var webFrontEnd: UITextField!
    @IBOutlet private var authToken: UITextField!
    @IBOutlet private var reportErrors: UISwitch!
    @IBOutlet private var scrollView: UIScrollView!
    @IBOutlet private var authTokenLabel: UILabel!
    @IBOutlet private var testButton: UIButton!

    var serverLocalId: NSManagedObjectID?

    private var focusedField: UITextField?

    override func viewDidLoad() {
        super.viewDidLoad()

        var a: ApiServer
        if let sid = serverLocalId {
            a = existingObject(with: sid) as! ApiServer
        } else {
            a = ApiServer.addDefaultGithub(in: DataManager.main)
            view.isUserInteractionEnabled = false
            Task {
                await DataManager.saveDB()
                serverLocalId = a.objectID
                view.isUserInteractionEnabled = true
            }
        }
        name.text = a.label
        apiPath.text = a.apiPath
        graphQLPath.text = a.graphQLPath
        webFrontEnd.text = a.webPath
        authToken.text = a.authToken
        reportErrors.isOn = a.reportRefreshFailures

        if UIDevice.current.userInterfaceIdiom != UIUserInterfaceIdiom.pad {
            let n = NotificationCenter.default
            n.addObserver(self, selector: #selector(keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
            n.addObserver(self, selector: #selector(keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        processTokenState(from: authToken.text)
    }

    @IBAction private func testConnectionSelected(_ sender: UIButton) {
        guard let apiServer = updateServerFromForm() else {
            return
        }

        sender.isEnabled = false

        Task {
            do {
                try await apiServer.test()
                showMessage("API seems OK for \(apiServer.label.orEmpty)", nil)
            } catch {
                showMessage("The test failed", error.localizedDescription)
            }
            sender.isEnabled = true
        }
    }

    @discardableResult
    private func updateServerFromForm() -> ApiServer? {
        if let sid = serverLocalId {
            let a = existingObject(with: sid) as! ApiServer
            a.label = name.text?.trim
            a.apiPath = apiPath.text?.trim
            a.graphQLPath = graphQLPath.text?.trim
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
        if tokenText.isEmpty {
            authTokenLabel.textColor = .appRed
            testButton.isEnabled = false
            testButton.alpha = 0.6
        } else {
            authTokenLabel.textColor = UIColor.label
            testButton.isEnabled = true
            testButton.alpha = 1.0
        }
    }

    @IBAction private func reportChanged(_: UISwitch) {
        updateServerFromForm()
    }

    func textFieldShouldEndEditing(_: UITextField) -> Bool {
        updateServerFromForm()
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
        if textField === authToken {
            let toReplace = textField.text.orEmpty
            if let r = Range(range, in: toReplace) {
                let newToken = toReplace.replacingCharacters(in: r, with: string)
                processTokenState(from: newToken)
            }
        }
        return true
    }

    @IBAction private func watchListSelected(_: UIBarButtonItem) {
        openGitHub(url: "/watching")
    }

    @IBAction private func createTokenSelected(_: UIBarButtonItem) {
        openGitHub(url: "/settings/tokens/new")
    }

    @IBAction private func existingTokensSelected(_: UIBarButtonItem) {
        openGitHub(url: "/settings/tokens")
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
            s.view.tintColor = view.tintColor
            present(s, animated: true)
        }
    }

    @IBAction private func deleteSelected(_: UIBarButtonItem) {
        let a = UIAlertController(title: "Delete API Server",
                                  message: "Are you sure you want to remove this API server from your list?",
                                  preferredStyle: .alert)

        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        a.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            Task {
                await self.deleteServer()
            }
        })

        present(a, animated: true)
    }

    private func deleteServer() async {
        if let a = existingObject(with: serverLocalId!) {
            DataManager.main.delete(a)
            await DataManager.saveDB()
        }
        serverLocalId = nil
        _ = navigationController?.popViewController(animated: true)
    }

    ///////////////////////// keyboard

    @objc private func keyboardWillShow(notification: NSNotification) {
        if focusedField?.superview == nil { return }

        if let info = notification.userInfo, let keyboardFrameValue = info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue {
            let keyboardFrame = keyboardFrameValue.cgRectValue
            let keyboardHeight = max(0, view.bounds.size.height - keyboardFrame.origin.y)
            let firstResponderFrame = view.convert(focusedField!.frame, from: focusedField!.superview)
            let bottomOfFirstResponder = (firstResponderFrame.origin.y + firstResponderFrame.size.height) + 36

            let topOfKeyboard = view.bounds.size.height - keyboardHeight
            if bottomOfFirstResponder > topOfKeyboard {
                let distance = bottomOfFirstResponder - topOfKeyboard
                scrollView.contentOffset = CGPoint(x: 0, y: scrollView.contentOffset.y + distance)
            }
        }
    }

    @objc private func keyboardWillHide(notification _: NSNotification) {
        if !scrollView.isDragging {
            scrollView.scrollRectToVisible(CGRect(x: 0,
                                                  y: min(scrollView.contentOffset.y, scrollView.contentSize.height - scrollView.bounds.size.height),
                                                  width: scrollView.bounds.size.width,
                                                  height: scrollView.bounds.size.height),
                                           animated: false)
        }
    }
}
