
import UIKit
import CoreData

final class RespositoriesViewController: UITableViewController, UITextFieldDelegate, NSFetchedResultsControllerDelegate {

	// Filtering
	private var searchField: UITextField?
	private var searchTimer: PopTimer?
	private var _fetchedResultsController: NSFetchedResultsController?

	@IBOutlet weak var actionsButton: UIBarButtonItem!

	@IBAction func done(sender: UIBarButtonItem) {
		if app.preferencesDirty {
			app.startRefresh()
		}
		dismissViewControllerAnimated(true, completion: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		searchField = UITextField(frame: CGRectMake(9, 10, view.bounds.size.width-18, 31))
		searchField!.placeholder = "Filter..."
		searchField!.returnKeyType = UIReturnKeyType.Search
		searchField!.font = UIFont.systemFontOfSize(18)
		searchField!.borderStyle = UITextBorderStyle.RoundedRect
		searchField!.contentVerticalAlignment = UIControlContentVerticalAlignment.Center
		searchField!.clearButtonMode = UITextFieldViewMode.Always
		searchField!.autocapitalizationType = UITextAutocapitalizationType.None
		searchField!.autocorrectionType = UITextAutocorrectionType.No
		searchField!.delegate = self
		searchField!.autoresizingMask = UIViewAutoresizing.FlexibleWidth

		searchTimer = PopTimer(timeInterval: 0.5) { [weak self] in
			self!.reloadData()
		}

		let searchHolder = UIView(frame: CGRectMake(0, 0, view.bounds.size.width, 51))
		searchHolder.addSubview(searchField!)
		searchHolder.autoresizesSubviews = true
		searchHolder.autoresizingMask = UIViewAutoresizing.FlexibleWidth
		tableView.tableHeaderView = searchHolder
	}

	override func viewDidAppear(animated: Bool) {
		actionsButton.enabled = ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext)
		if actionsButton.enabled && fetchedResultsController.fetchedObjects?.count==0 {
			refreshList()
		} else if let selectedIndex = tableView.indexPathForSelectedRow {
			tableView.deselectRowAtIndexPath(selectedIndex, animated: true)
		}
		super.viewDidAppear(animated)
	}

	override func viewWillAppear(animated: Bool) {
		super.viewWillAppear(animated)
		self.navigationController?.setToolbarHidden(false, animated: animated)
	}

	override func viewWillDisappear(animated: Bool) {
		super.viewWillDisappear(animated)
		self.navigationController?.setToolbarHidden(true, animated: animated)
	}

	@IBAction func actionSelected(sender: UIBarButtonItem) {
		refreshList()
	}

	@IBAction func setAllPrsSelected(sender: UIBarButtonItem) {
		if let ip = tableView.indexPathForSelectedRow {
			tableView.deselectRowAtIndexPath(ip, animated: false)
		}
		performSegueWithIdentifier("showRepoSelection", sender: self)
	}

	private func refreshList() {
		self.navigationItem.rightBarButtonItem?.enabled = false
		let originalName = navigationItem.title
		navigationItem.title = "Loading..."
		actionsButton.enabled = false
		tableView.userInteractionEnabled = false
		tableView.alpha = 0.5

		let tempContext = DataManager.tempContext()
		api.fetchRepositoriesToMoc(tempContext) { [weak self] in
			if ApiServer.shouldReportRefreshFailureInMoc(tempContext) {
				var errorServers = [String]()
				for apiServer in ApiServer.allApiServersInMoc(tempContext) {
					if apiServer.goodToGo && !apiServer.syncIsGood {
						errorServers.append(apiServer.label ?? "Untitled Server")
					}
				}
				let serverNames = errorServers.joinWithSeparator(", ")
				showMessage("Error", "Could not refresh repository list from \(serverNames), please ensure that the tokens you are using are valid")
			} else {
				try! tempContext.save()
			}
			self!.navigationItem.title = originalName
			self!.actionsButton.enabled = ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext)
			self!.tableView.alpha = 1.0
			self!.tableView.userInteractionEnabled = true
			app.preferencesDirty = true
			self!.navigationItem.rightBarButtonItem?.enabled = true
		}
	}

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return fetchedResultsController.sections?.count ?? 0
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return fetchedResultsController.sections?[section].numberOfObjects ?? 0
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as! RepoCell
		configureCell(cell, atIndexPath: indexPath)
		return cell
	}

	override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
		if let indexPath = tableView.indexPathForSelectedRow,
			repo = fetchedResultsController.objectAtIndexPath(indexPath) as? Repo,
			vc = segue.destinationViewController as? RepoSettingsViewController {
			vc.repo = repo
		}
	}

	override func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
		if section==1 {
			return "Forked Repos"
		} else {
			let repo = fetchedResultsController.objectAtIndexPath(NSIndexPath(forRow: 0, inSection: section)) as! Repo
			if (repo.fork?.boolValue ?? false) {
				return "Forked Repos"
			} else {
				return "Parent Repos"
			}
		}
	}

	private var fetchedResultsController: NSFetchedResultsController {
		if let f = _fetchedResultsController {
			return f
		}

		let fetchRequest = NSFetchRequest(entityName: "Repo")
		if let text = searchField?.text where !text.isEmpty {
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

	func controllerWillChangeContent(controller: NSFetchedResultsController) {
		tableView.beginUpdates()
	}

	func controller(controller: NSFetchedResultsController, didChangeSection sectionInfo: NSFetchedResultsSectionInfo, atIndex sectionIndex: Int, forChangeType type: NSFetchedResultsChangeType) {
		switch(type) {
		case .Insert:
			tableView.insertSections(NSIndexSet(index: sectionIndex), withRowAnimation: UITableViewRowAnimation.Automatic)
		case .Delete:
			tableView.deleteSections(NSIndexSet(index: sectionIndex), withRowAnimation: UITableViewRowAnimation.Automatic)
		case .Update:
			tableView.reloadSections(NSIndexSet(index: sectionIndex), withRowAnimation: UITableViewRowAnimation.Automatic)
		default:
			break
		}
	}

	func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {

		switch(type) {
		case .Insert:
			tableView.insertRowsAtIndexPaths([newIndexPath ?? indexPath!], withRowAnimation: UITableViewRowAnimation.Automatic)
		case .Delete:
			tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation:UITableViewRowAnimation.Automatic)
		case .Update:
			if let cell = tableView.cellForRowAtIndexPath(newIndexPath ?? indexPath!) as? RepoCell {
				configureCell(cell, atIndexPath: newIndexPath ?? indexPath!)
			}
		case .Move:
			tableView.deleteRowsAtIndexPaths([indexPath!], withRowAnimation:UITableViewRowAnimation.Automatic)
			if let n = newIndexPath {
				tableView.insertRowsAtIndexPaths([n], withRowAnimation:UITableViewRowAnimation.Automatic)
			}
		}
	}

	func controllerDidChangeContent(controller: NSFetchedResultsController) {
		tableView.endUpdates()
	}

	private func configureCell(cell: RepoCell, atIndexPath: NSIndexPath) {
		let repo = fetchedResultsController.objectAtIndexPath(atIndexPath) as! Repo

		cell.titleLabel.text = repo.fullName
		cell.titleLabel.textColor = repo.shouldSync() ? UIColor.blackColor() : UIColor.lightGrayColor()
		let prTitle = prTitleForRepo(repo)
		let issuesTitle = issueTitleForRepo(repo)
		cell.prLabel!.attributedText = prTitle
		cell.issuesLabel!.attributedText = issuesTitle
		cell.accessibilityLabel = "\(title), \(prTitle.string), \(issuesTitle.string)"
	}

	private var sizer: RepoCell?
	private var heightCache = [NSIndexPath : CGFloat]()
	override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
		if sizer == nil {
			sizer = tableView.dequeueReusableCellWithIdentifier("Cell") as? RepoCell
		} else if let h = heightCache[indexPath] {
			//DLog("using cached height for %d - %d", indexPath.section, indexPath.row)
			return h
		}
		configureCell(sizer!, atIndexPath: indexPath)
		UILayoutPriorityFittingSizeLevel
		let h = sizer!.systemLayoutSizeFittingSize(CGSizeMake(tableView.bounds.width, UILayoutFittingCompressedSize.height),
			withHorizontalFittingPriority: UILayoutPriorityRequired,
			verticalFittingPriority: UILayoutPriorityFittingSizeLevel).height
		heightCache[indexPath] = h
		return h
	}

	private func titleForRepo(repo: Repo) -> NSAttributedString {
		let fullName = repo.fullName ?? "(Untitled Repo)"
		let text = (repo.inaccessible?.boolValue ?? false) ? (fullName + " (inaccessible)") : fullName
		let color = repo.shouldSync() ? UIColor.darkTextColor() : UIColor.lightGrayColor()
		return NSAttributedString(string: text, attributes: [ NSForegroundColorAttributeName: color ])
	}

	private func prTitleForRepo(repo: Repo) -> NSAttributedString {
		let a = NSMutableAttributedString()

		let prPolicy = RepoDisplayPolicy(rawValue: repo.displayPolicyForPrs?.integerValue ?? 0) ?? RepoDisplayPolicy.Hide
		let attributes = attributesForEntryWithPolicy(prPolicy)
		a.appendAttributedString(NSAttributedString(string: prPolicy.prefixName(), attributes: attributes))
		a.appendAttributedString(NSAttributedString(string: " PRs", attributes: attributes))
		return a
	}

	private func issueTitleForRepo(repo: Repo) -> NSAttributedString {
		let a = NSMutableAttributedString()

		let issuePolicy = RepoDisplayPolicy(rawValue: repo.displayPolicyForIssues?.integerValue ?? 0) ?? RepoDisplayPolicy.Hide
		let attributes = attributesForEntryWithPolicy(issuePolicy)
		a.appendAttributedString(NSAttributedString(string: issuePolicy.prefixName(), attributes: attributes))
		a.appendAttributedString(NSAttributedString(string: " Issues", attributes: attributes))
		return a
	}

	private func attributesForEntryWithPolicy(policy: RepoDisplayPolicy) -> [String : AnyObject] {
		return [
			NSFontAttributeName: UIFont.systemFontOfSize(UIFont.smallSystemFontSize()),
			NSForegroundColorAttributeName: policy.color()
		];
	}

	///////////////////////////// filtering

	private func reloadData() {

		heightCache.removeAll()

		let currentIndexes = NSIndexSet(indexesInRange: NSMakeRange(0, fetchedResultsController.sections?.count ?? 0))

		_fetchedResultsController = nil

		let dataIndexes = NSIndexSet(indexesInRange: NSMakeRange(0, fetchedResultsController.sections?.count ?? 0))

		let removedIndexes = currentIndexes.indexesPassingTest { (idx, _) -> Bool in
			return !dataIndexes.containsIndex(idx)
		}
		let addedIndexes = dataIndexes.indexesPassingTest { (idx, _) -> Bool in
			return !currentIndexes.containsIndex(idx)
		}
		let untouchedIndexes = dataIndexes.indexesPassingTest { (idx, _) -> Bool in
			return !(removedIndexes.containsIndex(idx) || addedIndexes.containsIndex(idx))
		}

		tableView.beginUpdates()
		if removedIndexes.count > 0 {
			tableView.deleteSections(removedIndexes, withRowAnimation:UITableViewRowAnimation.Automatic)
		}
		if untouchedIndexes.count > 0 {
			tableView.reloadSections(untouchedIndexes, withRowAnimation:UITableViewRowAnimation.Automatic)
		}
		if addedIndexes.count > 0 {
			tableView.insertSections(addedIndexes, withRowAnimation:UITableViewRowAnimation.Automatic)
		}
		tableView.endUpdates()
	}

	override func scrollViewWillBeginDragging(scrollView: UIScrollView) {
		if searchField!.isFirstResponder() {
			searchField!.resignFirstResponder()
		}
	}

	func textFieldShouldClear(textField: UITextField) -> Bool {
		searchTimer?.push()
		return true
	}

	func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
		if string == "\n" {
			textField.resignFirstResponder()
		} else {
			searchTimer?.push()
		}
		return true
	}
}
