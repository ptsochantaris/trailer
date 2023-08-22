import CoreSpotlight
import Lista
import PopTimer
import UserNotifications

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    #if os(iOS)
        func handleUserActivity(activity: NSUserActivity) -> Bool {
            if let info = activity.userInfo {
                if activity.activityType == CSSearchableItemActionType, let uid = info[CSSearchableItemActivityIdentifier] as? String {
                    popupManager.masterController.highightItemWithUriPath(uriPath: uid)
                    return true

                } else if activity.activityType == CSQueryContinuationActionType, let searchString = info[CSSearchQueryString] as? String {
                    popupManager.masterController.focusFilter(terms: searchString)
                    return true
                }
            }
            return false
        }
    #endif

    func handleLocalNotification(notification: UNNotificationContent, action: String) async {
        let userInfo = notification.userInfo
        if userInfo.isEmpty {
            return
        }

        var relatedItem: ListableItem?
        var relatedComment: PRComment?

        if let commentId = DataManager.id(for: userInfo[COMMENT_ID_KEY] as? String), let c = try? DataManager.main.existingObject(with: commentId) as? PRComment {
            relatedItem = c.parent
            relatedComment = c
        } else if let uri = userInfo[LISTABLE_URI_KEY] as? String, let itemId = DataManager.id(for: uri) {
            relatedItem = try? DataManager.main.existingObject(with: itemId) as? ListableItem
        }

        guard let relatedItem else {
            Logging.log("Could not locate the item related to this notification")
            return
        }

        let settings = Settings.cache
        switch action {
        case "mute":
            relatedItem.setMute(to: true, settings: settings)
        case "read":
            relatedItem.catchUpWithComments(settings: settings)
        default:
            relatedItem.catchUpWithComments(settings: settings)

            if let urlToOpen = userInfo[NOTIFICATION_URL_KEY] as? String ?? relatedComment?.webUrl ?? relatedItem.webUrl,
               let u = URL(string: urlToOpen) {
                #if os(macOS)
                    openItem(u)
                #else
                    popupManager.masterController.notificationSelected(for: relatedItem, urlToOpen: urlToOpen)
                #endif
            }
        }

        Task {
            await DataManager.saveDB()
            #if os(macOS)
                await app.updateRelatedMenus(for: relatedItem)
            #endif
        }
    }

    func setup() {
        let n = UNUserNotificationCenter.current()
        n.delegate = self

        n.setNotificationCategories([
            UNNotificationCategory(identifier: "mutable", actions: [
                UNNotificationAction(identifier: "read", title: "Mark as read", options: []),
                UNNotificationAction(identifier: "mute", title: "Mute this item", options: [.destructive])
            ], intentIdentifiers: []),

            UNNotificationCategory(identifier: "repo", actions: [], intentIdentifiers: [])
        ])

        Task {
            do {
                if try await n.requestAuthorization(options: .provisional) {
                    Logging.log("Successfully registered for local notifications")
                } else {
                    Logging.log("Denied permission for notifications")
                }
            } catch {
                Logging.log("Registering for local notifications failed: \(error.localizedDescription)")
            }
        }
    }

    func postNotification(type: NotificationType, for item: DataItem) async {
        let notification = UNMutableNotificationContent()

        switch type {
        case .newMention:
            guard let c = item as? PRComment,
                  let parent = c.parent,
                  !parent.shouldSkipNotifications
            else { return }
            notification.title = "@\(c.userName.orEmpty) Mentioned You"
            notification.subtitle = c.notificationSubtitle
            notification.body = c.body.orEmpty
            notification.categoryIdentifier = "mutable"

        case .newComment:
            guard let c = item as? PRComment, let parent = c.parent, !parent.shouldSkipNotifications else { return }
            notification.title = "@\(c.userName.orEmpty) Commented"
            notification.subtitle = c.notificationSubtitle
            notification.body = c.body.orEmpty
            notification.categoryIdentifier = "mutable"

        case .newPr:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "New PR"
            notification.subtitle = p.repo.fullName.orEmpty
            notification.body = p.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .prReopened:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "Re-Opened PR"
            notification.subtitle = p.repo.fullName.orEmpty
            notification.body = p.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .prMerged:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Merged!"
            notification.subtitle = p.repo.fullName.orEmpty
            notification.body = p.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .prClosed:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Closed"
            notification.subtitle = p.repo.fullName.orEmpty
            notification.body = p.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .newRepoSubscribed:
            guard let r = item as? Repo else { return }
            notification.title = "New Repo Subscribed"
            notification.body = r.fullName.orEmpty
            notification.categoryIdentifier = "repo"

        case .newRepoAnnouncement:
            guard let r = item as? Repo else { return }
            notification.title = "New Repository"
            notification.body = r.fullName.orEmpty
            notification.categoryIdentifier = "repo"

        case .newPrAssigned:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Assigned"
            notification.subtitle = p.repo.fullName.orEmpty
            notification.body = p.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .newStatus:
            guard let s = item as? PRStatus, !s.pullRequest.shouldSkipNotifications else { return }
            notification.title = "PR Status Update"
            notification.subtitle = s.descriptionText.orEmpty
            notification.body = s.pullRequest.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .newIssue:
            guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
            notification.title = "New Issue"
            notification.subtitle = i.repo.fullName.orEmpty
            notification.body = i.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .issueReopened:
            guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
            notification.title = "Re-Opened Issue"
            notification.subtitle = i.repo.fullName.orEmpty
            notification.body = i.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .issueClosed:
            guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
            notification.title = "Issue Closed"
            notification.subtitle = i.repo.fullName.orEmpty
            notification.body = i.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .newIssueAssigned:
            guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
            notification.title = "Issue Assigned"
            notification.subtitle = i.repo.fullName.orEmpty
            notification.body = i.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .changesApproved:
            guard let r = item as? Review else { return }
            let p = r.pullRequest
            if p.shouldSkipNotifications { return }
            notification.title = "@\(r.username.orEmpty) Approved Changes"
            notification.subtitle = p.title.orEmpty
            notification.body = r.body.orEmpty
            notification.categoryIdentifier = "mutable"

            let path = Bundle.main.path(forResource: "approvesChangesIcon", ofType: "png")!
            if let attachment = try? UNNotificationAttachment(identifier: path, url: URL(fileURLWithPath: path), options: nil) {
                notification.attachments = [attachment]
            }

        case .changesRequested:
            guard let r = item as? Review else { return }
            let p = r.pullRequest
            if p.shouldSkipNotifications { return }
            notification.title = "@\(r.username.orEmpty) Requests Changes"
            notification.subtitle = p.title.orEmpty
            notification.body = r.body.orEmpty
            notification.categoryIdentifier = "mutable"

            let path = Bundle.main.path(forResource: "requestsChangesIcon", ofType: "png")!
            if let attachment = try? UNNotificationAttachment(identifier: path, url: URL(fileURLWithPath: path), options: nil) {
                notification.attachments = [attachment]
            }

        case .changesDismissed:
            guard let r = item as? Review else { return }
            let p = r.pullRequest
            if p.shouldSkipNotifications { return }
            notification.title = "@\(r.username.orEmpty) Dismissed A Review"
            notification.subtitle = p.title.orEmpty
            notification.body = r.body.orEmpty
            notification.categoryIdentifier = "mutable"

        case .assignedForReview:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Review Requested"
            notification.subtitle = p.repo.fullName.orEmpty
            notification.body = p.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .assignedToTeamForReview:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Review Request to Team"
            notification.subtitle = p.repo.fullName.orEmpty
            notification.body = p.title.orEmpty
            notification.categoryIdentifier = "mutable"

        case .newReaction:
            guard let r = item as? Reaction else { return }
            notification.title = r.displaySymbol
            notification.subtitle = "@\(r.userName.orEmpty)"
            if let c = r.comment, let p = c.pullRequest, !p.shouldSkipNotifications {
                if let b = c.body { notification.body = b }
                notification.categoryIdentifier = "mutable"
            } else if let p = r.pullRequest, !p.shouldSkipNotifications {
                if let t = p.title { notification.body = t }
                notification.categoryIdentifier = "mutable"
            } else if let i = r.issue, !i.shouldSkipNotifications {
                if let t = i.title { notification.body = t }
                notification.categoryIdentifier = "mutable"
            } else {
                return
            }
        }

        notification.userInfo = DataManager.info(for: item)

        let attachmentUrl = Settings.hideAvatarsInNotifications ? nil :
            (item as? PRComment)?.avatarUrl ??
            (item as? ListableItem)?.userAvatarUrl

        Task {
            if let attachmentUrl,
               let entry = try? await HTTP.avatar(from: attachmentUrl),
               let storedUrl = await ImageCache.shared.store(entry, from: attachmentUrl),
               let attachment = try? UNNotificationAttachment(identifier: storedUrl.path, url: storedUrl, options: nil) {
                notification.attachments = [attachment]
            }

            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: notification,
                                                trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private let removalQueue = Lista<String>()
    private lazy var removalTimer = PopTimer(timeInterval: 0.5) { [weak self] in
        guard let self else { return }
        let idSet = Set(removalQueue)
        removalQueue.removeAll()

        let nc = UNUserNotificationCenter.current()
        let idsToRemove = await nc.deliveredNotifications().map(\.request).compactMap { request -> String? in
            guard let uri = request.content.userInfo[LISTABLE_URI_KEY] as? String, idSet.contains(uri) else {
                return nil
            }
            return request.identifier
        }
        if idsToRemove.isEmpty {
            return
        }
        Logging.log("Removing related notifications: \(idsToRemove)")
        nc.removeDeliveredNotifications(withIdentifiers: idsToRemove)
    }

    func removeRelatedNotifications(for uri: String) {
        removalQueue.append(uri)
        removalTimer.push()
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_: UNUserNotificationCenter, willPresent _: UNNotification) async -> UNNotificationPresentationOptions {
        [.badge, .banner, .list, .sound]
    }

    func userNotificationCenter(_: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await NotificationManager.shared.handleLocalNotification(notification: response.notification.request.content, action: response.actionIdentifier)
    }
}
