import CoreData
import Foundation
import Lista
import TrailerJson
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

    override static var typeName: String { "PRComment" }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: PRComment.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { comment, node in
            guard node.created || node.updated,
                  let parent = node.parent
            else { return }

            if node.created {
                let parentId = parent.id
                let parentType = parent.elementType

                if parentType == "PullRequest", let pr = PullRequest.asParent(with: parentId, in: moc, parentCache: parentCache) {
                    comment.pullRequest = pr
                } else if parentType == "Issue", let issue = Issue.asParent(with: parentId, in: moc, parentCache: parentCache) {
                    comment.issue = issue
                } else if let review = Review.asParent(with: parentId, in: moc, parentCache: parentCache) {
                    comment.pullRequest = review.pullRequest
                    comment.review = review
                } else {
                    Task {
                        await Logging.shared.log("Warning: PRComment without parent")
                    }
                }
            }

            let info = node.jsonPayload
            comment.body = info.potentialString(named: "body")
            comment.webUrl = info.potentialString(named: "url")

            if let userInfo = info.potentialObject(named: "author") {
                comment.userName = userInfo.potentialString(named: "login")
                comment.userNodeId = userInfo.potentialString(named: "id")
                comment.avatarUrl = userInfo.potentialString(named: "avatarUrl")
            }
        }
    }

    static func syncComments(from data: [TypedJson.Entry]?, parent: ListableItem, moc: NSManagedObjectContext) async {
        let parentId = parent.objectID
        await v3items(with: data, type: PRComment.self, serverId: parent.apiServer.objectID, moc: moc) { item, info, newOrUpdated, syncMoc in
            if newOrUpdated, let parent = try? syncMoc.existingObject(with: parentId) as? ListableItem {
                item.pullRequest = parent.asPr
                item.issue = parent.asIssue
                item.fill(from: info)
                item.fastForwardIfNeeded(parent: parent)
                item.reactionsUrl = info.potentialObject(named: "reactions")?.potentialString(named: "url")
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

    func processNotifications(settings: Settings.Cache) {
        guard !createdByMe, let parent, parent.canBadge(settings: settings) else {
            return
        }

        if let userName, settings.commentAuthorList.contains(userName.comparableForm) {
            Task {
                await Logging.shared.log("Ignoring comment from user '\(userName)' as their name is on the blacklist")
            }
            return
        }

        let parentNodeId = parent.nodeId ?? "<no ID>"

        if contains(terms: ["@\(apiServer.userName!)"]) {
            if parent.isSnoozing, parent.shouldWakeOnMention {
                Task {
                    await Logging.shared.log("Waking up snoozed item ID \(parentNodeId) because of mention")
                }
                parent.wakeUp(settings: settings)
            }
            NotificationQueue.add(type: .newMention, for: self)
            return
        }

        if parent.isSnoozing, parent.shouldWakeOnComment {
            Task {
                await Logging.shared.log("Waking up snoozed item ID \(parentNodeId) because of posted comment")
            }
            parent.wakeUp(settings: settings)
        }

        if Settings.disableAllCommentNotifications {
            return
        }

        NotificationQueue.add(type: .newComment, for: self)
    }

    private func fill(from info: TypedJson.Entry) {
        body = info.potentialString(named: "body")

        if let id = info.potentialInt(named: "pull_request_review_id"), let moc = managedObjectContext, let r = Review.review(with: id, in: moc) {
            review = r
        } else {
            review = nil
        }

        if let userInfo = info.potentialObject(named: "user") {
            userName = userInfo.potentialString(named: "login")
            avatarUrl = userInfo.potentialString(named: "avatar_url")
            userNodeId = userInfo.potentialString(named: "node_id")
        }

        if let href = info.potentialString(named: "html_url") {
            webUrl = href

        } else if let links = info.potentialObject(named: "_links"),
                  let html = links.potentialObject(named: "html"),
                  let href = html.potentialString(named: "href") {
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

    override var asComment: PRComment? {
        self
    }
}
