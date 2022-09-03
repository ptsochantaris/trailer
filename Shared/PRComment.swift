import CoreData
import Foundation

final class PRComment: DataItem {
    @NSManaged var avatarUrl: String?
    @NSManaged var body: String?
    @NSManaged var userNodeId: String?
    @NSManaged var userName: String?
    @NSManaged var webUrl: String?
    @NSManaged var reactionsUrl: String?
    @NSManaged var pendingReactionScan: Bool

    @NSManaged var pullRequest: PullRequest?
    @NSManaged var issue: Issue?
    @NSManaged var review: Review?

    @NSManaged var reactions: Set<Reaction>

    static func sync(from nodes: ContiguousArray<GQLNode>, on serverId: NSManagedObjectID, moc: NSManagedObjectContext) async {
        await syncItems(of: PRComment.self, from: nodes, on: serverId, moc: moc) { comment, node, moc in
            guard node.created || node.updated,
                  let parentId = node.parent?.id
            else { return }

            if node.created {
                let review = DataItem.parent(of: Review.self, with: parentId, in: moc)
                comment.review = review

                let pr = DataItem.parent(of: PullRequest.self, with: parentId, in: moc)
                if pr == nil, review != nil {
                    comment.pullRequest = review?.pullRequest
                } else {
                    comment.pullRequest = pr
                }

                let issue = DataItem.parent(of: Issue.self, with: parentId, in: moc)
                comment.issue = issue

                if issue == nil, pr == nil, review == nil {
                    DLog("Warning: PRComment without parent")
                }
            }

            let info = node.jsonPayload
            comment.body = info["body"] as? String
            comment.webUrl = info["url"] as? String

            if let userInfo = info["author"] as? [AnyHashable: Any] {
                comment.userName = userInfo["login"] as? String
                comment.userNodeId = userInfo["id"] as? String
                comment.avatarUrl = userInfo["avatarUrl"] as? String
            }
        }
    }

    static func syncComments(from data: [[AnyHashable: Any]]?, parent: ListableItem, moc: NSManagedObjectContext) async {
        await items(with: data, type: PRComment.self, server: parent.apiServer, moc: moc) { item, info, newOrUpdated in
            if newOrUpdated {
                item.pullRequest = parent as? PullRequest
                item.issue = parent as? Issue
                item.fill(from: info)
                item.fastForwardIfNeeded(parent: parent)
                item.reactionsUrl = (info["reactions"] as? [AnyHashable: Any])?["url"] as? String
            }
        }
    }

    private func fastForwardIfNeeded(parent item: ListableItem) {
        // Check if we're assigned to a newly created issue, in which case we want to "fast forward" its latest comment date to our own, if ours is newer
        if let commentCreation = createdAt, item.postSyncAction == PostSyncAction.isNew.rawValue {
            if let latestReadDate = item.latestReadCommentDate, latestReadDate < commentCreation {
                item.latestReadCommentDate = commentCreation
            }
        }
    }

    func processNotifications() {
        guard let parent = parent, parent.canBadge else {
            return
        }
        if contains(terms: ["@\(apiServer.userName!)"]) {
            if parent.isSnoozing, parent.shouldWakeOnMention {
                DLog("Waking up snoozed item ID %@ because of mention", parent.nodeId ?? "<no ID>")
                parent.wakeUp()
            }
            NotificationQueue.add(type: .newMention, for: self)
        } else if !isMine {
            if parent.isSnoozing, parent.shouldWakeOnComment {
                DLog("Waking up snoozed item ID %@ because of posted comment", parent.nodeId ?? "<no ID>")
                parent.wakeUp()
            }
            guard !Settings.disableAllCommentNotifications, let authorName = userName else {
                return
            }
            let blocked = Settings.commentAuthorBlacklist.contains { authorName.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if blocked {
                DLog("Blocked notification for user '%@' as their name is on the blacklist", authorName)
            } else {
                DLog("User '%@' not on blacklist, can post notification", authorName)
                NotificationQueue.add(type: .newComment, for: self)
            }
        }
    }

    private func fill(from info: [AnyHashable: Any]) {
        body = info["body"] as? String

        if let id = info["pull_request_review_id"] as? Int64, let moc = managedObjectContext, let r = Review.review(with: id, in: moc) {
            review = r
        } else {
            review = nil
        }

        if let userInfo = info["user"] as? [AnyHashable: Any] {
            userName = userInfo["login"] as? String
            avatarUrl = userInfo["avatar_url"] as? String
            userNodeId = userInfo["node_id"] as? String
        }

        if let href = info["html_url"] as? String {
            webUrl = href

        } else if let links = info["_links"] as? [AnyHashable: Any],
                  let html = links["html"] as? [AnyHashable: Any],
                  let href = html["href"] as? String {
            webUrl = href
        }
    }

    static func commentsThatNeedReactionsToBeRefreshed(in moc: NSManagedObjectContext) -> [PRComment] {
        let f = NSFetchRequest<PRComment>(entityName: "PRComment")
        f.returnsObjectsAsFaults = false
        f.predicate = NSPredicate(format: "pendingReactionScan == YES and apiServer.lastSyncSucceeded == YES")
        return try! moc.fetch(f)
    }

    var notificationSubtitle: String {
        pullRequest?.title ?? issue?.title ?? "(untitled)"
    }

    var parent: ListableItem? {
        pullRequest ?? issue
    }

    var isMine: Bool {
        userNodeId == apiServer.userNodeId
    }

    final func contains(terms: [String]) -> Bool {
        if let b = body {
            for t in terms where !t.isEmpty && b.localizedCaseInsensitiveContains(t) {
                return true
            }
        }
        return false
    }
}
