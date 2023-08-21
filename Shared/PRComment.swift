import CoreData
import Foundation
import Lista
import TrailerQL

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

    override class var typeName: String { "PRComment" }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: PRComment.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { comment, node in
            guard node.created || node.updated,
                  let parentId = node.parent?.id
            else { return }

            if node.created {
                let review = Review.asParent(with: parentId, in: moc, parentCache: parentCache)
                comment.review = review

                let pr = PullRequest.asParent(with: parentId, in: moc, parentCache: parentCache)
                if pr == nil, let review {
                    comment.pullRequest = review.pullRequest
                } else {
                    comment.pullRequest = pr
                }

                let issue = Issue.asParent(with: parentId, in: moc, parentCache: parentCache)
                comment.issue = issue

                if issue == nil, pr == nil, review == nil {
                    Logging.log("Warning: PRComment without parent")
                }
            }

            let info = node.jsonPayload
            comment.body = info["body"] as? String
            comment.webUrl = info["url"] as? String

            if let userInfo = info["author"] as? JSON {
                comment.userName = userInfo["login"] as? String
                comment.userNodeId = userInfo["id"] as? String
                comment.avatarUrl = userInfo["avatarUrl"] as? String
            }
        }
    }

    static func syncComments(from data: [JSON]?, parent: ListableItem, moc: NSManagedObjectContext) async {
        let parentId = parent.objectID
        await v3items(with: data, type: PRComment.self, serverId: parent.apiServer.objectID, moc: moc) { item, info, newOrUpdated, syncMoc in
            if newOrUpdated, let parent = try? syncMoc.existingObject(with: parentId) as? ListableItem {
                item.pullRequest = parent as? PullRequest
                item.issue = parent as? Issue
                item.fill(from: info)
                item.fastForwardIfNeeded(parent: parent)
                item.reactionsUrl = (info["reactions"] as? JSON)?["url"] as? String
            }
        }
    }

    private func fastForwardIfNeeded(parent item: ListableItem) {
        // Check if we're assigned to a newly created issue, in which case we want to "fast forward" its latest comment date to our own, if ours is newer
        if let createdAt, item.postSyncAction == PostSyncAction.isNew.rawValue {
            if let latestReadDate = item.latestReadCommentDate, latestReadDate < createdAt {
                item.latestReadCommentDate = createdAt
            }
        }
    }

    func shouldContributeToCount(since: Date, settings: Settings.Cache) -> Bool {
        guard !createdByMe,
              let userName,
              let createdAt,
              createdAt > since
        else {
            return false
        }
        return !settings.excludedCommentAuthors.contains(userName.comparableForm)
    }

    func processNotifications(settings: Settings.Cache) {
        guard !createdByMe, let parent, parent.canBadge(settings: settings) else {
            return
        }

        if let userName, settings.excludedCommentAuthors.contains(userName.comparableForm) {
            Logging.log("Ignoring comment from user '\(userName)' as their name is on the blacklist")
            return
        }

        if contains(terms: ["@\(apiServer.userName!)"]) {
            if parent.isSnoozing, parent.shouldWakeOnMention {
                Logging.log("Waking up snoozed item ID \(parent.nodeId ?? "<no ID>") because of mention")
                parent.wakeUp(settings: settings)
            }
            NotificationQueue.add(type: .newMention, for: self)
            return
        }

        if parent.isSnoozing, parent.shouldWakeOnComment {
            Logging.log("Waking up snoozed item ID \(parent.nodeId ?? "<no ID>") because of posted comment")
            parent.wakeUp(settings: settings)
        }

        if Settings.disableAllCommentNotifications {
            return
        }

        NotificationQueue.add(type: .newComment, for: self)
    }

    private func fill(from info: JSON) {
        body = info["body"] as? String

        if let id = info["pull_request_review_id"] as? Int, let moc = managedObjectContext, let r = Review.review(with: id, in: moc) {
            review = r
        } else {
            review = nil
        }

        if let userInfo = info["user"] as? JSON {
            userName = userInfo["login"] as? String
            avatarUrl = userInfo["avatar_url"] as? String
            userNodeId = userInfo["node_id"] as? String
        }

        if let href = info["html_url"] as? String {
            webUrl = href

        } else if let links = info["_links"] as? JSON,
                  let html = links["html"] as? JSON,
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

    var createdByMe: Bool {
        userNodeId == apiServer.userNodeId
    }

    final func contains(terms: [String]) -> Bool {
        if let body {
            return terms.contains(where: { !$0.isEmpty && body.localizedCaseInsensitiveContains($0) })
        }
        return false
    }
}
