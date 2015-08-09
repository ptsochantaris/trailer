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

	class func commentWithInfo(info:[NSObject : AnyObject], fromServer:ApiServer) -> PRComment {
		let c = DataItem.itemWithInfo(info, type: "PRComment", fromServer: fromServer) as! PRComment
		if c.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			c.body = N(info, "body") as? String
			c.position = N(info, "position") as? NSNumber
			c.path = N(info, "path") as? String
			c.url = N(info, "url") as? String
			c.webUrl = N(info, "html_url") as? String

			if let userInfo = N(info, "user") as? [NSObject : AnyObject] {
				c.userName = N(userInfo, "login") as? String
				c.userId = N(userInfo, "id") as? NSNumber
				c.avatarUrl = N(userInfo, "avatar_url") as? String
			}

			if let links = N(info, "links") as? [NSObject : AnyObject] {
				c.url = N(N(links, "self"), "href") as? String
				if c.webUrl==nil { c.webUrl = N(N(links, "html"), "href") as? String }
			}
		}
		return c
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
