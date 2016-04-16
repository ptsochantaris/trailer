
import UIKit

final class NotificationManager {

	class func handleLocalNotification(notification: UILocalNotification, action: String?) {
		if let userInfo = notification.userInfo {
			DLog("Received local notification: %@", userInfo)
			popupManager.getMasterController().localNotification(userInfo, action: action)
		}
		UIApplication.sharedApplication().cancelLocalNotification(notification)
	}

	class func handleUserActivity(activity: NSUserActivity) -> Bool {

		if let info = activity.userInfo,
			uid = info["kCSSearchableItemActivityIdentifier"] as? String,
			oid = DataManager.idForUriPath(uid),
			item = existingObjectWithID(oid) {

				let m = popupManager.getMasterController()
				if item is PullRequest {
					m.openPrWithId(uid)
				} else {
					m.openIssueWithId(uid)
				}
				return true
		}
		return false
	}

	class func postNotificationOfType(type: PRNotificationType, forItem: DataItem) {
		if app.preferencesDirty {
			return
		}

		let notification = UILocalNotification()
		notification.userInfo = DataManager.infoForType(type, item: forItem)

		switch (type)
		{
		case .NewMention:
			if let c = forItem as? PRComment {
				if c.parentIsMuted() { return }
				let name = c.userName ?? "(unnamed)"
				let title = c.notificationSubtitle()
				let body = c.body ?? "(no description)"
				notification.alertBody = "@\(name) mentioned you in '\(title)': \(body)"
				notification.category = "mutable"
			}
		case .NewComment:
			if let c = forItem as? PRComment {
				if c.parentIsMuted() { return }
				let name = c.userName ?? "(unnamed)"
				let title = c.notificationSubtitle()
				let body = c.body ?? "(no description)"
				notification.alertBody = "@\(name) commented on '\(title)': \(body)"
				notification.category = "mutable"
			}
		case .NewPr:
			if let p = forItem as? PullRequest {
				if p.muted?.boolValue ?? false { return }
				notification.alertBody = "New PR: " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .PrReopened:
			if let p = forItem as? PullRequest {
				if p.muted?.boolValue ?? false { return }
				notification.alertBody = "Re-Opened PR: " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .PrMerged:
			if let p = forItem as? PullRequest {
				if p.muted?.boolValue ?? false { return }
				notification.alertBody = "PR Merged! " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .PrClosed:
			if let p = forItem as? PullRequest {
				if p.muted?.boolValue ?? false { return }
				notification.alertBody = "PR Closed: " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .NewRepoSubscribed:
			if let r = forItem as? Repo {
				notification.alertBody = "New Repository Subscribed: " + (r.fullName ?? "(untitled)")
			}
		case .NewRepoAnnouncement:
			if let r = forItem as? Repo {
				notification.alertBody = "New Repository: " + (r.fullName ?? "(untitled)")
			}
		case .NewPrAssigned:
			if let p = forItem as? PullRequest {
				if p.muted?.boolValue ?? false { return }
				notification.alertBody = "PR Assigned: " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .NewStatus:
			if let s = forItem as? PRStatus {
				if s.parentIsMuted() { return }
				notification.alertBody = "New Status: " + (s.descriptionText ?? "(untitled)") + " for " + (s.pullRequest.title ?? "(untitled)") + " in " + (s.pullRequest.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .NewIssue:
			if let i = forItem as? Issue {
				if i.muted?.boolValue ?? false { return }
				notification.alertBody = "New Issue: " + (i.title ?? "(untitled)") + " in " + (i.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .IssueReopened:
			if let i = forItem as? Issue {
				if i.muted?.boolValue ?? false { return }
				notification.alertBody = "Re-Opened Issue: " + (i.title ?? "(untitled)") + " in " + (i.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .IssueClosed:
			if let i = forItem as? Issue {
				if i.muted?.boolValue ?? false { return }
				notification.alertBody = "Issue Closed: " + (i.title ?? "(untitled)") + " in " + (i.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		case .NewIssueAssigned:
			if let i = forItem as? Issue {
				if i.muted?.boolValue ?? false { return }
				notification.alertBody = "Issue Assigned: " + (i.title ?? "(untitled)") + " in " + (i.repo.fullName ?? "(untitled)")
				notification.category = "mutable"
			}
		}

		// Present notifications only if the user isn't currenty reading notifications in the notification center, over the open app, a corner case
		// Otherwise the app will end up consuming them
		let sa = UIApplication.sharedApplication()
		if app.enteringForeground {
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), {

				while sa.applicationState == .Inactive {
					NSThread.sleepForTimeInterval(1.0)
				}
				atNextEvent {
					sa.presentLocalNotificationNow(notification)
				}
			})
		} else {
			sa.presentLocalNotificationNow(notification)
		}
	}
}