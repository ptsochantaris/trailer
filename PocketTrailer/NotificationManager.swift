import CoreSpotlight
import UIKit
import UserNotifications

final class NotificationManager {
    static func handleLocalNotification(notification: UNNotificationContent, action: String) {
        if !notification.userInfo.isEmpty {
            DLog("Received local notification: %@", notification.userInfo)
            popupManager.masterController.localNotificationSelected(userInfo: notification.userInfo, action: action)
        }
    }

    static func handleUserActivity(activity: NSUserActivity) -> Bool {
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

    static func setup(delegate: UNUserNotificationCenterDelegate) {
        let readAction = UNNotificationAction(identifier: "read", title: "Mark as read", options: [])
        let muteAction = UNNotificationAction(identifier: "mute", title: "Mute this item", options: [.destructive])
        let itemCategory = UNNotificationCategory(identifier: "mutable", actions: [readAction, muteAction], intentIdentifiers: [], options: [])
        let repoCategory = UNNotificationCategory(identifier: "repo", actions: [], intentIdentifiers: [], options: [])

        let n = UNUserNotificationCenter.current()
        n.setNotificationCategories([itemCategory, repoCategory])
        n.requestAuthorization(options: .provisional) { success, error in
            if success {
                DLog("Successfully registered for local notifications")
            } else {
                DLog("Registering for notifications failed: %@", error?.localizedDescription)
            }
        }
        n.delegate = delegate
    }

    static func postNotification(type: NotificationType, for item: DataItem) {
        let notification = UNMutableNotificationContent()

        switch type {
        case .newMention:
            guard let c = item as? PRComment, let parent = c.parent, !parent.shouldSkipNotifications else { return }
            notification.title = "@\(S(c.userName)) mentioned you:"
            notification.subtitle = c.notificationSubtitle
            if let b = c.body { notification.body = b }
            notification.categoryIdentifier = "mutable"

        case .newComment:
            guard let c = item as? PRComment, let parent = c.parent, !parent.shouldSkipNotifications else { return }
            notification.title = "@\(S(c.userName)) commented:"
            notification.subtitle = c.notificationSubtitle
            if let b = c.body { notification.body = b }
            notification.categoryIdentifier = "mutable"

        case .newPr:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "New PR"
            if let r = p.repo.fullName { notification.subtitle = r }
            if let b = p.title { notification.body = b }
            notification.categoryIdentifier = "mutable"

        case .prReopened:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "Re-Opened PR"
            if let r = p.repo.fullName { notification.subtitle = r }
            if let b = p.title { notification.body = b }
            notification.categoryIdentifier = "mutable"

        case .prMerged:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Merged!"
            if let r = p.repo.fullName { notification.subtitle = r }
            if let b = p.title { notification.body = b }
            notification.categoryIdentifier = "mutable"

        case .prClosed:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Closed"
            if let r = p.repo.fullName { notification.subtitle = r }
            if let b = p.title { notification.body = b }
            notification.categoryIdentifier = "mutable"

        case .newRepoSubscribed:
            guard let r = item as? Repo else { return }
            notification.title = "New Repository Subscribed"
            notification.body = S(r.fullName)
            notification.categoryIdentifier = "repo"

        case .newRepoAnnouncement:
            guard let r = item as? Repo else { return }
            notification.title = "New Repository"
            notification.body = S(r.fullName)
            notification.categoryIdentifier = "repo"

        case .newPrAssigned:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Assigned"
            if let r = p.repo.fullName { notification.subtitle = r }
            if let b = p.title { notification.body = b }
            notification.categoryIdentifier = "mutable"

        case .newStatus:
            guard let s = item as? PRStatus, !s.pullRequest.shouldSkipNotifications else { return }
            notification.title = "PR Status Update"
            if let d = s.descriptionText { notification.subtitle = d }
            if let t = s.pullRequest.title { notification.body = t }
            notification.categoryIdentifier = "mutable"

        case .newIssue:
            guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
            notification.title = "New Issue"
            if let n = i.repo.fullName { notification.subtitle = n }
            if let t = i.title { notification.body = t }
            notification.categoryIdentifier = "mutable"

        case .issueReopened:
            guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
            notification.title = "Re-Opened Issue"
            if let n = i.repo.fullName { notification.subtitle = n }
            if let t = i.title { notification.body = t }
            notification.categoryIdentifier = "mutable"

        case .issueClosed:
            guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
            notification.title = "Issue Closed"
            if let n = i.repo.fullName { notification.subtitle = n }
            if let t = i.title { notification.body = t }
            notification.categoryIdentifier = "mutable"

        case .newIssueAssigned:
            guard let i = item as? Issue, !i.shouldSkipNotifications else { return }
            notification.title = "Issue Assigned"
            if let n = i.repo.fullName { notification.subtitle = n }
            if let t = i.title { notification.body = t }
            notification.categoryIdentifier = "mutable"

        case .changesApproved:
            guard let r = item as? Review else { return }
            let p = r.pullRequest
            if p.shouldSkipNotifications { return }
            notification.title = "@\(S(r.username)) Approved Changes"
            if let t = p.title { notification.subtitle = t }
            if let b = r.body { notification.body = b }
            notification.categoryIdentifier = "mutable"

            let path = Bundle.main.path(forResource: "approvesChangesIcon", ofType: "png")!
            if let attachment = try? UNNotificationAttachment(identifier: path, url: URL(fileURLWithPath: path), options: nil) {
                notification.attachments = [attachment]
            }

        case .changesRequested:
            guard let r = item as? Review else { return }
            let p = r.pullRequest
            if p.shouldSkipNotifications { return }
            notification.title = "@\(S(r.username)) Requests Changes"
            if let t = p.title { notification.subtitle = t }
            if let b = r.body { notification.body = b }
            notification.categoryIdentifier = "mutable"

            let path = Bundle.main.path(forResource: "requestsChangesIcon", ofType: "png")!
            if let attachment = try? UNNotificationAttachment(identifier: path, url: URL(fileURLWithPath: path), options: nil) {
                notification.attachments = [attachment]
            }

        case .changesDismissed:
            guard let r = item as? Review else { return }
            let p = r.pullRequest
            if p.shouldSkipNotifications { return }
            notification.title = "@\(S(r.username)) Dismissed A Review"
            if let t = p.title { notification.subtitle = t }
            if let b = r.body { notification.body = b }
            notification.categoryIdentifier = "mutable"

        case .assignedForReview:
            guard let p = item as? PullRequest, !p.shouldSkipNotifications else { return }
            notification.title = "PR Assigned For Review"
            if let n = p.repo.fullName { notification.subtitle = n }
            if let t = p.title { notification.body = t }
            notification.categoryIdentifier = "mutable"

        case .newReaction:
            guard let r = item as? Reaction else { return }
            notification.title = r.displaySymbol
            notification.subtitle = "@\(S(r.userName))"
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

        Task {
            if !Settings.hideAvatarsInNotifications, let url = (item as? PRComment)?.avatarUrl ?? (item as? ListableItem)?.userAvatarUrl {
                let res = try? await API.avatar(from: url)
                if let res = res, let attachment = try? UNNotificationAttachment(identifier: res.1, url: URL(fileURLWithPath: res.1), options: nil) {
                    notification.attachments = [attachment]
                }
            }
            let identifier = [notification.title, notification.subtitle, notification.body].map { $0 }.joined(separator: " - ")
            let request = UNNotificationRequest(identifier: identifier, content: notification, trigger: nil)
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
        }
    }
}
