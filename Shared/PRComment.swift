import Foundation

final class PRComment: DataItem {

    @NSManaged var avatarUrl: String?
    @NSManaged var body: String?
    @NSManaged var userId: Int64
    @NSManaged var userName: String?
    @NSManaged var webUrl: String?

    @NSManaged var pullRequest: PullRequest?
	@NSManaged var issue: Issue?

	class func syncComments(from data: [[NSObject : AnyObject]]?, pullRequest: PullRequest) {
		items(with: data, type: "PRComment", server: pullRequest.apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				let c = item as! PRComment
				c.pullRequest = pullRequest
				c.fill(from: info)
				c.fastForwardIfNeeded(parent: pullRequest)
			}
		}
	}

	class func syncComments(from data: [[NSObject : AnyObject]]?, issue: Issue) {
		items(with: data, type: "PRComment", server: issue.apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				let c = item as! PRComment
				c.issue = issue
				c.fill(from: info)
				c.fastForwardIfNeeded(parent: issue)
			}
		}
	}

	func fastForwardIfNeeded(parent item: ListableItem) {
		// check if we're assigned to a just created issue, in which case we want to "fast forward" its latest comment dates to our own if we're newer
		if let commentCreation = createdAt, item.postSyncAction == PostSyncAction.noteNew.rawValue {
			if let latestReadDate = item.latestReadCommentDate, latestReadDate < commentCreation {
				item.latestReadCommentDate = commentCreation
			}
		}
	}

	func processNotifications() {
		if let item = pullRequest ?? issue, item.postSyncAction == PostSyncAction.noteUpdated.rawValue && item.isVisibleOnMenu {
			if contains(terms: ["@\(apiServer.userName!)"]) {
				if item.isSnoozing && item.shouldWakeOnMention {
					DLog("Waking up snoozed item ID %lld because of mention", item.serverId)
					item.wakeUp()
				}
				app.postNotification(type: .newMention, for: self)
			} else if !isMine {
				if item.isSnoozing && item.shouldWakeOnComment {
					DLog("Waking up snoozed item ID %lld because of posted comment", item.serverId)
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
							app.postNotification(type: .newComment, for: self)
						}
					}
				}
			}
		}
	}

	func fill(from info:[NSObject : AnyObject]) {
		body = info["body"] as? String
		webUrl = info["html_url"] as? String

		if let userInfo = info["user"] as? [NSObject : AnyObject] {
			userName = userInfo["login"] as? String
			userId = (userInfo["id"] as? NSNumber)?.int64Value ?? 0
			avatarUrl = userInfo["avatar_url"] as? String
		}

		if webUrl==nil, let links = info["links"] as? [NSObject : AnyObject] {
			webUrl = links["html"]?["href"] as? String
		}
	}

	var notificationSubtitle: String {
		return pullRequest?.title ?? issue?.title ?? "(untitled)"
	}

	var parentShouldSkipNotifications: Bool {
		if let item = pullRequest ?? issue {
			return item.shouldSkipNotifications
		}
		return false
	}

	var isMine: Bool {
		return userId == apiServer.userId
	}

	final func contains(terms: [String]) -> Bool {
		if let b = body {
			for t in terms {
				if b.localizedCaseInsensitiveContains(t) {
					return true
				}
			}
		}
		return false
	}
}
