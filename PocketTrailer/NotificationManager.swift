
import UIKit

final class NotificationManager {

	class func handleLocalNotification(notification: UILocalNotification, action: String?) {
		if let userInfo = notification.userInfo {
			DLog("Received local notification: %@", userInfo)
			popupManager.getMasterController().localNotification(userInfo, action: action)
		}
	}

	class func handleUserActivity(activity: NSUserActivity) -> Bool {

		if let info = activity.userInfo, uid = info["kCSSearchableItemActivityIdentifier"] as? String {
			popupManager.getMasterController().openItemWithUriPath(uid)
			return true
		}
		return false
	}

	class func postNotificationOfType(type: NotificationType, forItem: DataItem) {
		if preferencesDirty {
			return
		}

		let notification = UILocalNotification()
		notification.userInfo = DataManager.infoForType(type, item: forItem)

		switch (type) {
		case .NewMention:
			if let c = forItem as? PRComment {
				if c.parentShouldSkipNotifications { return }
				notification.alertTitle = "Mention by @\(S(c.userName))"
				notification.alertBody = "\(c.notificationSubtitle): '\(S(c.body))'"
				notification.category = "mutable"
			}
		case .NewComment:
			if let c = forItem as? PRComment {
				if c.parentShouldSkipNotifications { return }
				notification.alertTitle = "Comment by @\(S(c.userName))"
				notification.alertBody = "\(c.notificationSubtitle): '\(S(c.body))'"
				notification.category = "mutable"
			}
		case .NewPr:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "New PR in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .PrReopened:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "Re-Opened PR in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .PrMerged:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "PR Merged in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .PrClosed:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "PR Closed in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .NewRepoSubscribed:
			if let r = forItem as? Repo {
				notification.alertTitle = "New Subscription"
				notification.alertBody = S(r.fullName)
				notification.category = "repo"
			}
		case .NewRepoAnnouncement:
			if let r = forItem as? Repo {
				notification.alertTitle = "New Repository"
				notification.alertBody = S(r.fullName)
				notification.category = "repo"
			}
		case .NewPrAssigned:
			if let p = forItem as? PullRequest {
				if p.shouldSkipNotifications { return }
				notification.alertTitle = "PR Assigned in \(S(p.repo.fullName))"
				notification.alertBody = S(p.title)
				notification.category = "mutable"
			}
		case .NewStatus:
			if let s = forItem as? PRStatus {
				if s.parentShouldSkipNotifications { return }
				notification.alertTitle = S(s.descriptionText)
				notification.alertBody = "\(S(s.pullRequest.title)) (\(S(s.pullRequest.repo.fullName)))"
				notification.category = "mutable"
			}
		case .NewIssue:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.alertTitle = "New Issue in \(S(i.repo.fullName))"
				notification.alertBody = S(i.title)
				notification.category = "mutable"
			}
		case .IssueReopened:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.alertTitle = "Re-Opened Issue in \(S(i.repo.fullName))"
				notification.alertBody = S(i.title)
				notification.category = "mutable"
			}
		case .IssueClosed:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.alertTitle = "Issue Closed in \(S(i.repo.fullName))"
				notification.alertBody = S(i.title)
				notification.category = "mutable"
			}
		case .NewIssueAssigned:
			if let i = forItem as? Issue {
				if i.shouldSkipNotifications { return }
				notification.alertTitle = "Issue Assigned in \(S(i.repo.fullName))"
				notification.alertBody = S(i.title)
				notification.category = "mutable"
			}
		}

		UIApplication.sharedApplication().presentLocalNotificationNow(notification)
	}
}
