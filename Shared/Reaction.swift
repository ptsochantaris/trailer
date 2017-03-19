
final class Reaction: DataItem {

	@NSManaged var content: String?
	@NSManaged var userName: String?
	@NSManaged var avatarUrl: String?
	@NSManaged var userId: Int64

	@NSManaged var pullRequest: PullRequest?
	@NSManaged var issue: Issue?
	@NSManaged var comment: PRComment?

	class func syncReactions(from data: [[AnyHashable : Any]]?, comment: PRComment) {
		items(with: data, type: Reaction.self, server: comment.apiServer) { item, info, isNewOrUpdated in
			item.comment = comment
			if isNewOrUpdated {
				item.fill(from: info)
			}
		}
	}

	class func syncReactions(from data: [[AnyHashable : Any]]?, parent: ListableItem) {
		items(with: data, type: Reaction.self, server: parent.apiServer) { item, info, isNewOrUpdated in
			if let p = parent as? PullRequest {
				item.pullRequest = p
			} else {
				item.issue = parent as? Issue
			}
			if isNewOrUpdated {
				item.fill(from: info)
			}
		}
	}

	private func fill(from info: [AnyHashable : Any]) {
		content = info["content"] as? String
		if let user = info["user"] as? [AnyHashable:Any] {
			userName = user["login"] as? String
			avatarUrl = user["avatar_url"] as? String
			userId = user["id"] as? Int64 ?? 0
		}
		if postSyncAction == PostSyncAction.isNew.rawValue && userId != apiServer.userId {
			if let parentItem = (pullRequest ?? issue), Settings.notifyOnItemReactions, parentItem.postSyncAction != PostSyncAction.isNew.rawValue {

				if Settings.showCommentsEverywhere || (parentItem.sectionIndex != Section.all.rawValue && parentItem.sectionIndex != Section.none.rawValue) {
					NotificationQueue.add(type: .newReaction, for: self)
				}

			} else if let c = comment, let parentItem = (c.pullRequest ?? c.issue), Settings.notifyOnCommentReactions, parentItem.postSyncAction != PostSyncAction.isNew.rawValue {

				if Settings.showCommentsEverywhere || (parentItem.sectionIndex != Section.all.rawValue && parentItem.sectionIndex != Section.none.rawValue) {
					NotificationQueue.add(type: .newReaction, for: self)
				}

			}
		}
		postSyncAction = PostSyncAction.doNothing.rawValue
	}

	class func changesDetected(in reactions: Set<Reaction>, from info: [AnyHashable : Any]) -> String? {
		var counts = [String:Int]()
		for r in reactions {
			if let c = r.content {
				if let existingCount = counts[c] {
					counts[c] = existingCount + 1
				} else {
					counts[c] = 1
				}
			}
		}

		for type in ["+1", "-1", "laugh", "confused", "heart", "hooray"] {
			let serverCount = info[type] as? Int ?? 0
			let localCount = counts[type] ?? 0
			if serverCount != localCount {
				return info["url"] as? String
			}
		}

		return nil
	}

	var displaySymbol: String {
		switch S(content) {
		case "+1": return "👍"
		case "-1": return "👎"
		case "laugh": return "😄"
		case "confused": return "😕"
		case "heart": return "❤️"
		case "hooray": return "🎉"
		default: return "<unknown>"
		}
	}
}
