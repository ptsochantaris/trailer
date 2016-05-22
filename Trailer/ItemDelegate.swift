
private let _propertiesToFetch = { ()->[AnyObject] in
	let iodD = NSExpressionDescription()
	iodD.name = "objectID"
	iodD.expression = NSExpression.expressionForEvaluatedObject()
	iodD.expressionResultType = .ObjectIDAttributeType

	let sectionIndexD = NSExpressionDescription()
	sectionIndexD.name = "sectionIndex"
	sectionIndexD.expression = NSExpression(format: "sectionIndex")
	sectionIndexD.expressionResultType = .Integer16AttributeType

	return [iodD, sectionIndexD]
}()

final class ItemDelegate: NSObject, NSTableViewDelegate, NSTableViewDataSource {

	private var itemIds = [NSObject]()
	private let type: String
	private let sections: [String]
	private let removalSections: [String]
	private let apiServerId: NSManagedObjectID?

	init(type: String, sections: [String], removeButtonsInSections: [String], apiServer: ApiServer?) {

		self.type = type
		self.sections = sections
		self.removalSections = removeButtonsInSections
		self.apiServerId = apiServer?.objectID

		super.init()
		reloadData(nil)
	}

	func reloadData(filter: String?) {

		itemIds.removeAll(keepCapacity: false)

		let f = ListableItem.requestForItemsOfType(type, withFilter: filter, sectionIndex: -1, apiServerId: apiServerId)
		f.resultType = .DictionaryResultType
		f.fetchBatchSize = 0
		f.propertiesToFetch = _propertiesToFetch
		let allItems = try! mainObjectContext.executeFetchRequest(f) as! [NSDictionary]

		itemIds.reserveCapacity(allItems.count+sections.count)

		if let firstItem = allItems.first {
			var lastSection = (firstItem["sectionIndex"] as! NSNumber).integerValue
			itemIds.append(sections[lastSection])

			for item in allItems {
				let i = (item["sectionIndex"] as! NSNumber).integerValue
				if lastSection < i {
					itemIds.append(Section.issueMenuTitles[i])
					lastSection = i
				}
				itemIds.append(item["objectID"] as! NSManagedObjectID)
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
