
import UIKit

final class NotificationManager {

	class func handleLocalNotification(notification: UILocalNotification) {
		if let userInfo = notification.userInfo {
			DLog("Received local notification: %@", userInfo)
			popupManager.getMasterController().localNotification(userInfo)
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
				let name = c.userName ?? "(unnamed)"
				let title = c.notificationSubtitle()
				let body = c.body ?? "(no description)"
				notification.alertBody = "@\(name) mentioned you in '\(title)': \(body)"
			}
		case .NewComment:
			if let c = forItem as? PRComment {
				let name = c.userName ?? "(unnamed)"
				let title = c.notificationSubtitle()
				let body = c.body ?? "(no description)"
				notification.alertBody = "@\(name) commented on '\(title)': \(body)"
			}
		case .NewPr:
			if let p = forItem as? PullRequest {
				notification.alertBody = "New PR: " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
			}
		case .PrReopened:
			if let p = forItem as? PullRequest {
				notification.alertBody = "Re-Opened PR: " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
			}
		case .PrMerged:
			if let p = forItem as? PullRequest {
				notification.alertBody = "PR Merged! " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
			}
		case .PrClosed:
			if let p = forItem as? PullRequest {
				notification.alertBody = "PR Closed: " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
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
				notification.alertBody = "PR Assigned: " + (p.title ?? "(untitled)") + " in " + (p.repo.fullName ?? "(untitled)")
			}
		case .NewStatus:
			if let s = forItem as? PRStatus {
				notification.alertBody = "New Status: " + (s.descriptionText ?? "(untitled)") + " for " + (s.pullRequest.title ?? "(untitled)") + " in " + (s.pullRequest.repo.fullName ?? "(untitled)")
			}
		case .NewIssue:
			if let i = forItem as? Issue {
				notification.alertBody = "New Issue: " + (i.title ?? "(untitled)") + " in " + (i.repo.fullName ?? "(untitled)")
			}
		case .IssueReopened:
			if let i = forItem as? Issue {
				notification.alertBody = "Re-Opened Issue: " + (i.title ?? "(untitled)") + " in " + (i.repo.fullName ?? "(untitled)")
			}
		case .IssueClosed:
			if let i = forItem as? Issue {
				notification.alertBody = "Issue Closed: " + (i.title ?? "(untitled)") + " in " + (i.repo.fullName ?? "(untitled)")
			}
		case .NewIssueAssigned:
			if let i = forItem as? Issue {
				notification.alertBody = "Issue Assigned: " + (i.title ?? "(untitled)") + " in " + (i.repo.fullName ?? "(untitled)")
			}
		}

		// Present notifications only if the user isn't currenty reading notifications in the notification center, over the open app, a corner case
		// Otherwise the app will end up consuming them
		if app.enteringForeground {
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), {

				while UIApplication.sharedApplication().applicationState==UIApplicationState.Inactive {
					NSThread.sleepForTimeInterval(1.0)
				}
				dispatch_sync(dispatch_get_main_queue(), {
					UIApplication.sharedApplication().presentLocalNotificationNow(notification)
				})
			})
		} else {
			UIApplication.sharedApplication().presentLocalNotificationNow(notification)
		}
	}
}