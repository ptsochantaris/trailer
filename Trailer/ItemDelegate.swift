
private let _propertiesToFetch = { ()->[AnyObject] in
	let iodD = NSExpressionDescription()
	iodD.name = "objectID"
	iodD.expression = NSExpression.expressionForEvaluatedObject()
	iodD.expressionResultType = .objectIDAttributeType

	let sectionIndexD = NSExpressionDescription()
	sectionIndexD.name = "sectionIndex"
	sectionIndexD.expression = NSExpression(format: "sectionIndex")
	sectionIndexD.expressionResultType = .integer16AttributeType

	return [iodD, sectionIndexD]
}()

final class ItemDelegate: NSObject, NSTableViewDelegate, NSTableViewDataSource {

	private var itemIds = [NSObject]()
	private let type: String
	private let sections: [String]
	private let removalSections: [String]
	private let viewCriterion: GroupingCriterion?

	init(type: String, sections: [String], removeButtonsInSections: [String], viewCriterion: GroupingCriterion?) {

		self.type = type
		self.sections = sections
		self.removalSections = removeButtonsInSections
		self.viewCriterion = viewCriterion

		super.init()
		reloadData(nil)
	}

	func reloadData(_ filter: String?) {

		itemIds.removeAll(keepingCapacity: false)

		let f = ListableItem.requestForItems(ofType: type, withFilter: filter, sectionIndex: -1, criterion: viewCriterion)
		f.resultType = .dictionaryResultType
		f.fetchBatchSize = 0
		f.propertiesToFetch = _propertiesToFetch
		let allItems = try! mainObjectContext.fetch(f as! NSFetchRequest<NSDictionary>)

		itemIds.reserveCapacity(allItems.count+sections.count)

		if let firstItem = allItems.first {
			var lastSection = (firstItem["sectionIndex"] as! NSNumber).intValue
			itemIds.append(sections[lastSection])

			for item in allItems {
				let i = (item["sectionIndex"] as! NSNumber).intValue
				if lastSection < i {
					itemIds.append(Section.issueMenuTitles[i])
					lastSection = i
				}
				itemIds.append(item["objectID"] as! NSManagedObjectID)
			}
		}
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
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

	func tableView(_ tv: NSTableView, heightOfRow row: Int) -> CGFloat {
		let v = tableView(tv, viewFor: nil, row: row)
		return v!.frame.size.height
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		return itemIds.count
	}

	func itemAtRow(_ row: Int) -> ListableItem? {
		if row >= 0 && row < itemIds.count, let object = itemIds[row] as? NSManagedObjectID {
			return existingObjectWithID(object) as? ListableItem
		} else {
			return nil
		}
	}
}
