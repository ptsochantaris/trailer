
import UIKit
import CoreData
import WatchConnectivity

final class WatchManager : NSObject, WCSessionDelegate {

	private var backgroundTask = UIBackgroundTaskInvalid
	private var session: WCSession?

	override init() {
		super.init()
		if WCSession.isSupported() {
			session = WCSession.defaultSession()
			session?.delegate = self
			session?.activateSession()
		}
	}

	func updateContext() {
		let overview = buildOverview()
		_ = try? session?.updateApplicationContext(["overview": overview])
		(overview as NSDictionary).writeToURL(sharedFilesDirectory().URLByAppendingPathComponent("overview.plist"), atomically: true)
	}

	private func startBGTask() {
		backgroundTask = UIApplication.sharedApplication().beginBackgroundTaskWithName("com.housetrip.Trailer.watchrequest") { [weak self] in
			self?.endBGTask()
		}
	}

	private func endBGTask() {
		if backgroundTask != UIBackgroundTaskInvalid {
			UIApplication.sharedApplication().endBackgroundTask(backgroundTask)
			backgroundTask = UIBackgroundTaskInvalid
		}
	}

	func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {

		atNextEvent(self) { s in

			s.startBGTask()

			switch(S(message["command"] as? String)) {
			case "refresh":
				let lastSuccessfulSync = Settings.lastSuccessfulRefresh ?? NSDate()
				app.startRefresh()
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
					while appIsRefreshing { NSThread.sleepForTimeInterval(0.1) }
					atNextEvent {
						if Settings.lastSuccessfulRefresh == nil || lastSuccessfulSync.isEqualToDate(Settings.lastSuccessfulRefresh!) {
							s.reportFailure("Refresh Failed", message, replyHandler)
						} else {
							s.processList(message, replyHandler)
						}
					}
				}

			case "openpr", "openissue":
				if let itemId = message["localId"] as? String {
					popupManager.getMasterController().openItemWithUriPath(itemId)
					DataManager.saveDB()
				}
				s.processList(message, replyHandler)

			case "opencomment":
				if let itemId = message["id"] as? String {
					popupManager.getMasterController().openCommentWithId(itemId)
					DataManager.saveDB()
				}
				s.processList(message, replyHandler)

			case "clearAllMerged":
				app.clearAllMerged()
				s.processList(message, replyHandler)

			case "clearAllClosed":
				app.clearAllClosed()
				s.processList(message, replyHandler)

			case "markPrRead", "markIssueRead":
				app.markItemAsRead(message["localId"] as? String, reloadView: true)
				s.processList(message, replyHandler)

			case "markEverythingRead":
				app.markEverythingRead()
				s.processList(message, replyHandler)

			case "markAllPrsRead":
				if let s = message["sectionIndex"] as? Int {
					PullRequest.markEverythingRead(Section(rawValue: s)!, moc: mainObjectContext)
					popupManager.getMasterController().reloadDataWithAnimation(false)
					DataManager.saveDB()
					app.updateBadge()
				}
				s.processList(message, replyHandler)

			case "markAllIssuesRead":
				if let s = message["sectionIndex"] as? Int {
					Issue.markEverythingRead(Section(rawValue: s)!, moc: mainObjectContext)
					popupManager.getMasterController().reloadDataWithAnimation(false)
					DataManager.saveDB()
					app.updateBadge()
				}
				s.processList(message, replyHandler)

			case "needsOverview":
				s.updateContext()
				s.reportSuccess([:], replyHandler)

			default:
				s.processList(message, replyHandler)
			}
		}
	}

	private func processList(message: [String : AnyObject], _ replyHandler: ([String : AnyObject]) -> Void) {

		var result = [String : AnyObject]()

		switch(S(message["list"] as? String)) {

		case "overview":
			result["result"] = buildOverview()
			reportSuccess(result, replyHandler)

		case "item_list":
			let type = message["type"] as! String
			let sectionIndex = message["sectionIndex"] as! Int
			let from = message["from"] as! Int
			let count = message["count"] as! Int
			buildItemList(type, sectionIndex: sectionIndex, from: from, count: count, replyHandler: replyHandler)

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

	private func buildItemList(type: String, sectionIndex: Int, from: Int, count: Int, replyHandler: ([String : AnyObject]) -> Void) {

		let showLabels = Settings.showLabels
		let showStatuses: Bool
		let f: NSFetchRequest

		if type == "prs" {
			showStatuses = Settings.showStatusItems
			f = ListableItem.requestForItemsOfType("PullRequest", withFilter: nil, sectionIndex: sectionIndex)
		} else {
			showStatuses = false
			f = ListableItem.requestForItemsOfType("Issue", withFilter: nil, sectionIndex: sectionIndex)
		}
		f.fetchOffset = from
		f.fetchLimit = count

		let tempMoc = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
		tempMoc.persistentStoreCoordinator = mainObjectContext.persistentStoreCoordinator
		tempMoc.undoManager = nil
		let r = try! tempMoc.executeFetchRequest(f) as! [ListableItem]

		var items = [[String : AnyObject]]()
		for item in r {
			items.append(baseDataForItem(item, showStatuses: showStatuses, showLabels: showLabels))
		}
		replyHandler(["result" : items])
	}

	private func baseDataForItem(item: ListableItem, showStatuses: Bool, showLabels: Bool) -> [String : AnyObject] {

		var itemData = [
			"commentCount": item.totalComments ?? 0,
			"unreadCount": item.unreadComments ?? 0,
			"localId": item.objectID.URIRepresentation().absoluteString,
		]

		let font = UIFont.systemFontOfSize(UIFont.systemFontSize())
		let smallFont = UIFont.systemFontOfSize(UIFont.systemFontSize()-4)
		let lightGray = UIColor.lightGrayColor()
		let gray = UIColor.grayColor()

		let title = item.titleWithFont(font, labelFont: font, titleColor: UIColor.whiteColor())
		itemData["title"] = NSKeyedArchiver.archivedDataWithRootObject(title)

		if let i = item as? PullRequest {
			let subtitle = i.subtitleWithFont(smallFont, lightColor: lightGray, darkColor: gray)
			itemData["subtitle"] = NSKeyedArchiver.archivedDataWithRootObject(subtitle)
		} else if let i = item as? Issue {
			let subtitle = i.subtitleWithFont(smallFont, lightColor: lightGray, darkColor: gray)
			itemData["subtitle"] = NSKeyedArchiver.archivedDataWithRootObject(subtitle)
		}

		if showLabels {
			itemData["labels"] = labelsForItem(item)
		}
		if showStatuses {
			itemData["statuses"] = statusLinesForPr(item as! PullRequest)
		}
		return itemData
	}

	private func labelsForItem(item: ListableItem) -> [[String : AnyObject]] {
		var labels = [[String : AnyObject]]()
		for l in item.labels {
			labels.append([
				"color": colorToHex(l.colorForDisplay),
				"text": S(l.name)
				])
		}
		return labels
	}

	private func statusLinesForPr(pr: PullRequest) -> [[String : AnyObject]] {
		var statusLines = [[String : AnyObject]]()
		for status in pr.displayedStatuses {
			statusLines.append([
				"color": colorToHex(status.colorForDarkDisplay),
				"text": S(status.descriptionText)
				])
		}
		return statusLines
	}

	/////////////////////////////

	private func buildItemDetail(localId: String) -> [String : AnyObject]? {
		if let oid = DataManager.idForUriPath(localId), item = existingObjectWithID(oid) as? ListableItem {
			let showStatuses = (item is PullRequest) ? Settings.showStatusItems : false
			var result = baseDataForItem(item, showStatuses: showStatuses, showLabels: Settings.showLabels)
			result["description"] = item.body
			result["comments"] = commentsForItem(item)
			return result
		}
		return nil
	}

	private func commentsForItem(item: ListableItem) -> [[String : AnyObject]] {
		var comments = [[String : AnyObject]]()
		for comment in item.sortedComments(.OrderedDescending) {
			comments.append([
				"user": S(comment.userName),
				"date": comment.createdAt ?? never(),
				"text": S(comment.body),
				"mine": comment.isMine
				])
		}
		return comments
	}

	//////////////////////////////

	private func buildOverview() -> [String : AnyObject] {
		let totalPrs = PullRequest.countAllInMoc(mainObjectContext)
		var prs: [String : AnyObject] = [
			"mine": prCountsForSection(.Mine),
			"participated": prCountsForSection(.Participated),
			"mentioned": prCountsForSection(.Mentioned),
			"merged": prCountsForSection(.Merged),
			"closed": prCountsForSection(.Closed),
			"other": prCountsForSection(.All),
			"snoozed": prCountsForSection(.Snoozed),
			"total": totalPrs,
			"total_open": PullRequest.countOpenAndVisibleInMoc(mainObjectContext),
			"unread": PullRequest.badgeCountInMoc(mainObjectContext)
		]
		if totalPrs==0 {
			prs["error"] = PullRequest.reasonForEmptyWithFilter(nil).string
		}

		let totalIssues = Issue.countAllInMoc(mainObjectContext)
		var issues: [String : AnyObject] = [
			"mine": issueCountsForSection(.Mine),
			"participated": issueCountsForSection(.Participated),
			"mentioned": issueCountsForSection(.Mentioned),
			"closed": issueCountsForSection(.Closed),
			"other": issueCountsForSection(.All),
			"snoozed": issueCountsForSection(.Snoozed),
			"total": totalIssues,
			"total_open": Issue.countOpenAndVisibleInMoc(mainObjectContext),
			"unread": Issue.badgeCountInMoc(mainObjectContext)
		]
		if totalIssues==0 {
			issues["error"] = Issue.reasonForEmptyWithFilter(nil).string
		}

		return [
			"prs": prs,
			"issues": issues,
			"preferIssues": Settings.preferIssuesInWatch,
			"lastUpdated": Settings.lastSuccessfulRefresh ?? never()
		]
	}

	private func prCountsForSection(section: Section) -> [String : Int] {
		return ["total": PullRequest.countRequestsInSection(section, moc: mainObjectContext),
				"unread": PullRequest.badgeCountInSection(section, moc: mainObjectContext)]
	}
	private func issueCountsForSection(section: Section) -> [String : Int] {
		return ["total": Issue.countIssuesInSection(section, moc: mainObjectContext),
				"unread": Issue.badgeCountInSection(section, moc: mainObjectContext)]
	}
}
