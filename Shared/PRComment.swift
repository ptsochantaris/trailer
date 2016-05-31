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
		itemsWithInfo(data, type: "PRComment", fromServer: pullRequest.apiServer) { item, info, newOrUpdated in
			if newOrUpdated {
				let c = item as! PRComment
				c.pullRequest = pullRequest
				c.fillFromInfo(info)
				c.fastForwardItemIfNeeded(pullRequest)
			}
		}
	}

	class func syncCommentsFromInfo(data: [[NSObject : AnyObject]]?, issue: Issue) {
		itemsWithInfo(data, type: "PRComment", fromServer: issue.apiServer) { item, info, newOrUpdated in
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
			if let latestReadDate = item.latestReadCommentDate where latestReadDate.compare(commentCreation) == .OrderedAscending {
				item.latestReadCommentDate = commentCreation
			}
		}
	}

	func processNotifications() {
		if let item = pullRequest ?? issue where item.postSyncAction?.integerValue == PostSyncAction.NoteUpdated.rawValue && item.isVisibleOnMenu {
			if refersToMe {
				if item.isSnoozing && Settings.snoozeWakeOnMention {
					DLog("Waking up snoozed item ID %@ because of mention", item.serverId)
					item.wakeUp()
				}
				app.postNotificationOfType(.NewMention, forItem: self)
			} else if !isMine {
				if item.isSnoozing && Settings.snoozeWakeOnComment {
					DLog("Waking up snoozed item ID %@ because of posted comment", item.serverId)
					item.wakeUp()
				}
				if !Settings.disableAllCommentNotifications && item.showNewComments && !isMine {
					if let authorName = userName {
						var blocked = false
						for blockedAuthor in Settings.commentAuthorBlacklist as [String] {
							if authorName.compare(blockedAuthor, options: [.CaseInsensitiveSearch, .DiacriticInsensitiveSearch]) == .OrderedSame {
								blocked = true
								break
							}
						}
						if blocked {
							DLog("Blocked notification for user '%@' as their name is on the blacklist",authorName)
						} else {
							DLog("User '%@' not on blacklist, can post notification",authorName)
							app.postNotificationOfType(.NewComment, forItem:self)
						}
					}
				}
			}
		}
	}

	func fillFromInfo(info:[NSObject : AnyObject]) {
		body = info["body"] as? String
		position = info["position"] as? NSNumber
		path = info["path"] as? String
		url = info["url"] as? String
		webUrl = info["html_url"] as? String

		if let userInfo = info["user"] as? [NSObject : AnyObject] {
			userName = userInfo["login"] as? String
			userId = userInfo["id"] as? NSNumber
			avatarUrl = userInfo["avatar_url"] as? String
		}

		if let links = info["links"] as? [NSObject : AnyObject] {
			url = links["self"]?["href"] as? String
			if webUrl==nil { webUrl = links["html"]?["href"] as? String }
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

	var refersToMe: Bool {
		if let userForServer = apiServer.userName where userId != apiServer.userId { // Ignore self-references
			let rangeOfHandle = body?.rangeOfString("@\(userForServer)",
				options: [.CaseInsensitiveSearch, .DiacriticInsensitiveSearch])
			return rangeOfHandle != nil
		}
		return false
	}

	var refersToMyTeams: Bool {
		if let b = body {
			for t in apiServer.teams {
				if let r = t.calculatedReferral {
					let range = b.rangeOfString(r, options: [.CaseInsensitiveSearch, .DiacriticInsensitiveSearch])
					if range != nil { return true }
				}
			}
		}
		return false
	}
}
