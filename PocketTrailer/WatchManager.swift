
import UIKit
import CoreData
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

	func updateContext() {
		do {
			try session?.updateApplicationContext(["overview": buildOverview()])
		} catch {}
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

		dispatch_async(dispatch_get_main_queue()) {

			self.startBGTask()

			switch(message["command"] as? String ?? "") {
			case "refresh":
				app.startRefresh()
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
					let lastSuccessfulSync = Settings.lastSuccessfulRefresh ?? NSDate()
					while app.isRefreshing { NSThread.sleepForTimeInterval(0.1) }
					dispatch_sync(dispatch_get_main_queue(), {
						if Settings.lastSuccessfulRefresh == nil || lastSuccessfulSync.isEqualToDate(Settings.lastSuccessfulRefresh!) {
							self.reportFailure("Refresh Failed", message, replyHandler)
						} else {
							self.processList(message, replyHandler)
						}
					})
				}

			case "openpr":
				if let itemId = message["localId"] as? String {
					let m = popupManager.getMasterController()
					m.openPrWithId(itemId)
					DataManager.saveDB()
				}
				self.processList(message, replyHandler)

			case "openissue":
				if let itemId = message["localId"] as? String {
					let m = popupManager.getMasterController()
					m.openIssueWithId(itemId)
					DataManager.saveDB()
				}
				self.processList(message, replyHandler)

			case "opencomment":
				if let itemId = message["id"] as? String {
					let m = popupManager.getMasterController()
					m.openCommentWithId(itemId)
					DataManager.saveDB()
				}
				self.processList(message, replyHandler)

			case "clearAllMerged":
				for p in PullRequest.allMergedRequestsInMoc(mainObjectContext) {
					mainObjectContext.deleteObject(p)
				}
				DataManager.saveDB()
				let m = popupManager.getMasterController()
				m.reloadDataWithAnimation(false)
				m.updateStatus()
				self.processList(message, replyHandler)

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
				self.processList(message, replyHandler)

			case "markPrRead":
				if let
					itemId = message["localId"] as? String,
					oid = DataManager.idForUriPath(itemId),
					pr = existingObjectWithID(oid) as? PullRequest {
						pr.catchUpWithComments()
						popupManager.getMasterController().reloadDataWithAnimation(false)
						DataManager.saveDB()
						app.updateBadge()
				}
				self.processList(message, replyHandler)

			case "markIssueRead":
				if let
					itemId = message["localId"] as? String,
					oid = DataManager.idForUriPath(itemId),
					i = existingObjectWithID(oid) as? Issue {
						i.catchUpWithComments()
						popupManager.getMasterController().reloadDataWithAnimation(false)
						DataManager.saveDB()
						app.updateBadge()
				}
				self.processList(message, replyHandler)

			case "markEverythingRead":
				PullRequest.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
				Issue.markEverythingRead(PullRequestSection.None, moc: mainObjectContext)
				popupManager.getMasterController().reloadDataWithAnimation(false)
				DataManager.saveDB()
				app.updateBadge()
				self.processList(message, replyHandler)

			case "markAllPrsRead":
				if let s = message["sectionIndex"] as? Int {
					PullRequest.markEverythingRead(PullRequestSection(rawValue: s)!, moc: mainObjectContext)
					popupManager.getMasterController().reloadDataWithAnimation(false)
					DataManager.saveDB()
					app.updateBadge()
				}
				self.processList(message, replyHandler)

			case "markAllIssuesRead":
				if let s = message["sectionIndex"] as? Int {
					Issue.markEverythingRead(PullRequestSection(rawValue: s)!, moc: mainObjectContext)
					popupManager.getMasterController().reloadDataWithAnimation(false)
					DataManager.saveDB()
					app.updateBadge()
				}
				self.processList(message, replyHandler)

			case "needsOverview":
				self.updateContext()
				self.reportSuccess([:], replyHandler)

			default:
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
			let sectionIndex = message["sectionIndex"] as! Int
			result["result"] = buildItemList(type, sectionIndex)
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
		r["error"] = true
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

	private func buildItemList(type: String, _ sectionIndex: Int) -> [[String : AnyObject]] {
		var items = [[String : AnyObject]]()

		let sectionIndex = PullRequestSection(rawValue: sectionIndex)!

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
			"commentCount": item.totalComments ?? 0,
			"unreadCount": item.unreadComments ?? 0,
			"localId": item.objectID.URIRepresentation().absoluteString,
		]

		let font = UIFont.systemFontOfSize(UIFont.systemFontSize())
		let smallFont = UIFont.systemFontOfSize(UIFont.systemFontSize()-4)
		itemData["title"] = toData(item.titleWithFont(font, labelFont: font, titleColor: UIColor.whiteColor()))
		if item is PullRequest {
			itemData["subtitle"] = toData((item as! PullRequest).subtitleWithFont(smallFont, lightColor: UIColor.lightGrayColor(), darkColor: UIColor.grayColor()))
		} else {
			itemData["subtitle"] = toData((item as! Issue).subtitleWithFont(smallFont, lightColor: UIColor.lightGrayColor(), darkColor: UIColor.grayColor()))
		}

		if Settings.showLabels {
			itemData["labels"] = labelsForItem(item)
		}
		if showStatuses {
			itemData["statuses"] = statusLinesForPr(item as! PullRequest)
		}
		return itemData
	}

	private func toData(s: NSAttributedString) -> NSData {
		return NSKeyedArchiver.archivedDataWithRootObject(s)
	}

	private func labelsForItem(item: ListableItem) -> [[String : AnyObject]] {
		var labels = [[String : AnyObject]]()
		for l in item.labels {
			labels.append([
				"color": colorToHex(l.colorForDisplay()),
				"text": l.name ?? "NOTEXT"
				])
		}
		return labels
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
		for comment in item.sortedComments(NSComparisonResult.OrderedDescending) {
			comments.append([
				"user": comment.userName ?? "NOUSER",
				"date": comment.createdAt ?? never(),
				"text": comment.body ?? "NOBODY",
				])
		}
		return comments
	}

	//////////////////////////////

	private func buildOverview() -> [String : AnyObject] {
		let totalPrs = PullRequest.countAllRequestsInMoc(mainObjectContext)
		var prs: [String : AnyObject] = [
			"mine": prCountsForSection(PullRequestSection.Mine),
			"participated": prCountsForSection(PullRequestSection.Participated),
			"merged": prCountsForSection(PullRequestSection.Merged),
			"closed": prCountsForSection(PullRequestSection.Closed),
			"other": prCountsForSection(PullRequestSection.All),
			"total": totalPrs,
			"unread": PullRequest.badgeCountInMoc(mainObjectContext)
		]
		if totalPrs==0 {
			prs["error"] = DataManager.reasonForEmptyWithFilter(nil).string
		}

		let totalIssues = Issue.countAllIssuesInMoc(mainObjectContext)
		var issues: [String : AnyObject] = [
			"mine": issueCountsForSection(PullRequestSection.Mine),
			"participated": issueCountsForSection(PullRequestSection.Participated),
			"closed": issueCountsForSection(PullRequestSection.Closed),
			"other": issueCountsForSection(PullRequestSection.All),
			"total": totalIssues,
			"unread": Issue.badgeCountInMoc(mainObjectContext)
		]
		if totalIssues==0 {
			issues["error"] = DataManager.reasonForEmptyIssuesWithFilter(nil).string
		}

		return [
			"prs": prs,
			"issues": issues,
			"preferIssues": Settings.preferIssuesInWatch,
			"lastUpdated": Settings.lastSuccessfulRefresh ?? never()
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
