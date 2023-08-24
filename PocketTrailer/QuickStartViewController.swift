import SafariServices

extension UIViewController {
    func dismiss(animated: Bool) async {
        await withCheckedContinuation { continuation in
            dismiss(animated: animated) {
                continuation.resume()
            }
        }
    }
}

final class QuickStartViewController: UIViewController, UITextFieldDelegate {
    @IBOutlet private var testButton: UIButton!
    @IBOutlet private var otherViews: [UIView]!
    @IBOutlet private var spinner: UIActivityIndicatorView!
    @IBOutlet private var feedback: UILabel!
    @IBOutlet private var skip: UIBarButtonItem!
    @IBOutlet private var importer: UIBarButtonItem!
    @IBOutlet private var link: UIButton!

    private let newServer = ApiServer.allApiServers(in: DataManager.main).first!
    private var token = ""
    private var importExport: ImportExport!

    override func viewDidLoad() {
        super.viewDidLoad()
        importExport = ImportExport(parent: self)
        normalMode()
    }

    @IBAction private func importSelected(_ sender: UIBarButtonItem) {
        importExport.importSelected(sender: sender)
    }

    @IBAction private func skipSelected(_: UIBarButtonItem) {
        dismiss(animated: true)
    }

    @IBAction private func openGitHubSelected(_: UIButton) {
        let s = SFSafariViewController(url: URL(string: "https://github.com/settings/tokens/new")!)
        s.view.tintColor = view.tintColor
        present(s, animated: true)
    }

    @IBAction private func testSelected(_ sender: UIButton) {
        testMode()

        Task {
            do {
                try await newServer.test()
                feedback.text = "\nFetching your watchlist. This will take a moment…"
                Settings.lastSuccessfulRefresh = nil
                await app.startRefreshIfItIsDue()
                await checkRefreshDone()

            } catch {
                showMessage("Testing the token failed - please check that you have pasted your token correctly", error.localizedDescription)
                normalMode()
                sender.isEnabled = true
            }
        }
    }

    private func checkRefreshDone() async {
        while API.isRefreshing {
            try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
        }

        if newServer.lastSyncSucceeded {
            await dismiss(animated: true)
            await popupManager.masterController.resetView(becauseOfChanges: true)
            Settings.lastPreferencesTabSelected = 1 // repos
            popupManager.masterController.performSegue(withIdentifier: "showPreferences", sender: self)
            showMessage("Setup complete!", "This is the 'Repos' tab that displays your current GitHub watchlist. By default everything is hidden. Be sure to enable only the repos you need, in order to keep API (and data & battery) usage low.\n\nYou can tweak options & behaviour from the 'Advanced' tab. When you're done, just close this settings view from the top-left.\n\nTrailer has read-only access to your GitHub data, so feel free to experiment, you can't damage your data or settings on GitHub.")

        } else {
            showMessage("Syncing with this server failed - please check that your network connection is working and that you have pasted your token correctly", nil)
            normalMode()
        }
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if string == "\n" {
            view.endEditing(false)
            return false
        }
        token = textField.text.orEmpty
        if let r = Range(range, in: token) {
            token = token.replacingCharacters(in: r, with: string)
        }
        token = token.trim
        testButton.isEnabled = !token.isEmpty
        link.alpha = testButton.isEnabled ? 0.5 : 1.0
        return true
    }

    private func testMode() {
        view.endEditing(true)

        try? DataManager.main.save() // permanent ID for generated server

        for v in otherViews {
            v.isHidden = true
        }
        skip.isEnabled = false
        importer.isEnabled = false
        spinner.startAnimating()
        feedback.text = "\nTesting the token…"

        newServer.authToken = token
        newServer.lastSyncSucceeded = true
    }

    private func normalMode() {
        feedback.text = "Quick Start"
        skip.isEnabled = true
        importer.isEnabled = true
        for v in otherViews {
            v.isHidden = false
        }
        spinner.stopAnimating()
    }
}
