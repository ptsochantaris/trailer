
import UIKit
import UserNotifications

final class NotificationManager {

	class func handleLocalNotification(notification: UNNotificationContent, action: String?) {
		if notification.userInfo.count > 0 {
			DLog("Received local notification: %@", notification.userInfo)
			popupManager.getMasterController().localNotification(userInfo: notification.userInfo, action: action)
		}
	}

	class func handleUserActivity(activity: NSUserActivity) -> Bool {

		if let info = activity.userInfo, let uid = info["kCSSearchableItemActivityIdentifier"] as? String {
			popupManager.getMasterController().openItemWithUriPath(uriPath: uid)
			return true
		}
		return false
	}

	class func setup(delegate: UNUserNotificationCenterDelegate) {
		let readAction = UNNotificationAction(identifier: "read", title: "Mark as read", options: [])
		let muteAction = UNNotificationAction(identifier: "mute", title: "Mute this item", options: [.destructive])
		let itemCategory = UNNotificationCategory(identifier: "mutable", actions: [readAction, muteAction], intentIdentifiers: [], options: [])
		let repoCategory = UNNotificationCategory(identifier: "repo", actions: [], intentIdentifiers: [], options: [])

		let n = UNUserNotificationCenter.current()
		n.setNotificationCategories([itemCategory, repoCategory])
		n.requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
			if success {
				DLog("Successfully registered for local notifications")
			} else {
				DLog("Registering for notifications failed: %@", error?.localizedDescription)
			}
		}
		n.delegate = delegate
	}

	class func postNotification(type: NotificationType, forItem: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = UNMutableNotificationContent()

		switch (type) {
		case .newMention:
			if let c = forItem as? PRComment {
				if c.parentShouldSkipNotifications { return }
				notification.title = "@\(S(c.userName)) mentioned you:"
				notification.subtitle = c.notificationSubtitle
				if let b = c.body { notification.body = b }
				notification.categoryIdentifier = "mutable"
			}
		case .newComment:
			if let c = forItem as? PRComment {
				if c.parentShouldSkipNotifications { return }
				notification.title = "@\(S(c.userName)) commented:"
				notification.subtitle = c.notificationSubtitle
				if let b = c.body { notification.body = b }
				notification.categoryIdentifier = "mutable"
			}
		case .newPr:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.title = "New PR"
				if let r = p.repo.fullName { notification.subtitle = r }
				if let b = p.title { notification.body = b }
				notification.categoryIdentifier = "mutable"
			}
		case .prReopened:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.title = "Re-Opened PR"
				if let r = p.repo.fullName { notification.subtitle = r }
				if let b = p.title { notification.body = b }
				notification.categoryIdentifier = "mutable"
			}
		case .prMerged:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.title = "PR Merged!"
				if let r = p.repo.fullName { notification.subtitle = r }
				if let b = p.title { notification.body = b }
				notification.categoryIdentifier = "mutable"
			}
		case .prClosed:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.title = "PR Closed"
				if let r = p.repo.fullName { notification.subtitle = r }
				if let b = p.title { notification.body = b }
				notification.categoryIdentifier = "mutable"
			}
		case .newRepoSubscribed:
			if let r = forItem as? Repo {
				notification.title = "New Repository Subscribed"
				notification.body = S(r.fullName)
				notification.categoryIdentifier = "repo"
			}
		case .newRepoAnnouncement:
			if let r = forItem as? Repo {
				notification.title = "New Repository"
				notification.body = S(r.fullName)
				notification.categoryIdentifier = "repo"
			}
		case .newPrAssigned:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.title = "PR Assigned"
				if let r = p.repo.fullName { notification.subtitle = r }
				if let b = p.title { notification.body = b }
				notification.categoryIdentifier = "mutable"
			}
		case .newStatus:
			if let s = forItem as? PRStatus {
				if s.parentShouldSkipNotifications { return }
				notification.title = "PR Status Update"
				if let d = s.descriptionText { notification.subtitle = d }
				if let t = s.pullRequest.title { notification.body = t }
				notification.categoryIdentifier = "mutable"
			}
		case .newIssue:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.title = "New Issue"
				if let n = i.repo.fullName { notification.subtitle = n }
				if let t = i.title { notification.body = t }
				notification.categoryIdentifier = "mutable"
			}
		case .issueReopened:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.title = "Re-Opened Issue"
				if let n =  i.repo.fullName { notification.subtitle = n }
				if let t = i.title { notification.body = t }
				notification.categoryIdentifier = "mutable"
			}
		case .issueClosed:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.title = "Issue Closed"
				if let n =  i.repo.fullName { notification.subtitle = n }
				if let t = i.title { notification.body = t }
				notification.categoryIdentifier = "mutable"
			}
		case .newIssueAssigned:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.title = "Issue Assigned"
				if let n =  i.repo.fullName { notification.subtitle = n }
				if let t = i.title { notification.body = t }
				notification.categoryIdentifier = "mutable"
			}
		}

		notification.userInfo = DataManager.infoForType(type, item: forItem)

		let t = S(notification.title)
		let s = S(notification.subtitle)
		let b = S(notification.body)
		let identifier = "\(t) - \(s) - \(b)"


		if let c = forItem as? PRComment, let url = c.avatarUrl, !Settings.hideAvatars {
			_ = api.haveCachedAvatar(from: url) { image, cachePath in
				if image != nil, let attachment = try? UNNotificationAttachment(identifier: cachePath, url: URL(fileURLWithPath: cachePath), options: [:]) {
					notification.attachments = [attachment]
				}
				let request = UNNotificationRequest(identifier: identifier, content: notification, trigger: nil)
				UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
			}
		} else {
			let request = UNNotificationRequest(identifier: identifier, content: notification, trigger: nil)
			UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
		}
	}
}
