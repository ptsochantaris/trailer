
import UIKit

final class NotificationManager {

	class func handleLocalNotification(notification: UILocalNotification, action: String?) {
		if let userInfo = notification.userInfo {
			DLog("Received local notification: %@", userInfo)
			popupManager.getMasterController().localNotification(userInfo: userInfo, action: action)
		}
	}

	class func handleUserActivity(activity: NSUserActivity) -> Bool {

		if let info = activity.userInfo, let uid = info["kCSSearchableItemActivityIdentifier"] as? String {
			popupManager.getMasterController().openItemWithUriPath(uriPath: uid)
			return true
		}
		return false
	}

	class func postNotification(type: NotificationType, forItem: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = UILocalNotification()
		notification.userInfo = DataManager.infoForType(type, item: forItem)

		switch (type) {
		case .newMention:
			if let c = forItem as? PRComment {
				if c.parentShouldSkipNotifications { return }
				notification.alertTitle = "Mention by @\(S(c.userName))"
				notification.alertBody = "\(c.notificationSubtitle): '\(S(c.body))'"
				notification.category = "mutable"
			}
		case .newComment:
			if let c = forItem as? PRComment {
				if c.parentShouldSkipNotifications { return }
				notification.alertTitle = "Comment by @\(S(c.userName))"
				notification.alertBody = "\(c.notificationSubtitle): '\(S(c.body))'"
				notification.category = "mutable"
			}
		case .newPr:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "New PR in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .prReopened:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "Re-Opened PR in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .prMerged:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "PR Merged in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .prClosed:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "PR Closed in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .newRepoSubscribed:
			if let r = forItem as? Repo {
				notification.alertTitle = "New Subscription"
				notification.alertBody = S(r.fullName)
				notification.category = "repo"
			}
		case .newRepoAnnouncement:
			if let r = forItem as? Repo {
				notification.alertTitle = "New Repository"
				notification.alertBody = S(r.fullName)
				notification.category = "repo"
			}
		case .newPrAssigned:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "PR Assigned in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .newStatus:
			if let s = forItem as? PRStatus {
				if s.parentShouldSkipNotifications { return }
				notification.alertTitle = S(s.descriptionText)
				notification.alertBody = "\(S(s.pullRequest.title)) (\(S(s.pullRequest.repo.fullName)))"
				notification.category = "mutable"
			}
		case .newIssue:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.alertTitle = "New Issue in \(S(i.repo.fullName))"
				notification.alertBody = S(i.title)
				notification.category = "mutable"
			}
		case .issueReopened:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.alertTitle = "Re-Opened Issue in \(S(i.repo.fullName))"
				notification.alertBody = S(i.title)
				notification.category = "mutable"
			}
		case .issueClosed:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.alertTitle = "Issue Closed in \(S(i.repo.fullName))"
				notification.alertBody = S(i.title)
				notification.category = "mutable"
			}
		case .newIssueAssigned:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.alertTitle = "Issue Assigned in \(S(i.repo.fullName))"
				notification.alertBody = S(i.title)
				notification.category = "mutable"
			}
		}

		UIApplication.shared.presentLocalNotificationNow(notification)
	}
}
