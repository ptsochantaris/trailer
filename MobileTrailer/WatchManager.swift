
final class WatchManager {

	class func handleWatchKitExtensionRequest(userInfo: [NSObject : AnyObject]?, reply: (([NSObject : AnyObject]!) -> Void)!) {

		if let command = userInfo?["command"] as? String {
			switch(command) {
			case "refresh":
				app.startRefresh()
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {

					let lastSuccessfulSync = Settings.lastSuccessfulRefresh ?? NSDate()

					while app.isRefreshing {
						NSThread.sleepForTimeInterval(0.1)
					}

					dispatch_async(dispatch_get_main_queue()) {
						if Settings.lastSuccessfulRefresh == nil || lastSuccessfulSync.isEqualToDate(Settings.lastSuccessfulRefresh!) {
							reply(["status": "Refresh failed", "color": "red"])
						} else {
							reply(["status": "Success", "color": "green"])
						}
					}
				}

			case "openpr":
				if let itemId = userInfo?["id"] as? String {
					let m = popupManager.getMasterController()
					m.openPrWithId(itemId)
					DataManager.saveDB()
				}
				reply(["status": "Success", "color": "green"])

			case "openissue":
				if let itemId = userInfo?["id"] as? String {
					let m = popupManager.getMasterController()
					m.openIssueWithId(itemId)
					DataManager.saveDB()
				}
				reply(["status": "Success", "color": "green"])

			case "opencomment":
				if let itemId = userInfo?["id"] as? String {
					let m = popupManager.getMasterController()
					m.openCommentWithId(itemId)
					DataManager.saveDB()
				}
				reply(["status": "Success", "color": "green"])

			case "clearAllMerged":
				let m = popupManager.getMasterController()
				m.removeAllMergedConfirmed()
				reply(["status": "Success", "color": "green"])

			case "clearAllClosed":
				let m = popupManager.getMasterController()
				m.removeAllClosedConfirmed()
				reply(["status": "Success", "color": "green"])

			case "markPrRead":
				if let
					itemId = userInfo?["id"] as? String,
					oid = DataManager.idForUriPath(itemId),
					pr = mainObjectContext.existingObjectWithID(oid, error:nil) as? PullRequest {
						pr.catchUpWithComments()
						popupManager.getMasterController().reloadDataWithAnimation(false)
						DataManager.saveDB()
				}
				reply(["status": "Success", "color": "green"])

			case "markIssueRead":
				if let
					itemId = userInfo?["id"] as? String,
					oid = DataManager.idForUriPath(itemId),
					i = mainObjectContext.existingObjectWithID(oid, error:nil) as? Issue {
						i.catchUpWithComments()
						popupManager.getMasterController().reloadDataWithAnimation(false)
						DataManager.saveDB()
				}
				reply(["status": "Success", "color": "green"])

			case "markEverythingRead":
				PullRequest.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
				Issue.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
				popupManager.getMasterController().reloadDataWithAnimation(false)
				DataManager.saveDB()
				reply(["status": "Success", "color": "green"])

			case "markAllPrsRead":
				if let s = userInfo?["sectionIndex"] as? Int {
					PullRequest.markEverythingRead(PullRequestSection(rawValue: s)!, moc: mainObjectContext)
					popupManager.getMasterController().reloadDataWithAnimation(false)
					DataManager.saveDB()
				}
				reply(["status": "Success", "color": "green"])

			case "markAllIssuesRead":
				if let s = userInfo?["sectionIndex"] as? Int {
					Issue.markEverythingRead(PullRequestSection(rawValue: s)!, moc: mainObjectContext)
					popupManager.getMasterController().reloadDataWithAnimation(false)
					DataManager.saveDB()
				}
				reply(["status": "Success", "color": "green"])
				
			default: break;
			}
		}
	}
}
