
import CoreData
#if os(iOS)
	import UIKit
#endif

final class Issue: ListableItem {

	@NSManaged var commentsLink: String?

	class func syncIssues(from data: [[AnyHashable : Any]]?, in repo: Repo) {
		let filteredData = data?.filter { $0["pull_request"] == nil } // don't sync issues which are pull requests, they are already synced
		items(with: filteredData, type: Issue.self, server: repo.apiServer, prefetchRelationships: ["labels"]) { item, info, isNewOrUpdated in

			if isNewOrUpdated {

				item.baseSync(from: info, in: repo)

				if let R = repo.fullName {
					item.commentsLink = "/repos/\(R)/issues/\(item.number)/comments"
				}

				for l in item.labels {
					l.postSyncAction = PostSyncAction.delete.rawValue
				}

				if Settings.showLabels, let labelList = info["labels"] as? [[AnyHashable : Any]] {
					PRLabel.syncLabels(from: labelList, withParent: item)
				}
			}
			item.reopened = item.condition == ItemCondition.closed.rawValue
			item.condition = ItemCondition.open.rawValue
		}
	}

	class func reasonForEmpty(with filterValue: String?, criterion: GroupingCriterion?) -> NSAttributedString {
		let openIssueCount = Issue.countOpen(in: DataManager.main, criterion: criterion)
		return reasonForEmpty(with: filterValue, criterion: criterion, openItemCount: openIssueCount)
	}

	#if os(iOS)
	override var searchKeywords: [String] {
		return ["Issue", "Issues"] + super.searchKeywords
	}
	#endif

	class func markEverythingRead(in section: Section, in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		if section != .none {
			f.predicate = section.matchingPredicate
		}
		for pr in try! moc.fetch(f) {
			pr.catchUpWithComments()
		}
	}

	class func badgeCount(in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.includesSubentities = false
		f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, includeInUnreadPredicate])
		return badgeCount(from: f, in: moc)
	}

	class func badgeCount(in moc: NSManagedObjectContext, criterion: GroupingCriterion?) -> Int {
		let f = requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: criterion)
		return badgeCount(from: f, in: moc)
	}

	class func countOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil) -> Int {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.includesSubentities = false
		add(criterion: criterion, toFetchRequest: f, originalPredicate: ItemCondition.isOpenPredicate, in: moc)
		return try! moc.count(for: f)
	}

	func subtitle(with font: FONT_CLASS, lightColor: COLOR_CLASS, darkColor: COLOR_CLASS) -> NSMutableAttributedString {
		let _subtitle = NSMutableAttributedString()
		let p = NSMutableParagraphStyle()
		#if os(iOS)
			p.lineHeightMultiple = 1.3
		#endif

		let lightSubtitle = [NSForegroundColorAttributeName: lightColor, NSFontAttributeName: font, NSParagraphStyleAttributeName: p]

		#if os(iOS)
			let separator = NSAttributedString(string:"\n", attributes: lightSubtitle)
		#elseif os(OSX)
			let separator = NSAttributedString(string:"   ", attributes: lightSubtitle)
		#endif

		if Settings.showReposInName {
			if let n = repo.fullName {
				var darkSubtitle = lightSubtitle
				darkSubtitle[NSForegroundColorAttributeName] = darkColor
				_subtitle.append(NSAttributedString(string: n, attributes: darkSubtitle))
				_subtitle.append(separator)
			}
		}

		if let l = userLogin {
			_subtitle.append(NSAttributedString(string: "@\(l)", attributes: lightSubtitle))
			_subtitle.append(separator)
		}

		if Settings.showCreatedInsteadOfUpdated {
			_subtitle.append(NSAttributedString(string: itemDateFormatter.string(from: createdAt!), attributes: lightSubtitle))
		} else {
			_subtitle.append(NSAttributedString(string: itemDateFormatter.string(from: updatedAt!), attributes: lightSubtitle))
		}
		
		return _subtitle
	}

	var sectionName: String {
		return Section.issueMenuTitles[Int(sectionIndex)]
	}

	class func allClosed(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [Issue] {
		let f = NSFetchRequest<Issue>(entityName: "Issue")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let p = ItemCondition.closed.matchingPredicate
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
		return try! moc.fetch(f)
	}

	var accessibleSubtitle: String {
		var components = [String]()

		if Settings.showReposInName {
			components.append("Repository: \(S(repo.fullName))")
		}

		if let l = userLogin { components.append("Author: \(l)") }

		if Settings.showCreatedInsteadOfUpdated {
			components.append("Created \(itemDateFormatter.string(from: createdAt!))")
		} else {
			components.append("Updated \(itemDateFormatter.string(from: updatedAt!))")
		}

		return components.joined(separator: ",")
	}
}
