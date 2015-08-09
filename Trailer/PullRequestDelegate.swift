
final class PullRequestDelegate: NSObject, NSTableViewDelegate, NSTableViewDataSource {

	private var pullRequestIds: [NSObject]

	override init() {
		pullRequestIds = [NSObject]()
		super.init()
		reloadData(nil)
	}

	func reloadData(filter: String?) {

		pullRequestIds.removeAll(keepCapacity: false)

		let f = ListableItem.requestForItemsOfType("PullRequest", withFilter: filter, sectionIndex: -1)
		let allPrs = try! mainObjectContext.executeFetchRequest(f) as! [PullRequest]

		if let firstPr = allPrs.first {
			var lastSection = firstPr.sectionIndex!.integerValue
			pullRequestIds.append(PullRequestSection.prMenuTitles[lastSection])

			for pr in allPrs {
				let i = pr.sectionIndex!.integerValue
				if lastSection < i {
					pullRequestIds.append(PullRequestSection.prMenuTitles[i])
					lastSection = i
				}
				pullRequestIds.append(pr.objectID)
			}
		}
	}

	func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let object = pullRequestIds[row]
		if object.isKindOfClass(NSManagedObjectID) {
			let pr = existingObjectWithID(object as! NSManagedObjectID) as! PullRequest
			return PullRequestCell(pullRequest: pr)
		} else {
			let title = object as! String
			let showButton = (title == PullRequestSection.Merged.prMenuName() || title == PullRequestSection.Closed.prMenuName())
			return SectionHeader(title: title, showRemoveAllButton: showButton)
		}
	}

	func tableView(tv: NSTableView, heightOfRow row: Int) -> CGFloat {
		let prView = tableView(tv, viewForTableColumn: nil, row: row)
		return prView!.frame.size.height
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return pullRequestIds.count
	}

	func pullRequestAtRow(row: Int) -> PullRequest? {
		if let object = pullRequestIds[row] as? NSManagedObjectID {
			return existingObjectWithID(object) as? PullRequest
		} else {
			return nil
		}
	}
}
