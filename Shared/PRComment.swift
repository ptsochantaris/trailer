import Foundation

final class PRComment: DataItem {

    @NSManaged var avatarUrl: String?
    @NSManaged var body: String?
    @NSManaged var userId: Int64
    @NSManaged var userName: String?
    @NSManaged var webUrl: String?

    @NSManaged var pullRequest: PullRequest?
	@NSManaged var issue: Issue?
	@NSManaged var review: Review?

	class func syncComments(from data: [[AnyHashable : Any]]?, pullRequest: PullRequest) {
		items(with: data, type: PRComment.self, server: pullRequest.apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				item.pullRequest = pullRequest
				item.fill(from: info)
				item.fastForwardIfNeeded(parent: pullRequest)
			}
		}
	}

	class func syncComments(from data: [[AnyHashable : Any]]?, issue: Issue) {
		items(with: data, type: PRComment.self, server: issue.apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				item.issue = issue
				item.fill(from: info)
				item.fastForwardIfNeeded(parent: issue)
			}
		}
	}

	class func syncComments(from data: [[AnyHashable : Any]]?, review: Review) {
		items(with: data, type: PRComment.self, server: review.apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				let pr = review.pullRequest
				item.review = review
				item.pullRequest = pr
				item.fill(from: info)
				item.fastForwardIfNeeded(parent: pr)
			}
		}
	}

	func fastForwardIfNeeded(parent item: ListableItem) {
		// Check if we're assigned to a newly created issue, in which case we want to "fast forward" its latest comment date to our own, if ours is newer
		if let commentCreation = createdAt, item.postSyncAction == PostSyncAction.isNew.rawValue {
			if let latestReadDate = item.latestReadCommentDate, latestReadDate < commentCreation {
				item.latestReadCommentDate = commentCreation
			}
		}
	}

	func processNotifications() {
		if let item = parent, item.postSyncAction == PostSyncAction.isUpdated.rawValue && item.isVisibleOnMenu {
			if contains(terms: ["@\(apiServer.userName!)"]) {
				if item.isSnoozing && item.shouldWakeOnMention {
					DLog("Waking up snoozed item ID %@ because of mention", item.serverId)
					item.wakeUp()
				}
				NotificationQueue.add(type: .newMention, for: self)
			} else if !isMine {
				if item.isSnoozing && item.shouldWakeOnComment {
					DLog("Waking up snoozed item ID %@ because of posted comment", item.serverId)
					item.wakeUp()
				}
				let notifyForNewComments = item.sectionIndex != Section.all.rawValue || Settings.showCommentsEverywhere
				if notifyForNewComments && !Settings.disableAllCommentNotifications && !isMine {
					if let authorName = userName {
						var blocked = false
						for blockedAuthor in Settings.commentAuthorBlacklist as [String] {
							if authorName.compare(blockedAuthor, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
								blocked = true
								break
							}
						}
						if blocked {
							DLog("Blocked notification for user '%@' as their name is on the blacklist", authorName)
						} else {
							DLog("User '%@' not on blacklist, can post notification", authorName)
							NotificationQueue.add(type: .newComment, for: self)
						}
					}
				}
			}
		}
	}

	func fill(from info: [AnyHashable : Any]) {
		body = info["body"] as? String

		if let id = info["pull_request_review_id"] as? Int64, let moc = managedObjectContext, let r = Review.review(with: id, in: moc) {
			review = r
		} else {
			review = nil
		}

		if let userInfo = info["user"] as? [AnyHashable : Any] {
			userName = userInfo["login"] as? String
			userId = userInfo["id"] as? Int64 ?? 0
			avatarUrl = userInfo["avatar_url"] as? String
		}

		if let href = info["html_url"] as? String {
			webUrl = href

		} else if let links = info["_links"] as? [AnyHashable : Any],
			let html = links["html"] as? [AnyHashable : Any],
			let href = html["href"] as? String {

			webUrl = href
		}
	}

	var notificationSubtitle: String {
		return pullRequest?.title ?? issue?.title ?? "(untitled)"
	}

	var parent: ListableItem? {
		return pullRequest ?? issue
	}

	var isMine: Bool {
		return userId == apiServer.userId
	}

	final func contains(terms: [String]) -> Bool {
		if let b = body {
			for t in terms {
				if !t.isEmpty && b.localizedCaseInsensitiveContains(t) {
					return true
				}
			}
		}
		return false
	}
}
