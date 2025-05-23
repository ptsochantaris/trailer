import CoreData
import Lista
import TrailerJson
import TrailerQL

final class Review: DataItem {
    @NSManaged var body: String?
    @NSManaged var username: String?
    @NSManaged var state: String?

    @NSManaged var pullRequest: PullRequest
    @NSManaged var comments: Set<PRComment>

    override static var typeName: String { "Review" }

    enum State: String {
        case CHANGES_REQUESTED
        case APPROVED
        case DISMISSED
    }

    static func syncRequests(from nodes: Lista<Node>, moc: NSManagedObjectContext, parentCache: FetchCache) {
        var prIdsToAssignedUsers = [String: Set<String>]()
        var prIdsToAssignedTeams = [String: Set<String>]()

        for node in nodes {
            guard node.elementType == "ReviewRequest",
                  let parentId = node.parent?.id else {
                continue
            }

            if let reviewerJson = node.jsonPayload.potentialObject(named: "requestedReviewer") {
                if let login = reviewerJson.potentialString(named: "login") {
                    var previous = prIdsToAssignedUsers[parentId]
                    previous?.insert(login)
                    prIdsToAssignedUsers[parentId] = previous ?? [login]
                }
                if let slug = reviewerJson.potentialString(named: "slug") {
                    var previous = prIdsToAssignedTeams[parentId]
                    previous?.insert(slug)
                    prIdsToAssignedTeams[parentId] = previous ?? [slug]
                }
            }
        }

        for node in nodes {
            guard node.elementType == "ReviewRequest",
                  let parentId = node.parent?.id,
                  let parent = PullRequest.asParent(with: parentId, in: moc, parentCache: parentCache) else {
                continue
            }
            parent.checkAndStoreReviewAssignments(prIdsToAssignedUsers[parentId] ?? [],
                                                  prIdsToAssignedTeams[parentId] ?? [])
        }
    }

    static func sync(from nodes: Lista<Node>, on server: ApiServer, moc: NSManagedObjectContext, parentCache: FetchCache) {
        syncItems(of: Review.self, from: nodes, on: server, moc: moc, parentCache: parentCache) { review, node in
            let info = node.jsonPayload
            if (try? info.keys)?.count == 3 { // this node is a blank container (id, comments, typename)
                return
            }
            let newState = info.potentialString(named: "state")
            review.check(newState: newState)

            guard node.created || node.updated,
                  let parentId = node.parent?.id
            else { return }

            if node.created {
                if let parent = PullRequest.asParent(with: parentId, in: moc, parentCache: parentCache) {
                    review.pullRequest = parent
                } else {
                    Task {
                        await Logging.shared.log("Warning Review without parent")
                    }
                }
            }

            review.body = info.potentialString(named: "body")
            review.username = info.potentialObject(named: "author")?.potentialString(named: "login")
        }
    }

    override var asReview: Review? {
        self
    }

    static func syncReviews(from data: [TypedJson.Entry]?, withParent: PullRequest, moc: NSManagedObjectContext) async {
        let parentId = withParent.objectID
        let apiServerId = withParent.apiServer.objectID
        await v3items(with: data, type: Review.self, serverId: apiServerId, moc: moc) { item, info, isNewOrUpdated, syncMoc in
            if isNewOrUpdated, let parent = try? syncMoc.existingObject(with: parentId) as? PullRequest {
                item.pullRequest = parent
                item.body = info.potentialString(named: "body")
                item.username = info.potentialObject(named: "user")?.potentialString(named: "login")
            }
            let newState = info.potentialString(named: "state")
            item.check(newState: newState)
        }
    }

    private func check(newState: String?) {
        if state != newState { // state change doesn't change API date, so we need to check for this every time
            state = newState
            if postSyncAction == PostSyncAction.doNothing.rawValue {
                postSyncAction = PostSyncAction.isUpdated.rawValue
            }
        }
    }

    func processNotifications(settings: Settings.Cache) {
        guard !isMine, pullRequest.canBadge(settings: settings), let newState = State(rawValue: state.orEmpty) else {
            return
        }

        switch newState {
        case .CHANGES_REQUESTED:
            if settings.notifyOnAllReviewChangeRequests || (settings.notifyOnReviewChangeRequests && pullRequest.createdByMe) {
                NotificationQueue.add(type: .changesRequested, for: self)
            }
        case .APPROVED:
            if settings.notifyOnAllReviewAcceptances || (settings.notifyOnReviewAcceptances && pullRequest.createdByMe) {
                NotificationQueue.add(type: .changesApproved, for: self)
            }
        case .DISMISSED:
            if settings.notifyOnAllReviewDismissals || (settings.notifyOnReviewDismissals && pullRequest.createdByMe) {
                NotificationQueue.add(type: .changesDismissed, for: self)
            }
        }
    }

    static func review(with id: Int, in moc: NSManagedObjectContext) -> Review? {
        let f = NSFetchRequest<Review>(entityName: "Review")
        f.returnsObjectsAsFaults = false
        f.includesSubentities = false
        f.fetchLimit = 1
        f.predicate = NSPredicate(format: "serverId == %d", id)
        return try! moc.fetch(f).first
    }

    var isMine: Bool {
        username == apiServer.userName
    }

    var affectsBottomLine: Bool {
        switch state {
        case State.APPROVED.rawValue, State.CHANGES_REQUESTED.rawValue, State.DISMISSED.rawValue:
            true
        default:
            false
        }
    }
}
