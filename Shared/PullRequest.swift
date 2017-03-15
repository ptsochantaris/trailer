
import CoreData
#if os(iOS)
	import UIKit
#endif

final class PullRequest: ListableItem {

	@NSManaged var issueCommentLink: String?
	@NSManaged var issueUrl: String?
	@NSManaged var mergeable: Bool
	@NSManaged var reviewCommentLink: String?
	@NSManaged var statusesLink: String?
	@NSManaged var lastStatusNotified: String?
	@NSManaged var mergeCommitSha: String?
	@NSManaged var hasNewCommits: Bool
	@NSManaged var assignedForReview: Bool

	@NSManaged var statuses: Set<PRStatus>
	@NSManaged var reviews: Set<Review>

	class func syncPullRequests(from data: [[AnyHashable : Any]]?, in repo: Repo) {
		items(with: data, type: PullRequest.self, server: repo.apiServer) { item, info, isNewOrUpdated in
			if isNewOrUpdated {

				item.baseSync(from: info, in: repo)

				item.mergeable = info["mergeable"] as? Bool ?? true
				let newMergeCommitSha = info["merge_commit_sha"] as? String
				if item.mergeCommitSha != newMergeCommitSha {
					item.mergeCommitSha = newMergeCommitSha
					let markWithAlert = Settings.markPrsAsUnreadOnNewCommits && !(item.postSyncAction == PostSyncAction.isNew.rawValue)
					item.hasNewCommits = markWithAlert
				}

				if let linkInfo = info["_links"] as? [AnyHashable : Any] {
					item.issueCommentLink = (linkInfo["comments"] as? [AnyHashable : Any])?["href"] as? String
					item.reviewCommentLink = (linkInfo["review_comments"] as? [AnyHashable : Any])?["href"] as? String
					item.statusesLink = (linkInfo["statuses"] as? [AnyHashable : Any])?["href"] as? String
					item.issueUrl = (linkInfo["issue"] as? [AnyHashable : Any])?["href"] as? String
				}

				API.refreshesSinceLastStatusCheck[item.objectID] = nil
			}
			item.reopened = item.condition == ItemCondition.closed.rawValue
			item.condition = ItemCondition.open.rawValue
		}
	}

	#if os(iOS)
	override var searchKeywords: [String] {
		return ["PR", "Pull Request", "PRs", "Pull Requests"] + super.searchKeywords
	}
	#endif

	override var hasUnreadCommentsOrAlert: Bool {
		return super.hasUnreadCommentsOrAlert || hasNewCommits
	}

	class func active(in moc: NSManagedObjectContext, visibleOnly: Bool) -> [PullRequest] {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		if visibleOnly {
			f.predicate = NSCompoundPredicate(type: .or, subpredicates: [Section.mine.matchingPredicate, Section.participated.matchingPredicate, Section.all.matchingPredicate])
		} else {
			f.predicate = ItemCondition.open.matchingPredicate
		}
		return try! moc.fetch(f)
	}

	class func allMerged(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [PullRequest] {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let p = ItemCondition.merged.matchingPredicate
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
		return try! moc.fetch(f)
	}

	class func allClosed(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil, includeAllGroups: Bool = false) -> [PullRequest] {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		let p = ItemCondition.closed.matchingPredicate
		add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc, includeAllGroups: includeAllGroups)
		return try! moc.fetch(f)
	}

	class func countOpen(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil) -> Int {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.includesSubentities = false
		add(criterion: criterion, toFetchRequest: f, originalPredicate: ItemCondition.isOpenPredicate, in: moc)
		return try! moc.count(for: f)
	}

	class func markEverythingRead(in section: Section, in moc: NSManagedObjectContext) {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		if section != .none {
			f.predicate = section.matchingPredicate
		}
		for pr in try! moc.fetch(f) {
			pr.catchUpWithComments()
		}
	}

	override func catchUpWithComments() {
		hasNewCommits = false
		super.catchUpWithComments()
	}

	override class func badgeCount<T: PullRequest>(from fetch: NSFetchRequest<T>, in moc: NSManagedObjectContext) -> Int {
		var badgeCount = super.badgeCount(from: fetch as! NSFetchRequest<ListableItem>, in: moc)
		if Settings.markPrsAsUnreadOnNewCommits {
			for i in try! moc.fetch(fetch) {
				if i.hasNewCommits {
					badgeCount += 1
				}
			}
		}
		return badgeCount
	}

	class func badgeCount(in section: Section, in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.includesSubentities = false
		f.predicate = NSCompoundPredicate(type: .and, subpredicates: [section.matchingPredicate, includeInUnreadPredicate])
		return badgeCount(from: f, in: moc)
	}

	class func badgeCount(in moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.includesSubentities = false
		f.predicate = NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, includeInUnreadPredicate])
		return badgeCount(from: f, in: moc)
	}

	class func badgeCount(in moc: NSManagedObjectContext, criterion: GroupingCriterion? = nil) -> Int {
		let f = requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: criterion)
		return badgeCount(from: f, in: moc)
	}

	private static let _unreadOrNewCommitsPredicate = NSPredicate(format: "unreadComments > 0 or hasNewCommits == YES")
	override class var includeInUnreadPredicate: NSPredicate {
		return Settings.markPrsAsUnreadOnNewCommits ? _unreadOrNewCommitsPredicate : super.includeInUnreadPredicate
	}

	var markUnmergeable: Bool {
		if !mergeable {
			let s = sectionIndex
			if s == ItemCondition.merged.rawValue || s == ItemCondition.closed.rawValue {
				return false
			}
			if s == Section.all.rawValue && Settings.markUnmergeableOnUserSectionsOnly {
				return false
			}
			return true
		}
		return false
	}

	class func reasonForEmpty(with filterValue: String?, criterion: GroupingCriterion? = nil) -> NSAttributedString {
		let openRequestCount = PullRequest.countOpen(in: DataManager.main, criterion: criterion)
		return reasonForEmpty(with: filterValue, criterion: criterion, openItemCount: openRequestCount)
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

		#if os(iOS)
			if !mergeable {
				_subtitle.append(separator)
				var redSubtitle = lightSubtitle
				redSubtitle[NSForegroundColorAttributeName] = UIColor.red
				_subtitle.append(NSAttributedString(string: "Cannot be merged!", attributes: redSubtitle))
			}
		#endif

		return _subtitle
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

		if !mergeable {
			components.append("Cannot be merged!")
		}

		return components.joined(separator: ",")
	}

	func shouldBeCheckedForRedStatuses(in section: Section) -> Bool {
		if Settings.hidePrsThatArentPassing {
			if Settings.hidePrsThatDontPassOnlyInAll {
				return section == .all
			} else {
				return section == .mine || section == .participated || section == .all
			}
		}
		return false
	}

	var displayedStatuses: [PRStatus] {

		let rawStatuses: [PRStatus]

		let mode = Settings.statusFilteringMode
		if mode == StatusFilter.all.rawValue {
			rawStatuses = statuses.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
		} else {
			let terms = Settings.statusFilteringTerms
			if terms.count > 0 {

				let inclusive = mode == StatusFilter.include.rawValue
				// contains(a) or contains(b) or contains(c)  -vs-  not(contains(a) or contains(b) or contains(c))
				rawStatuses = statuses.filter { s in
					for t in terms {
						if let d = s.descriptionText, d.localizedCaseInsensitiveContains(t) {
							return inclusive
						}
					}
					return !inclusive
				}.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }

			} else {
				rawStatuses = statuses.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
			}
		}

		var contexts = [String : PRStatus]()
		for s in rawStatuses {
			let context = s.context ?? "//NO CONTEXT/-/"
			if let latestStatusInContext = contexts[context] {
				if (latestStatusInContext.createdAt ?? .distantPast) < (s.createdAt ?? .distantPast) {
					contexts[context] = s
				}
			} else {
				contexts[context] = s
			}
		}
		return contexts.values.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
	}

	var labelsLink: String? {
		return issueUrl?.appending(pathComponent: "labels")
	}

	var sectionName: String {
		return Section.prMenuTitles[Int(sectionIndex)]
	}
}
