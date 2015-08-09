
import UIKit
import WatchConnectivity

final class WatchManager : NSObject, WCSessionDelegate {

	var backgroundTask = UIBackgroundTaskInvalid
	var session: WCSession?

	override init() {
		super.init()
		if WCSession.isSupported() {
			session = WCSession.defaultSession()
			session?.delegate = self
			session?.activateSession()
		}
	}

	func startBGTask() {
		backgroundTask = UIApplication.sharedApplication().beginBackgroundTaskWithName("com.housetrip.Trailer.watchrequest", expirationHandler: {
			self.endBGTask()
		})
	}

	func endBGTask() {
		if backgroundTask != UIBackgroundTaskInvalid {
			UIApplication.sharedApplication().endBackgroundTask(backgroundTask)
			backgroundTask = UIBackgroundTaskInvalid
		}
	}

	func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {

		startBGTask()

		switch(message["command"] as? String ?? "") {
		case "refresh":
			app.startRefresh()
			dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {

				let lastSuccessfulSync = Settings.lastSuccessfulRefresh ?? NSDate()

				while app.isRefreshing {
					NSThread.sleepForTimeInterval(0.1)
				}
				atNextEvent() {
					if Settings.lastSuccessfulRefresh == nil || lastSuccessfulSync.isEqualToDate(Settings.lastSuccessfulRefresh!) {
						replyHandler(["status": "Refresh failed", "color": "red"])
					} else {
						replyHandler(["status": "Success", "color": "green"])
					}
					self.endBGTask()
				}
			}
		case "openpr":
			if let itemId = message["id"] as? String {
				let m = popupManager.getMasterController()
				m.openPrWithId(itemId)
				DataManager.saveDB()
			}
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "openissue":
			if let itemId = message["id"] as? String {
				let m = popupManager.getMasterController()
				m.openIssueWithId(itemId)
				DataManager.saveDB()
			}
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "opencomment":
			if let itemId = message["id"] as? String {
				let m = popupManager.getMasterController()
				m.openCommentWithId(itemId)
				DataManager.saveDB()
			}
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "clearAllMerged":
			for p in PullRequest.allMergedRequestsInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
			DataManager.saveDB()
			let m = popupManager.getMasterController()
			m.reloadDataWithAnimation(false)
			m.updateStatus()
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "clearAllClosed":
			for p in PullRequest.allClosedRequestsInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
			for i in Issue.allClosedIssuesInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(i)
			}
			DataManager.saveDB()
			let m = popupManager.getMasterController()
			m.reloadDataWithAnimation(false)
			m.updateStatus()
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "markPrRead":
			if let
				itemId = message["id"] as? String,
				oid = DataManager.idForUriPath(itemId),
				pr = existingObjectWithID(oid) as? PullRequest {
					pr.catchUpWithComments()
					popupManager.getMasterController().reloadDataWithAnimation(false)
					DataManager.saveDB()
					app.updateBadge()
			}
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "markIssueRead":
			if let
				itemId = message["id"] as? String,
				oid = DataManager.idForUriPath(itemId),
				i = existingObjectWithID(oid) as? Issue {
					i.catchUpWithComments()
					popupManager.getMasterController().reloadDataWithAnimation(false)
					DataManager.saveDB()
					app.updateBadge()
			}
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "markEverythingRead":
			PullRequest.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
			Issue.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
			popupManager.getMasterController().reloadDataWithAnimation(false)
			DataManager.saveDB()
			app.updateBadge()
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "markAllPrsRead":
			if let s = message["sectionIndex"] as? Int {
				PullRequest.markEverythingRead(PullRequestSection(rawValue: s)!, moc: mainObjectContext)
				popupManager.getMasterController().reloadDataWithAnimation(false)
				DataManager.saveDB()
				app.updateBadge()
			}
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		case "markAllIssuesRead":
			if let s = message["sectionIndex"] as? Int {
				Issue.markEverythingRead(PullRequestSection(rawValue: s)!, moc: mainObjectContext)
				popupManager.getMasterController().reloadDataWithAnimation(false)
				DataManager.saveDB()
				app.updateBadge()
			}
			atNextEvent() {
				replyHandler(["status": "Success", "color": "green"])
				self.endBGTask()
			}
		default:
			atNextEvent() {
				self.endBGTask()
			}
		}
	}
}
