
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
		do {
			let overview = buildOverview()
			try session?.updateApplicationContext(["overview": overview])
			(overview as NSDictionary).writeToURL(sharedFilesDirectory().URLByAppendingPathComponent("overview.plist"), atomically: true)
		} catch {}
	}

	func startBGTask() {
		backgroundTask = UIApplication.sharedApplication().beginBackgroundTaskWithName("com.housetrip.Trailer.watchrequest") { [weak self] in
			self?.endBGTask()
		}
	}

	func endBGTask() {
		if backgroundTask != UIBackgroundTaskInvalid {
			UIApplication.sharedApplication().endBackgroundTask(backgroundTask)
			backgroundTask = UIBackgroundTaskInvalid
		}
	}

	func session(session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {

		atNextEvent(self) { s in

			s.startBGTask()

			switch(message["command"] as? String ?? "") {
			case "refresh":
				let lastSuccessfulSync = Settings.lastSuccessfulRefresh ?? NSDate()
				app.startRefresh()
				dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)) {
					while app.isRefreshing { NSThread.sleepForTimeInterval(0.1) }
					atNextEvent {
						if Settings.lastSuccessfulRefresh == nil || lastSuccessfulSync.isEqualToDate(Settings.lastSuccessfulRefresh!) {
							s.reportFailure("Refresh Failed", message, replyHandler)
						} else {
							s.processList(message, replyHandler)
						}
					}
				}

			case "openpr":
				if let itemId = message["localId"] as? String {
					let m = popupManager.getMasterController()
					m.openPrWithId(itemId)
					DataManager.saveDB()
				}
				s.processList(message, replyHandler)

			case "openissue":
				if let itemId = message["localId"] as? String {
					let m = popupManager.getMasterController()
					m.openIssueWithId(itemId)
					DataManager.saveDB()
				}
				s.processList(message, replyHandler)

			case "opencomment":
				if let itemId = message["id"] as? String {
					let m = popupManager.getMasterController()
					m.openCommentWithId(itemId)
					DataManager.saveDB()
				}
				s.processList(message, replyHandler)

			case "clearAllMerged":
				app.clearAllMerged()
				s.processList(message, replyHandler)

			case "clearAllClosed":
				app.clearAllClosed()
				s.processList(message, replyHandler)

			case "markPrRead":
				app.markItemAsRead(message["localId"] as? String, reloadView: true)
				s.processList(message, replyHandler)

			case "markIssueRead":
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

		switch(message["list"] as? String ?? "") {

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

		var items = [[String : AnyObject]]()

		let sectionIndex = Section(rawValue: sectionIndex)!

		let f: NSFetchRequest
		var showStatuses = false
		if type == "prs" {
			f = ListableItem.requestForItemsOfType("PullRequest", withFilter: nil, sectionIndex: sectionIndex.rawValue)
			showStatuses = Settings.showStatusItems
		} else {
			f = ListableItem.requestForItemsOfType("Issue", withFilter: nil, sectionIndex: sectionIndex.rawValue)
		}
		f.fetchOffset = from
		f.fetchLimit = count
		let tempMoc = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
		tempMoc.persistentStoreCoordinator = mainObjectContext.persistentStoreCoordinator
		tempMoc.undoManager = nil
		let r = try! tempMoc.executeFetchRequest(f) as! [ListableItem]
		for item in r {
			items.append(self.baseDataForItem(item, showStatuses: showStatuses))
		}
		replyHandler(["result" : items])
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
				"mine": comment.isMine()
				])
		}
		return comments
	}

	//////////////////////////////

	private func buildOverview() -> [String : AnyObject] {
		let totalPrs = PullRequest.countAllRequestsInMoc(mainObjectContext)
		var prs: [String : AnyObject] = [
			"mine": prCountsForSection(Section.Mine),
			"participated": prCountsForSection(Section.Participated),
			"mentioned": prCountsForSection(Section.Mentioned),
			"merged": prCountsForSection(Section.Merged),
			"closed": prCountsForSection(Section.Closed),
			"other": prCountsForSection(Section.All),
			"snoozed": prCountsForSection(Section.Snoozed),
			"total": totalPrs,
			"unread": PullRequest.badgeCountInMoc(mainObjectContext)
		]
		if totalPrs==0 {
			prs["error"] = DataManager.reasonForEmptyWithFilter(nil).string
		}

		let totalIssues = Issue.countAllIssuesInMoc(mainObjectContext)
		var issues: [String : AnyObject] = [
			"mine": issueCountsForSection(Section.Mine),
			"participated": issueCountsForSection(Section.Participated),
			"mentioned": issueCountsForSection(Section.Mentioned),
			"closed": issueCountsForSection(Section.Closed),
			"other": issueCountsForSection(Section.All),
			"snoozed": issueCountsForSection(Section.Snoozed),
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

	private func prCountsForSection(section: Section) -> [String : Int] {
		return ["total": PullRequest.countRequestsInSection(section, moc: mainObjectContext),
				"unread": PullRequest.badgeCountInSection(section, moc: mainObjectContext)];
	}
	private func issueCountsForSection(section: Section) -> [String : Int] {
		return ["total": Issue.countIssuesInSection(section, moc: mainObjectContext),
				"unread": Issue.badgeCountInSection(section, moc: mainObjectContext)];
	}
}
