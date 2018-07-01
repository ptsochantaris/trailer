
import CoreData

final class Review: DataItem {

	@NSManaged var body: String?
	@NSManaged var username: String?
	@NSManaged var state: String?

	@NSManaged var pullRequest: PullRequest
	@NSManaged var comments: Set<PRComment>

	enum State: String {
		case CHANGES_REQUESTED
		case APPROVED
		case DISMISSED
	}

	class func syncReviews(from data: [[AnyHashable : Any]]?, withParent: PullRequest) {

		items(with: data, type: Review.self, server: withParent.apiServer) { item, info, isNewOrUpdated in
			if isNewOrUpdated {
				item.pullRequest = withParent
				item.body = info["body"] as? String
				item.username = (info["user"] as? [AnyHashable : Any])?["login"] as? String

				let previousState = item.state
				let newState = info["state"] as? String
				if previousState != newState {

					item.state = newState

					if !item.isMine, let ns = newState, let n = State(rawValue: ns) {
						switch n {
						case .CHANGES_REQUESTED:
							if Settings.notifyOnAllReviewChangeRequests || (Settings.notifyOnReviewChangeRequests && withParent.createdByMe) {
								NotificationQueue.add(type: .changesRequested, for: item)
							}
						case .APPROVED:
							if Settings.notifyOnAllReviewAcceptances || (Settings.notifyOnReviewAcceptances && withParent.createdByMe) {
								NotificationQueue.add(type: .changesApproved, for: item)
							}
						case .DISMISSED:
							if Settings.notifyOnAllReviewDismissals || (Settings.notifyOnReviewDismissals && withParent.createdByMe) {
								NotificationQueue.add(type: .changesDismissed, for: item)
							}
						}
					}
				}
			}
		}
	}

	class func review(with id: Int64, in moc: NSManagedObjectContext) -> Review? {
		let f = NSFetchRequest<Review>(entityName: "Review")
		f.returnsObjectsAsFaults = false
		f.includesSubentities = false
		f.predicate = NSPredicate(format: "serverId == %lld", id)
		return try! moc.fetch(f).first
	}

	var isMine: Bool {
		return username == apiServer.userName
	}

	var affectsBottomLine: Bool {
		return state == State.CHANGES_REQUESTED.rawValue || state == State.APPROVED.rawValue || state == State.DISMISSED.rawValue
	}
}

/*
	PENDING
	A review that has not yet been submitted.
	
	COMMENTED
	An informational review.
	
	APPROVED
	A review allowing the pull request to merge.
	
	CHANGES_REQUESTED
	A review blocking the pull request from merging.
	
	DISMISSED
	A review that has been dismissed.
*/
