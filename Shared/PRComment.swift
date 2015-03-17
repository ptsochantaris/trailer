import Foundation

@objc(PRComment)
class PRComment: DataItem {

    @NSManaged var avatarUrl: String?
    @NSManaged var body: String?
    @NSManaged var path: String?
    @NSManaged var position: NSNumber?
    @NSManaged var url: String?
    @NSManaged var userId: NSNumber?
    @NSManaged var userName: String?
    @NSManaged var webUrl: String?

    @NSManaged var pullRequest: PullRequest
	
	class func commentWithInfo(info:NSDictionary, fromServer:ApiServer) -> PRComment {
		let c = DataItem.itemWithInfo(info, type: "PRComment", fromServer: fromServer) as PRComment
		if c.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
			c.body = info.ofk("body") as? String
			c.position = info.ofk("position") as? NSNumber
			c.path = info.ofk("path") as? String
			c.url = info.ofk("url") as? String
			c.webUrl = info.ofk("html_url") as? String

			if let userInfo = info.ofk("user") as? NSDictionary {
				c.userName = userInfo.ofk("login") as? String
				c.userId = userInfo.ofk("id") as? NSNumber
				c.avatarUrl = userInfo.ofk("avatar_url") as? String
			}

			if let links = info.ofk("links") as? NSDictionary {
				c.url = links.ofk("self")?.ofk("href") as? String
				if c.webUrl==nil { c.webUrl = links.ofk("html")?.ofk("href") as? String }
			}
		}
		return c
	}

	func isMine() -> Bool {
		return userId == apiServer.userId
	}

	func refersToMe() -> Bool {
		if let userForServer = apiServer.userName {
			let rangeOfHandle = body?.rangeOfString("@"+userForServer,
				options: NSStringCompareOptions.CaseInsensitiveSearch|NSStringCompareOptions.DiacriticInsensitiveSearch)
			return rangeOfHandle != nil
		} else {
			return false
		}
	}
}
