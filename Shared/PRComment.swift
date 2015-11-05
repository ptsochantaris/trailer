import Foundation

final class PRComment: DataItem {

    @NSManaged var avatarUrl: String?
    @NSManaged var body: String?
    @NSManaged var path: String?
    @NSManaged var position: NSNumber?
    @NSManaged var url: String?
    @NSManaged var userId: NSNumber?
    @NSManaged var userName: String?
    @NSManaged var webUrl: String?

    @NSManaged var pullRequest: PullRequest?
	@NSManaged var issue: Issue?

	class func syncCommentsFromInfo(data: [[NSObject : AnyObject]]?, pullRequest: PullRequest) {
		DataItem.itemsWithInfo(data, type: "PRComment", fromServer: pullRequest.apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				let c = item as! PRComment
				c.pullRequest = pullRequest
				c.fillFromInfo(info)
				c.fastForwardItemIfNeeded(pullRequest)
			}
		}
	}

	class func syncCommentsFromInfo(data: [[NSObject : AnyObject]]?, issue: Issue) {
		DataItem.itemsWithInfo(data, type: "PRComment", fromServer: issue.apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				let c = item as! PRComment
				c.issue = issue
				c.fillFromInfo(info)
				c.fastForwardItemIfNeeded(issue)
			}
		}
	}

	func fastForwardItemIfNeeded(item: ListableItem) {
		// check if we're assigned to a just created issue, in which case we want to "fast forward" its latest comment dates to our own if we're newer
		if let commentCreation = createdAt where (item.postSyncAction?.integerValue ?? 0) == PostSyncAction.NoteNew.rawValue {
			if let latestReadDate = item.latestReadCommentDate where latestReadDate.compare(commentCreation) == NSComparisonResult.OrderedAscending {
				item.latestReadCommentDate = commentCreation
			}
		}
	}

	func processNotifications() {
		if let item = pullRequest ?? issue where item.postSyncAction?.integerValue == PostSyncAction.NoteUpdated.rawValue && item.isVisibleOnMenu() {
			if refersToMe() {
				app.postNotificationOfType(PRNotificationType.NewMention, forItem: self)
			} else if !Settings.disableAllCommentNotifications && item.showNewComments() && !isMine() {
				if let authorName = userName {
					var blocked = false
					for blockedAuthor in Settings.commentAuthorBlacklist as [String] {
						if authorName.compare(blockedAuthor, options: [NSStringCompareOptions.CaseInsensitiveSearch, NSStringCompareOptions.DiacriticInsensitiveSearch])==NSComparisonResult.OrderedSame {
							blocked = true
							break
						}
					}
					if blocked {
						DLog("Blocked notification for user '%@' as their name is on the blacklist",authorName)
					} else {
						DLog("User '%@' not on blacklist, can post notification",authorName)
						app.postNotificationOfType(PRNotificationType.NewComment, forItem:self)
					}
				}
			}
		}
	}

	func fillFromInfo(info:[NSObject : AnyObject]) {
		body = N(info, "body") as? String
		position = N(info, "position") as? NSNumber
		path = N(info, "path") as? String
		url = N(info, "url") as? String
		webUrl = N(info, "html_url") as? String

		if let userInfo = N(info, "user") as? [NSObject : AnyObject] {
			userName = N(userInfo, "login") as? String
			userId = N(userInfo, "id") as? NSNumber
			avatarUrl = N(userInfo, "avatar_url") as? String
		}

		if let links = N(info, "links") as? [NSObject : AnyObject] {
			url = N(N(links, "self"), "href") as? String
			if webUrl==nil { webUrl = N(N(links, "html"), "href") as? String }
		}
	}

	func notificationSubtitle() -> String {
		if let pr = pullRequest, title = pr.title {
			return title
		} else if let i = issue, title = i.title {
			return title
		}
		return "(untitled)"
	}

	func isMine() -> Bool {
		return userId == apiServer.userId
	}

	func refersToMe() -> Bool {
		if let userForServer = apiServer.userName {
			let rangeOfHandle = body?.rangeOfString("@"+userForServer,
				options: [NSStringCompareOptions.CaseInsensitiveSearch, NSStringCompareOptions.DiacriticInsensitiveSearch])
			return rangeOfHandle != nil
		} else {
			return false
		}
	}

	func refersToMyTeams() -> Bool {
		if let b = body {
			for t in apiServer.teams {
				if let r = t.calculatedReferral {
					let range = b.rangeOfString(r, options: [NSStringCompareOptions.CaseInsensitiveSearch, NSStringCompareOptions.DiacriticInsensitiveSearch])
					if range != nil { return true }
				}
			}
		}
		return false
	}
}
