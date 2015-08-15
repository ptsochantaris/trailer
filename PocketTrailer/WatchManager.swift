
import UIKit
import CoreData
import WatchConnectivity

final class WatchManager : NSObject, WCSessionDelegate {

	var backgroundTask = UIBackgroundTaskInvalid

	override init() {
		super.init()
		if WCSession.isSupported() {
			let session = WCSession.defaultSession()
			session.delegate = self
			session.activateSession()
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

				atNextEvent {
					if Settings.lastSuccessfulRefresh == nil || lastSuccessfulSync.isEqualToDate(Settings.lastSuccessfulRefresh!) {
						self.reportFailure("Refresh Failed", message, replyHandler)
					} else {
						self.processList(message, replyHandler)
					}
				}
			}

		case "openpr":
			if let itemId = message["id"] as? String {
				let m = popupManager.getMasterController()
				m.openPrWithId(itemId)
				DataManager.saveDB()
			}
			atNextEvent {
				self.processList(message, replyHandler)
			}

		case "openissue":
			if let itemId = message["id"] as? String {
				let m = popupManager.getMasterController()
				m.openIssueWithId(itemId)
				DataManager.saveDB()
			}
			atNextEvent {
				self.processList(message, replyHandler)
			}

		case "opencomment":
			if let itemId = message["id"] as? String {
				let m = popupManager.getMasterController()
				m.openCommentWithId(itemId)
				DataManager.saveDB()
			}
			atNextEvent {
				self.processList(message, replyHandler)
			}

		case "clearAllMerged":
			for p in PullRequest.allMergedRequestsInMoc(mainObjectContext) {
				mainObjectContext.deleteObject(p)
			}
			DataManager.saveDB()
			let m = popupManager.getMasterController()
			m.reloadDataWithAnimation(false)
			m.updateStatus()
			atNextEvent {
				self.processList(message, replyHandler)
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
			atNextEvent {
				self.processList(message, replyHandler)
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
			atNextEvent {
				self.processList(message, replyHandler)
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
			atNextEvent {
				self.processList(message, replyHandler)
			}

		case "markEverythingRead":
			PullRequest.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
			Issue.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
			popupManager.getMasterController().reloadDataWithAnimation(false)
			DataManager.saveDB()
			app.updateBadge()
			atNextEvent {
				self.processList(message, replyHandler)
			}

		case "markAllPrsRead":
			if let s = message["sectionIndex"] as? Int {
				PullRequest.markEverythingRead(PullRequestSection(rawValue: s)!, moc: mainObjectContext)
				popupManager.getMasterController().reloadDataWithAnimation(false)
				DataManager.saveDB()
				app.updateBadge()
			}
			atNextEvent {
				self.processList(message, replyHandler)
			}

		case "markAllIssuesRead":
			if let s = message["sectionIndex"] as? Int {
				Issue.markEverythingRead(PullRequestSection(rawValue: s)!, moc: mainObjectContext)
				popupManager.getMasterController().reloadDataWithAnimation(false)
				DataManager.saveDB()
				app.updateBadge()
			}
			atNextEvent {
				self.processList(message, replyHandler)
			}

		default:
			atNextEvent {
				self.processList(message, replyHandler)
			}
		}
	}

	private func processList(message: [String : AnyObject], _ replyHandler: ([String : AnyObject]) -> Void) {

		var result = [String : AnyObject]()

		switch(message["list"] as? String ?? "") {

		case "overview":
			result["result"] = buildOverview()
			reportSuccess(result, replyHandler)

		case "item_list":
			let type = message["type"] as! String
			let section = message["section"] as! String
			result["result"] = buildItemList(type, section)
			reportSuccess(result, replyHandler)

		case "item_detail":
			if let lid = message["localId"] as? String, details = buildItemDetail(lid) {
				result["result"] = details
				reportSuccess(result, replyHandler)
			} else {
				reportFailure("Item Not Found", result, replyHandler)
			}

		default:
			reportSuccess(result, replyHandler)
		}
	}

	private func reportFailure(reason: String, _ result: [String : AnyObject], _ replyHandler: ([String : AnyObject]) -> Void) {
		var r = result
		r["status"] = reason
		r["color"] = "FF0000"
		replyHandler(r)
		endBGTask()
	}

	private func reportSuccess(result: [String : AnyObject], _ replyHandler: ([String : AnyObject]) -> Void) {
		var r = result
		r["status"] = "Success"
		r["color"] = "00FF00"
		replyHandler(r)
		endBGTask()
	}

	////////////////////////////

	private func buildItemList(type: String, _ section: String) -> [[String : AnyObject]] {
		var items = [[String : AnyObject]]()

		let sectionIndex: PullRequestSection
		switch section {
			case "mine": sectionIndex = PullRequestSection.Mine
			case "participated": sectionIndex = PullRequestSection.Participated
			case "merged": sectionIndex = PullRequestSection.Merged
			case "closed": sectionIndex = PullRequestSection.Closed
			default: sectionIndex = PullRequestSection.All
		}

		let f: NSFetchRequest
		var showStatuses = false
		if type == "prs" {
			f = ListableItem.requestForItemsOfType("PullRequest", withFilter: nil, sectionIndex: sectionIndex.rawValue)
			showStatuses = Settings.showStatusItems
		} else {
			f = ListableItem.requestForItemsOfType("Issue", withFilter: nil, sectionIndex: sectionIndex.rawValue)
		}
		for item in try! mainObjectContext.executeFetchRequest(f) as! [ListableItem] {
			items.append(baseDataForItem(item, showStatuses: showStatuses))
		}
		return items
	}

	private func baseDataForItem(item: ListableItem, showStatuses: Bool) -> [String : AnyObject] {
		var itemData = [
			"title": item.title ?? "NOTITLE",
			"unreadcount": item.unreadComments ?? 0,
			"repo": item.repo.fullName ?? "NOREPONAME",
			"user": item.userLogin ?? "NONAME",
			"date": (Settings.showCreatedInsteadOfUpdated ? item.createdAt : item.updatedAt) ?? NSDate.distantPast(),
			"localId": item.objectID.URIRepresentation().absoluteString
		]
		if showStatuses {
			itemData["statuses"] = statusLinesForPr(item as! PullRequest)
		}
		return itemData
	}

	private func statusLinesForPr(pr: PullRequest) -> [[String : AnyObject]] {
		var statusLines = [[String : AnyObject]]()
		for status in pr.displayedStatuses() {
			statusLines.append([
				"color": colorToHex(status.colorForDarkDisplay()),
				"text": status.descriptionText ?? "NOTEXT"
				])
		}
		return statusLines
	}

	/////////////////////////////

	private func buildItemDetail(localId: String) -> [String : AnyObject]? {
		if let oid = DataManager.idForUriPath(localId), item = existingObjectWithID(oid) as? ListableItem {
			let showStatuses = (item is PullRequest) ? Settings.showStatusItems : false
			var result = baseDataForItem(item, showStatuses: showStatuses)
			result["description"] = item.body
			result["comments"] = commentsForItem(item)
			return result
		}
		return nil
	}

	private func commentsForItem(item: ListableItem) -> [[String : AnyObject]] {
		var comments = [[String : AnyObject]]()
		for comment in item.comments {
			comments.append([
				"user": comment.userName ?? "NOUSER",
				"date": comment.createdAt ?? NSDate.distantPast(),
				"text": comment.body ?? "NOBODY",
				])
		}
		return comments
	}

	//////////////////////////////

	private func buildOverview() -> [String : AnyObject] {
		var prs: [String : AnyObject] = [
			"mine": prCountsForSection(PullRequestSection.Mine),
			"participated": prCountsForSection(PullRequestSection.Participated),
			"merged": prCountsForSection(PullRequestSection.Merged),
			"closed": prCountsForSection(PullRequestSection.Closed),
			"other": prCountsForSection(PullRequestSection.All),
			"total": PullRequest.countAllRequestsInMoc(mainObjectContext),
			"unread": PullRequest.badgeCountInMoc(mainObjectContext)
		]
		if prs.count==0 {
			prs["error"] = DataManager.reasonForEmptyWithFilter(nil).string
		}
		var issues: [String : AnyObject] = [
			"mine": issueCountsForSection(PullRequestSection.Mine),
			"participated": issueCountsForSection(PullRequestSection.Participated),
			"closed": issueCountsForSection(PullRequestSection.Closed),
			"other": issueCountsForSection(PullRequestSection.All),
			"total": Issue.countAllIssuesInMoc(mainObjectContext),
			"unread": Issue.badgeCountInMoc(mainObjectContext)
		]
		if issues.count==0 {
			issues["error"] = DataManager.reasonForEmptyIssuesWithFilter(nil).string
		}
		return [
			"prs": prs,
			"issues": issues,
			"glanceWantsIssues": Settings.showIssuesInGlance,
			"lastUpdated": Settings.lastSuccessfulRefresh ?? NSDate.distantPast()
		]
	}

	private func prCountsForSection(section: PullRequestSection) -> [String : Int] {
		return ["total": PullRequest.countRequestsInSection(section, moc: mainObjectContext),
				"unread": PullRequest.badgeCountInSection(section, moc: mainObjectContext)];
	}
	private func issueCountsForSection(section: PullRequestSection) -> [String : Int] {
		return ["total": Issue.countIssuesInSection(section, moc: mainObjectContext),
				"unread": Issue.badgeCountInSection(section, moc: mainObjectContext)];
	}
}
