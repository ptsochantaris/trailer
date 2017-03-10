
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
				item.state = info["state"] as? String
				item.username = (info["user"] as? [AnyHashable : Any])?["login"] as? String
			}
		}
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
