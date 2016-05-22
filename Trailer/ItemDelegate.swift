
final class ItemDelegate: NSObject, NSTableViewDelegate, NSTableViewDataSource {

	private var itemIds = [NSObject]()
	private let type: String
	private let sections: [String]
	private let removalSections: [String]

	init(type: String, sections: [String], removeButtonsInSections: [String]) {
		self.type = type
		self.sections = sections
		self.removalSections = removeButtonsInSections
		super.init()
		reloadData(nil)
	}

	func reloadData(filter: String?) {

		itemIds.removeAll(keepCapacity: false)

		let f = ListableItem.requestForItemsOfType(type, withFilter: filter, sectionIndex: -1)
		let allItems = try! mainObjectContext.executeFetchRequest(f) as! [ListableItem]

		if let firstItem = allItems.first {
			var lastSection = firstItem.sectionIndex!.integerValue
			itemIds.append(sections[lastSection])

			for item in allItems {
				let i = item.sectionIndex!.integerValue
				if lastSection < i {
					itemIds.append(Section.issueMenuTitles[i])
					lastSection = i
				}
				itemIds.append(item.objectID)
			}
		}
	}

	func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
		let object = itemIds[row]
		if let o = object as? NSManagedObjectID {
			if let i = existingObjectWithID(o) {
				if let pr = i as? PullRequest {
					return PullRequestCell(pullRequest: pr)
				} else if let issue = i as? Issue {
					return IssueCell(issue: issue)
				}
			}
		} else if let title = object as? String {
			return SectionHeader(title: title, showRemoveAllButton: removalSections.contains(title))
		}
		return nil
	}

	func tableView(tv: NSTableView, heightOfRow row: Int) -> CGFloat {
		let v = tableView(tv, viewForTableColumn: nil, row: row)
		return v!.frame.size.height
	}

	func numberOfRowsInTableView(tableView: NSTableView) -> Int {
		return itemIds.count
	}

	func itemAtRow(row: Int) -> ListableItem? {
		if row >= 0 && row < itemIds.count, let object = itemIds[row] as? NSManagedObjectID {
			return existingObjectWithID(object) as? ListableItem
		} else {
			return nil
		}
	}
}
