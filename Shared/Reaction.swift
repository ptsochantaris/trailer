import CoreData
import Lista
import TrailerQL
import TrailerJson

final class Reaction: DataItem {
    @NSManaged var content: String?
    @NSManaged var userName: String?
    @NSManaged var avatarUrl: String?
    @NSManaged var userNodeId: String?

    @NSManaged var pullRequest: PullRequest?
    @NSManaged var issue: Issue?
    @NSManaged var comment: PRComment?

    override static var typeName: String { "Reaction" }

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
            reaction.content = info.potentialString(named: "content")

            if let user = info.potentialObject(named: "user") {
                reaction.userName = user.potentialString(named: "login")
                reaction.avatarUrl = user.potentialString(named: "avatarUrl")
                reaction.userNodeId = user.potentialString(named: "id")
            }
        }
    }

    override var asReaction: Reaction? {
        self
    }

    static func syncReactions(from data: [TypedJson.Entry]?, commentId: NSManagedObjectID, serverId: NSManagedObjectID, moc: NSManagedObjectContext) async {
        await v3items(with: data, type: Reaction.self, serverId: serverId, moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated, let parent = try? syncMoc.existingObject(with: commentId) as? PRComment {
                item.pullRequest = nil
                item.issue = nil
                item.comment = parent
                item.fill(from: info)
            }
        }
    }

    static func syncReactions(from data: [TypedJson.Entry]?, parentId: NSManagedObjectID, serverId: NSManagedObjectID, moc: NSManagedObjectContext) async {
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

    private func fill(from info: TypedJson.Entry) {
        content = info.potentialString(named: "content")
        if let user = info.potentialObject(named: "user") {
            userName = user.potentialString(named: "login")
            avatarUrl = user.potentialString(named: "avatar_url")
            userNodeId = user.potentialString(named: "node_id")
        }
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

    static func changesDetected(in reactions: Set<Reaction>, from info: TypedJson.Entry) -> String? {
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
            let serverCount = info.potentialInt(named: type) ?? 0
            let localCount = counts[type] ?? 0
            if serverCount != localCount {
                return info.potentialString(named: "url")
            }
        }

        return nil
    }

    var displaySymbol: String {
        switch content.orEmpty.lowercased() {
        case "+1", "thumbs_up": "👍"
        case "-1", "thumbs_down": "👎"
        case "laugh": "😄"
        case "confused": "😕"
        case "heart": "❤️"
        case "hooray": "🎉"
        case "rocket": "🚀"
        case "eyes": "👀"
        default: "<unknown>"
        }
    }
}
