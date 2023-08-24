import CoreData
import Lista
import TrailerQL

final class Reaction: DataItem {
    @NSManaged var content: String?
    @NSManaged var userName: String?
    @NSManaged var avatarUrl: String?
    @NSManaged var userNodeId: String?

    @NSManaged var pullRequest: PullRequest?
    @NSManaged var issue: Issue?
    @NSManaged var comment: PRComment?

    override class var typeName: String { "Reaction" }

    static func sync(from nodes: Lista<Node>, for parentType: (some DataItem).Type, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: Reaction.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { reaction, node in
            guard node.created || node.updated,
                  let parentId = node.parent?.id
            else { return }

            if node.created {
                let parent = parentType.asParent(with: parentId, in: moc, parentCache: parentCache)
                reaction.pullRequest = parent?.asPr
                reaction.issue = parent?.asIssue
                reaction.comment = parent?.asComment
                if parent == nil {
                    Logging.log("Warning: Reaction without parent")
                }
            }

            let info = node.jsonPayload
            reaction.content = info["content"] as? String

            if let user = info["user"] as? JSON {
                reaction.userName = user["login"] as? String
                reaction.avatarUrl = user["avatarUrl"] as? String
                reaction.userNodeId = user["id"] as? String
            }
        }
    }

    override var asReaction: Reaction? {
        self
    }

    static func syncReactions(from data: [JSON]?, commentId: NSManagedObjectID, serverId: NSManagedObjectID, moc: NSManagedObjectContext) async {
        await v3items(with: data, type: Reaction.self, serverId: serverId, moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated, let parent = try? syncMoc.existingObject(with: commentId) as? PRComment {
                item.pullRequest = nil
                item.issue = nil
                item.comment = parent
                item.fill(from: info)
            }
        }
    }

    static func syncReactions(from data: [JSON]?, parentId: NSManagedObjectID, serverId: NSManagedObjectID, moc: NSManagedObjectContext) async {
        await v3items(with: data, type: Reaction.self, serverId: serverId, moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated {
                let parent = try! syncMoc.existingObject(with: parentId) as? ListableItem
                item.pullRequest = parent?.asPr
                item.issue = parent?.asIssue
                item.comment = nil
                item.fill(from: info)
            }
        }
    }

    private func fill(from info: JSON) {
        content = info["content"] as? String
        if let user = info["user"] as? JSON {
            userName = user["login"] as? String
            avatarUrl = user["avatar_url"] as? String
            userNodeId = user["node_id"] as? String
        }
    }

    func shouldContributeToCount(since: Date, settings: Settings.Cache) -> Bool {
        guard !isMine,
              let userName,
              let createdAt,
              createdAt > since
        else {
            return false
        }
        return !settings.excludedCommentAuthors.contains(userName.comparableForm)
    }

    @MainActor
    func checkNotifications(settings: Settings.Cache) {
        if postSyncAction == PostSyncAction.isNew.rawValue, !isMine {
            if settings.notifyOnItemReactions, let parentItem = (pullRequest ?? issue), parentItem.canBadge(settings: settings) {
                NotificationQueue.add(type: .newReaction, for: self)

            } else if settings.notifyOnCommentReactions, let comment, let parentItem = (comment.pullRequest ?? comment.issue), parentItem.canBadge(settings: settings) {
                NotificationQueue.add(type: .newReaction, for: self)
            }
        }
    }

    var isMine: Bool {
        userNodeId == apiServer.userNodeId
    }

    static func changesDetected(in reactions: Set<Reaction>, from info: JSON) -> String? {
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
        switch content.orEmpty.lowercased() {
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
