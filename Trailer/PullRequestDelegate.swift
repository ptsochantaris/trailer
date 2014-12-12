
class PullRequestDelegate: NSObject, NSTableViewDelegate, NSTableViewDataSource {

	private var pullRequestIds: [NSObject]
	private let sectionDelegate: SectionHeaderDelegate

	init(sectionDelegate: SectionHeaderDelegate) {
		self.sectionDelegate = sectionDelegate
		self.pullRequestIds = [NSObject]()
		super.init()
		reloadData(nil)
	}

	func reloadData(filter: String?) {
		let f = PullRequest.requestForPullRequestsWithFilter(filter)
		f.resultType = NSFetchRequestResultType.ManagedObjectIDResultType
		pullRequestIds = mainObjectContext.executeFetchRequest(f, error: nil) as [NSManagedObjectID]
	}

	func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let object = pullRequestIds[row]
		if object.isKindOfClass(NSManagedObjectID) {
			let pr = mainObjectContext.existingObjectWithID(object as NSManagedObjectID, error: nil) as PullRequest?
			return PRItemView(pullRequest: pr!)
		} else {
			return SectionHeader(delegate: sectionDelegate, title: object as String)
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
