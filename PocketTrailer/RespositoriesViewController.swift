
import UIKit
import CoreData

final class RespositoriesViewController: UITableViewController, UISearchBarDelegate, NSFetchedResultsControllerDelegate {

	// Filtering
	@IBOutlet weak var searchBar: UISearchBar!
	private var searchTimer: PopTimer!
	private var _fetchedResultsController: NSFetchedResultsController<Repo>?

	@IBOutlet weak var actionsButton: UIBarButtonItem!

	@IBAction func done(_ sender: UIBarButtonItem) {
		if preferencesDirty {
			_ = app.startRefresh()
		}
		dismiss(animated: true, completion: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		searchTimer = PopTimer(timeInterval: 0.5) { [weak self] in
			self?.reloadData()
		}
	}

	override func viewDidAppear(_ animated: Bool) {
		actionsButton.isEnabled = ApiServer.someServersHaveAuthTokens(in: mainObjectContext)
		if actionsButton.isEnabled && fetchedResultsController.fetchedObjects?.count==0 {
			refreshList()
		} else if let selectedIndex = tableView.indexPathForSelectedRow {
			tableView.deselectRow(at: selectedIndex, animated: true)
		}
		super.viewDidAppear(animated)
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		self.navigationController?.setToolbarHidden(false, animated: animated)
	}

	override func viewWillDisappear(_ animated: Bool) {
		super.viewWillDisappear(animated)
		self.navigationController?.setToolbarHidden(true, animated: animated)
	}

	@IBAction func actionSelected(_ sender: UIBarButtonItem) {
		refreshList()
	}

	@IBAction func setAllPrsSelected(_ sender: UIBarButtonItem) {
		if let ip = tableView.indexPathForSelectedRow {
			tableView.deselectRow(at: ip, animated: false)
		}
		performSegue(withIdentifier: "showRepoSelection", sender: self)
	}

	private func refreshList() {
		self.navigationItem.rightBarButtonItem?.isEnabled = false
		let originalName = navigationItem.title
		navigationItem.title = "Loading..."
		actionsButton.isEnabled = false
		tableView.isUserInteractionEnabled = false
		tableView.alpha = 0.5

		NotificationQueue.clear()

		let tempContext = DataManager.buildChildContext()
		api.fetchRepositories(to: tempContext) { [weak self] in
			if ApiServer.shouldReportRefreshFailure(in: tempContext) {
				var errorServers = [String]()
				for apiServer in ApiServer.allApiServers(in: tempContext) {
					if apiServer.goodToGo && !apiServer.lastSyncSucceeded {
						errorServers.append(S(apiServer.label))
					}
				}
				let serverNames = errorServers.joined(separator: ", ")
				showMessage("Error", "Could not refresh repository list from \(serverNames), please ensure that the tokens you are using are valid")
				NotificationQueue.clear()
			} else {
				try! tempContext.save()
				NotificationQueue.commit()
			}
			preferencesDirty = true
			guard let s = self  else { return }
			s.navigationItem.title = originalName
			s.actionsButton.isEnabled = ApiServer.someServersHaveAuthTokens(in: mainObjectContext)
			s.tableView.alpha = 1.0
			s.tableView.isUserInteractionEnabled = true
			s.navigationItem.rightBarButtonItem?.isEnabled = true
		}
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return fetchedResultsController.sections?.count ?? 0
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return fetchedResultsController.sections?[section].numberOfObjects ?? 0
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! RepoCell
		configureCell(cell, atIndexPath: indexPath)
		return cell
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let indexPath = tableView.indexPathForSelectedRow,
			let vc = segue.destination as? RepoSettingsViewController {

			vc.repo = fetchedResultsController.object(at: indexPath)
		}
	}

	override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section==1 {
			return "Forked Repos"
		} else {
			let repo = fetchedResultsController.object(at: IndexPath(row: 0, section: section))
			return repo.fork ? "Forked Repos" : "Parent Repos"
		}
	}

	private var fetchedResultsController: NSFetchedResultsController<Repo> {
		if let f = _fetchedResultsController {
			return f
		}

		let fetchRequest = NSFetchRequest<Repo>(entityName: "Repo")
		if let text = searchBar.text, !text.isEmpty {
			fetchRequest.predicate = NSPredicate(format: "fullName contains [cd] %@", text)
		}
		fetchRequest.fetchBatchSize = 20
		fetchRequest.sortDescriptors = [NSSortDescriptor(key: "fork", ascending: true), NSSortDescriptor(key: "fullName", ascending: true)]

		let fc = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: mainObjectContext, sectionNameKeyPath: "fork", cacheName: nil)
		fc.delegate = self
		_fetchedResultsController = fc

		try! fc.performFetch()
		return fc
	}

	func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		tableView.beginUpdates()
	}

	func controller(controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {

		heightCache.removeAll()

		switch(type) {
		case .insert:
			tableView.insertSections(IndexSet(integer: sectionIndex), with: .automatic)
		case .delete:
			tableView.deleteSections(IndexSet(integer: sectionIndex), with: .automatic)
		case .update:
			tableView.reloadSections(IndexSet(integer: sectionIndex), with: .automatic)
		default:
			break
		}
	}

	func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

		heightCache.removeAll()

		switch(type) {
		case .insert:
			tableView.insertRows(at: [(newIndexPath ?? indexPath!)], with: .automatic)
		case .delete:
			tableView.deleteRows(at: [indexPath!], with:.automatic)
		case .update:
			if let cell = tableView.cellForRow(at: (newIndexPath ?? indexPath!)) as? RepoCell {
				configureCell(cell, atIndexPath: newIndexPath ?? indexPath!)
			}
		case .move:
			tableView.deleteRows(at: [indexPath!], with:.automatic)
			if let n = newIndexPath {
				tableView.insertRows(at: [n], with:.automatic)
			}
		}
	}

	func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
		tableView.endUpdates()
	}

	private func configureCell(_ cell: RepoCell, atIndexPath: IndexPath) {
		let repo = fetchedResultsController.object(at: atIndexPath)

		let titleColor: UIColor = repo.shouldSync ? .black : .lightGray
		let titleAttributes = [ NSForegroundColorAttributeName: titleColor ]

		let title = NSMutableAttributedString(attributedString: NSAttributedString(string: S(repo.fullName), attributes: titleAttributes))
		title.append(NSAttributedString(string: "\n", attributes: titleAttributes))
		let groupTitle = groupTitleForRepo(repo: repo)
		title.append(groupTitle)

		cell.titleLabel.attributedText = title
		let prTitle = prTitleForRepo(repo: repo)
		let issuesTitle = issueTitleForRepo(repo: repo)
		let hidingTitle = hidingTitleForRepo(repo: repo)

		cell.prLabel.attributedText = prTitle
		cell.issuesLabel.attributedText = issuesTitle
		cell.hidingLabel.attributedText = hidingTitle
		cell.accessibilityLabel = "\(title), \(prTitle.string), \(issuesTitle.string), \(hidingTitle.string), \(groupTitle.string)"
	}

	private var sizer: RepoCell?
	private var heightCache = [IndexPath : CGFloat]()
	override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
		if sizer == nil {
			sizer = tableView.dequeueReusableCell(withIdentifier: "Cell") as? RepoCell
		} else if let h = heightCache[indexPath] {
			//DLog("using cached height for %@ - %@", indexPath.section, indexPath.row)
			return h
		}
		configureCell(sizer!, atIndexPath: indexPath)
		let h = sizer!.systemLayoutSizeFitting(CGSize(width: tableView.bounds.width, height: UILayoutFittingCompressedSize.height),
			withHorizontalFittingPriority: UILayoutPriorityRequired,
			verticalFittingPriority: UILayoutPriorityFittingSizeLevel).height
		heightCache[indexPath] = h
		return h
	}

	private func titleForRepo(repo: Repo) -> NSAttributedString {

		let fullName = S(repo.fullName)
		let text = repo.inaccessible ? "\(fullName) (inaccessible)" : fullName
		let color: UIColor = repo.shouldSync ? .darkText : .lightGray
		return NSAttributedString(string: text, attributes: [ NSForegroundColorAttributeName: color ])
	}

	private func prTitleForRepo(repo: Repo) -> NSAttributedString {

		let policy = RepoDisplayPolicy(repo.displayPolicyForPrs) ?? .hide
		return NSAttributedString(string: "PR Sections: \(policy.name)", attributes: attributes(for: policy))
	}

	private func issueTitleForRepo(repo: Repo) -> NSAttributedString {

		let policy = RepoDisplayPolicy(repo.displayPolicyForIssues) ?? .hide
		return NSAttributedString(string: "Issue Sections: \(policy.name)", attributes: attributes(for: policy))
	}

	private func groupTitleForRepo(repo: Repo) -> NSAttributedString {
		if let l = repo.groupLabel {
			return NSAttributedString(string: "Group: \(l)", attributes: [
				NSForegroundColorAttributeName : UIColor.darkGray,
				NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
				])
		} else {
			return NSAttributedString(string: "Ungrouped", attributes: [
				NSForegroundColorAttributeName : UIColor.lightGray,
				NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize)
				])
		}
	}

	private func hidingTitleForRepo(repo: Repo) -> NSAttributedString {

		let policy = RepoHidingPolicy(repo.itemHidingPolicy) ?? .noHiding
		return NSAttributedString(string: policy.name, attributes: attributes(for: policy))
	}

	private func attributes(for policy: RepoDisplayPolicy) -> [String : Any] {
		return [
			NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize-1.0),
			NSForegroundColorAttributeName: policy.color
		]
	}

	private func attributes(for policy: RepoHidingPolicy) -> [String : Any] {
		return [
			NSFontAttributeName: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize-1.0),
			NSForegroundColorAttributeName: policy.color
		]
	}

	///////////////////////////// filtering

	private func reloadData() {

		heightCache.removeAll()

		let currentIndexes = IndexSet(integersIn: NSMakeRange(0, fetchedResultsController.sections?.count ?? 0).toRange()!)

		_fetchedResultsController = nil

		let dataIndexes = IndexSet(integersIn: NSMakeRange(0, fetchedResultsController.sections?.count ?? 0).toRange()!)

		let removedIndexes = currentIndexes.filter { !dataIndexes.contains($0) }
		let addedIndexes = dataIndexes.filter { !currentIndexes.contains($0) }
		let untouchedIndexes = dataIndexes.filter { !(removedIndexes.contains($0) || addedIndexes.contains($0)) }

		tableView.beginUpdates()
		if removedIndexes.count > 0 {
			tableView.deleteSections(IndexSet(removedIndexes), with: .automatic)
		}
		if untouchedIndexes.count > 0 {
			tableView.reloadSections(IndexSet(untouchedIndexes), with:.automatic)
		}
		if addedIndexes.count > 0 {
			tableView.insertSections(IndexSet(addedIndexes), with: .automatic)
		}
		tableView.endUpdates()
	}

	override func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		if searchBar!.isFirstResponder {
			searchBar!.resignFirstResponder()
		}
	}

	func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
		searchTimer.push()
	}

	func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
		searchBar.setShowsCancelButton(true, animated: true)
	}

	func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
		searchBar.setShowsCancelButton(false, animated: true)
	}

	func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
		searchBar.text = nil
		searchTimer.push()
		view.endEditing(false)
	}

	func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
		if text == "\n" {
			view.endEditing(false)
			return false
		} else {
			return true
		}
	}
}
