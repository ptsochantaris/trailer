
import UIKit

final class CustomReposViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
	
	var repos = [Repo]()
	@IBOutlet private weak var table: UITableView!
	
	@objc private func updateRepos() {
		repos = Repo.allItems(of: Repo.self, in: DataManager.main).filter { $0.manuallyAdded }
		table.reloadData()
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		navigationItem.largeTitleDisplayMode = .automatic

		sizer = table.dequeueReusableCell(withIdentifier: "CustomRepoCellId") as! CustomRepoCell
		NotificationCenter.default.addObserver(self, selector: #selector(updateRepos), name: RefreshEndedNotification, object: nil)
	}
	
	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		updateRepos()
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
	
	func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let c = tableView.dequeueReusableCell(withIdentifier: "CustomRepoCellId", for: indexPath) as! CustomRepoCell
		c.repoLabel.text = repos[indexPath.row].fullName
		return c
	}
	
	func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return repos.count
	}
	
	func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
		return .delete
	}
	
	func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
		let r = repos[indexPath.row]
		DataManager.main.delete(r)
		DataManager.saveDB()
		atNextEvent {
			popupManager.masterController.updateStatus(becauseOfChanges: true)
		}
		updateRepos()
	}
	
	private var sizer: CustomRepoCell!
	func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		sizer.repoLabel.text = repos[indexPath.row].fullName
		return sizer.systemLayoutSizeFitting(CGSize(width: tableView.bounds.size.width, height: 0),
		                                     withHorizontalFittingPriority: UILayoutPriority.required,
		                                     verticalFittingPriority: UILayoutPriority.fittingSizeLevel).height
	}
	
	@IBOutlet private weak var addButton: UIBarButtonItem!
	@IBAction private func addSelected(_ sender: Any) {
		
		let v = UIAlertController(title: "Add Custom Repository", message: "Please paste the full URL of the repository you wish to add.\n\nTo add all repos for a given user or org, user a star (*) as the name of the repo instead.", preferredStyle: .alert)
		v.addTextField { field in
			field.placeholder = "http://github.com/owner_or_org/repo_name"
		}
		let cancel = UIAlertAction(title: "Cancel", style: .cancel)
		let ok = UIAlertAction(title: "Add", style: .default) { a in
			self.addRepo(url: v.textFields?.first!.text)
		}
		v.addAction(cancel)
		v.addAction(ok)
		present(v, animated: true)
	}
	
	private func addRepo(url: String?) {
		guard let url = url else { return }
		guard let components = URLComponents(string: url) else {
			showMessage("This does not seem to be a valid URL", nil)
			return
		}
		
		guard let host = components.host else {
			showMessage("This URL does not contain a server hostname", "The URL you have provided does not seem to have a usable hostname. Please paste the full URL, including the https:// prefix")
			return
		}
		
		guard let server = ApiServer.server(host: host, moc: DataManager.main) else {
			showMessage("Server not found", "We can't locate a configured server with an API base host of '\(host)'")
			return
		}
		
		let segments = components.path.components(separatedBy: "/")
		let count = segments.count
		if count < 2 {
			showMessage("Path not found", "We can't locate a valid repo path in the URL provided. Please ensure it ends with the owner and repo name components (…/owner/repo)")
			return
		}
		let ownerName = segments[count-2]
		let repoName = segments[count-1]
		if ownerName.isEmpty || repoName.isEmpty {
			showMessage("Path not found", "We can't locate a valid repo path in the URL provided. Please ensure it ends with the owner and repo name components (…/owner/repo) or a star for all repos from this org or user.")
			return
		}
		
		let a = UIActivityIndicatorView(activityIndicatorStyle: .gray)
		a.startAnimating()
		addButton.customView = a

		if repoName == "*" {
			API.fetchAllRepos(owner: ownerName, from: server) { error in
				a.stopAnimating()
				self.addButton.customView = nil

				if let e = error {
					showMessage("Fetching Repository Information Failed", e.localizedDescription)
				} else {
					let addedCount = Repo.newItems(of: Repo.self, in: DataManager.main).count
					if Settings.displayPolicyForNewPrs == Int(RepoDisplayPolicy.hide.rawValue) && Settings.displayPolicyForNewIssues == Int(RepoDisplayPolicy.hide.rawValue) {
						showMessage("Repositories added", "WARNING: While \(addedCount) repositories have been added successfully to your list, your default settings specify that they should be hidden. You probably want to change their visibility in the main repositories list.")
					} else {
						showMessage("Repositories added", "\(addedCount) new repositories have been added to your local list. Trailer will refresh after you close preferences to fetch any items from them.")
					}
					DataManager.saveDB()
					atNextEvent {
						popupManager.masterController.updateStatus(becauseOfChanges: true)
					}
					self.updateRepos()
				}
			}
		} else {
			API.fetchRepo(named: repoName, owner: ownerName, from: server) { error in
				a.stopAnimating()
				self.addButton.customView = nil

				if let e = error {
					showMessage("Fetching Repository Information Failed", e.localizedDescription)
				} else {
					if Settings.displayPolicyForNewPrs == Int(RepoDisplayPolicy.hide.rawValue) && Settings.displayPolicyForNewIssues == Int(RepoDisplayPolicy.hide.rawValue) {
						showMessage("Repository added", "WARNING: While the repository has been added successfully to your list, your default settings specify that it should be hidden. You probably want to change its visibility in the main repositories list.")
					} else {
						showMessage("Repository added", "The new repository has been added to your local list. Trailer will refresh after you close preferences to fetch any items from it.")
					}
					DataManager.saveDB()
					atNextEvent {
						popupManager.masterController.updateStatus(becauseOfChanges: true)
					}
					self.updateRepos()
				}
			}
		}
	}
}
