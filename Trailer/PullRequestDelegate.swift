
class PullRequestDelegate: NSObject, NSTableViewDelegate, NSTableViewDataSource {

	private var pullRequestIds: [NSObject]

	override init() {
		pullRequestIds = [NSObject]()
		super.init()
		reloadData(nil)
	}

	func reloadData(filter: String?) {

		pullRequestIds = [NSObject]()

		let f = PullRequest.requestForPullRequestsWithFilter(filter)
		let allPrs = mainObjectContext.executeFetchRequest(f, error: nil) as [PullRequest]

		if let firstPr = allPrs.first {
			var lastSection = firstPr.sectionIndex!.integerValue
			pullRequestIds.append(kPullRequestSectionNames[lastSection] as String)

			for pr in allPrs {
				let i = pr.sectionIndex!.integerValue
				if lastSection < i {
					pullRequestIds.append(kPullRequestSectionNames[i] as String)
					lastSection = i
				}
				pullRequestIds.append(pr.objectID)
			}
		}
	}

	func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let object = pullRequestIds[row]
		if object.isKindOfClass(NSManagedObjectID) {
			let pr = mainObjectContext.existingObjectWithID(object as NSManagedObjectID, error: nil) as PullRequest?
			return PRItemView(pullRequest: pr!)
		} else {
			let title = object as String
			let showButton = (title == kPullRequestSectionNames[PullRequestSection.Merged.rawValue] as String)
				|| (title == kPullRequestSectionNames[PullRequestSection.Closed.rawValue] as String)
			return SectionHeader(title: title, showRemoveAllButton: showButton)
		}
	}

	func tableView(tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		let prView = self.tableView(tableView, viewForTableColumn: nil, row: row)
		return prView!.frame.size.height
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return pullRequestIds.count
	}

	func pullRequestAtRow(row: Int) -> PullRequest? {
		let object = pullRequestIds[row]
		if object.isKindOfClass(NSManagedObjectID) {
			return mainObjectContext.existingObjectWithID(object as NSManagedObjectID, error: nil) as PullRequest?
		} else {
			return nil;
		}
	}
}
