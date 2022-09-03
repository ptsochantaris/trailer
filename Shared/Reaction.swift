import CoreData

final class Reaction: DataItem {
    @NSManaged var content: String?
    @NSManaged var userName: String?
    @NSManaged var avatarUrl: String?
    @NSManaged var userNodeId: String?

    @NSManaged var pullRequest: PullRequest?
    @NSManaged var issue: Issue?
    @NSManaged var comment: PRComment?

    static func sync<T: DataItem>(from nodes: ContiguousArray<GQLNode>, for parentType: T.Type, on serverId: NSManagedObjectID, moc: NSManagedObjectContext) async {
        await syncItems(of: Reaction.self, from: nodes, on: serverId, moc: moc) { reaction, node, moc in
            guard node.created || node.updated,
                  let parentId = node.parent?.id
            else { return }

            if node.created {
                let parent = DataItem.parent(of: parentType, with: parentId, in: moc)
                reaction.pullRequest = parent as? PullRequest
                reaction.issue = parent as? Issue
                reaction.comment = parent as? PRComment
                if parent == nil {
                    DLog("Warning: Reaction without parent")
                }
            }

            let info = node.jsonPayload
            reaction.content = info["content"] as? String

            if let user = info["user"] as? [AnyHashable: Any] {
                reaction.userName = user["login"] as? String
                reaction.avatarUrl = user["avatarUrl"] as? String
                reaction.userNodeId = user["id"] as? String
            }
        }
    }

    static func syncReactions(from data: [[AnyHashable: Any]]?, comment: PRComment, moc: NSManagedObjectContext) async {
        await items(with: data, type: Reaction.self, server: comment.apiServer, moc: moc) { item, info, isNewOrUpdated in
            if isNewOrUpdated {
                item.pullRequest = nil
                item.issue = nil
                item.comment = comment
                item.fill(from: info)
            }
        }
    }

    static func syncReactions(from data: [[AnyHashable: Any]]?, parent: ListableItem, moc: NSManagedObjectContext) async {
        await items(with: data, type: Reaction.self, server: parent.apiServer, moc: moc) { item, info, isNewOrUpdated in
            if isNewOrUpdated {
                item.pullRequest = parent as? PullRequest
                item.issue = parent as? Issue
                item.comment = nil
                item.fill(from: info)
            }
        }
    }

    private func fill(from info: [AnyHashable: Any]) {
        content = info["content"] as? String
        if let user = info["user"] as? [AnyHashable: Any] {
            userName = user["login"] as? String
            avatarUrl = user["avatar_url"] as? String
            userNodeId = user["node_id"] as? String
        }
    }

    func checkNotifications() {
        if postSyncAction == PostSyncAction.isNew.rawValue, !isMine {
            if let parentItem = (pullRequest ?? issue), Settings.notifyOnItemReactions, parentItem.canBadge {
                NotificationQueue.add(type: .newReaction, for: self)

            } else if let c = comment, let parentItem = (c.pullRequest ?? c.issue), Settings.notifyOnCommentReactions, parentItem.canBadge {
                NotificationQueue.add(type: .newReaction, for: self)
            }
        }
    }

    var isMine: Bool {
        userNodeId == apiServer.userNodeId || userNodeId == apiServer.userNodeId
    }

    static func changesDetected(in reactions: Set<Reaction>, from info: [AnyHashable: Any]) -> String? {
        var counts = [String: Int]()
        for r in reactions {
            if let c = r.content {
                if let existingCount = counts[c] {
                    counts[c] = existingCount + 1
                } else {
                    counts[c] = 1
                }
            }
        }

        for type in ["+1", "-1", "laugh", "confused", "heart", "hooray", "rocket", "eyes", "thumbs_up", "thumbs_down"] {
            let serverCount = info[type] as? Int ?? 0
            let localCount = counts[type] ?? 0
            if serverCount != localCount {
                return info["url"] as? String
            }
        }

        return nil
    }

    var displaySymbol: String {
        switch S(content).lowercased() {
        case "+1", "thumbs_up": return "👍"
        case "-1", "thumbs_down": return "👎"
        case "laugh": return "😄"
        case "confused": return "😕"
        case "heart": return "❤️"
        case "hooray": return "🎉"
        case "rocket": return "🚀"
        case "eyes": return "👀"
        default: return "<unknown>"
        }
    }
}
