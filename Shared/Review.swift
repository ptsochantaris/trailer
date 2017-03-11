
import CoreData

final class Review: DataItem {

	@NSManaged var body: String?
	@NSManaged var username: String?
	@NSManaged var state: String?

	@NSManaged var pullRequest: PullRequest
	@NSManaged var comments: Set<PRComment>

	class func syncReviews(from data: [[AnyHashable : Any]]?, withParent: PullRequest) {

		items(with: data, type: Review.self, server: withParent.apiServer) { item, info, isNewOrUpdated in
			if isNewOrUpdated {
				item.pullRequest = withParent
				item.body = info["body"] as? String
				let previousState = item.state
				let newState = info["state"] as? String
				if previousState != newState {
					if let n = newState {
						switch n {
						case "CHANGES_REQUESTED":
							if Settings.notifyOnAllReviewChangeRequests || (Settings.notifyOnReviewChangeRequests && withParent.createdByMe) {
								NotificationQueue.add(type: .changesRequested, for: withParent)
							}
						case "APPROVED":
							if Settings.notifyOnAllReviewAcceptances || (Settings.notifyOnReviewAcceptances && withParent.createdByMe) {
								NotificationQueue.add(type: .changesApproved, for: withParent)
							}
						case "DISMISSED":
							if Settings.notifyOnAllReviewDismissals || (Settings.notifyOnReviewDismissals && withParent.createdByMe) {
								NotificationQueue.add(type: .changesDismissed, for: withParent)
							}
						default: break
						}
					}
				}
				item.state = newState
				item.username = (info["user"] as? [AnyHashable : Any])?["login"] as? String
			}
		}
	}

	var shouldDisplay: Bool {
		return state == "CHANGES_REQUESTED"
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
