
import CoreData
#if os(iOS)
	import UIKit
#endif

final class PullRequest: ListableItem {

	@NSManaged var issueCommentLink: String?
	@NSManaged var issueUrl: String?
	@NSManaged var reviewCommentLink: String?
	@NSManaged var statusesLink: String?
	@NSManaged var lastStatusNotified: String?
	@NSManaged var mergeCommitSha: String?
	@NSManaged var hasNewCommits: Bool
	@NSManaged var assignedForReview: Bool
	@NSManaged var reviewers: String

	@NSManaged var statuses: Set<PRStatus>
	@NSManaged var reviews: Set<Review>

	class func syncPullRequests(from data: [[AnyHashable : Any]]?, in repo: Repo) {
		items(with: data, type: PullRequest.self, server: repo.apiServer) { item, info, isNewOrUpdated in
			if isNewOrUpdated {

				item.baseSync(from: info, in: repo)

				let newMergeCommitSha = info["merge_commit_sha"] as? String
				if item.mergeCommitSha != newMergeCommitSha {
					let hadOneBefore = item.mergeCommitSha != nil
					item.mergeCommitSha = newMergeCommitSha
					item.hasNewCommits = hadOneBefore && Settings.markPrsAsUnreadOnNewCommits && !(item.postSyncAction == PostSyncAction.isNew.rawValue)
				}

				if let linkInfo = info["_links"] as? [AnyHashable : Any] {
					item.issueCommentLink = (linkInfo["comments"] as? [AnyHashable : Any])?["href"] as? String
					item.reviewCommentLink = (linkInfo["review_comments"] as? [AnyHashable : Any])?["href"] as? String
					item.statusesLink = (linkInfo["statuses"] as? [AnyHashable : Any])?["href"] as? String
					item.issueUrl = (linkInfo["issue"] as? [AnyHashable : Any])?["href"] as? String
				}

				API.refreshesSinceLastStatusCheck[item.objectID] = nil
				API.refreshesSinceLastReactionsCheck[item.objectID] = 1
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

	override var reviewedByMe: Bool {
		for r in reviews {
			if r.isMine {
				return true
			}
		}
		return false
	}

	var shouldShowStatuses: Bool {
		return Settings.showStatusItems && (Settings.showStatusesOnAllItems || (Section(rawValue: sectionIndex)?.isLoud ?? false))
	}

	func checkAndStoreReviewAssignments(_ reviewerNames: Set<String>) -> Bool {
		reviewers = reviewerNames.joined(separator: ",")
		let assigned = reviewerNames.contains(S(apiServer.userName))
		assignedForReview = assigned
		return assigned
	}

	class func pullRequestsThatNeedReactionsToBeRefreshed(in moc: NSManagedObjectContext) -> [PullRequest] {
		let f = NSFetchRequest<PullRequest>(entityName: "PullRequest")
		f.returnsObjectsAsFaults = false
		f.predicate = NSPredicate(format: "requiresReactionRefreshFromUrl != nil")
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

	class func reasonForEmpty(with filterValue: String?, criterion: GroupingCriterion?) -> NSAttributedString {
		let openRequestCount = PullRequest.countOpen(in: DataManager.main, criterion: criterion)
		return reasonForEmpty(with: filterValue, criterion: criterion, openItemCount: openRequestCount)
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
			rawStatuses = statuses.sorted { $1.createdBefore($0) }
		} else {
			let terms = Settings.statusFilteringTerms
			if terms.count > 0 {

				let inclusive = mode == StatusFilter.include.rawValue
				// contains(a) or contains(b) or contains(c)  -vs-  not(contains(a) or contains(b) or contains(c))
				let rawUnsorted = statuses.filter {
					for t in terms {
						if let d = $0.descriptionText, d.localizedCaseInsensitiveContains(t) {
							return inclusive
						}
					}
					return !inclusive
				}
				rawStatuses = rawUnsorted.sorted { $1.createdBefore($0) }

			} else {
				rawStatuses = statuses.sorted { $1.createdBefore($0) }
			}
		}

		var contexts = [String : PRStatus]()
		for s in rawStatuses {
			let context = s.context ?? "//NO CONTEXT/-/"
			if let latestStatusInContext = contexts[context] {
				if latestStatusInContext.createdBefore(s) {
					contexts[context] = s
				}
			} else {
				contexts[context] = s
			}
		}
		return contexts.values.sorted { $0.createdBefore($1) }
	}

	var labelsLink: String? {
		return issueUrl?.appending(pathComponent: "labels")
	}

	@objc var sectionName: String {
		return Section.prMenuTitles[Int(sectionIndex)]
	}
}
