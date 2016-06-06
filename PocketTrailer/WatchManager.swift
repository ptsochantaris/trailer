
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
		let overviewPath = DataManager.sharedFilesDirectory().URLByAppendingPathComponent("overview.plist")
		(overview as NSDictionary).writeToURL(overviewPath, atomically: true)
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
						let l = Settings.lastSuccessfulRefresh
						if l == nil || lastSuccessfulSync == l! {
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
				app.markItemAsRead(message["localId"] as? String)
				s.processList(message, replyHandler)

			case "markEverythingRead":
				app.markEverythingRead()
				s.processList(message, replyHandler)

			case "markAllPrsRead":
				if var s = message["sectionIndex"] as? Int {
					if s == -1 { s = 0 }
					PullRequest.markEverythingRead(Section(rawValue: s)!, moc: mainObjectContext)
					DataManager.saveDB()
					app.updateBadge()
				}
				s.processList(message, replyHandler)

			case "markAllIssuesRead":
				if var s = message["sectionIndex"] as? Int {
					if s == -1 { s = 0 }
					Issue.markEverythingRead(Section(rawValue: s)!, moc: mainObjectContext)
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
			buildItemList(message["type"] as! String,
			              sectionIndex: message["sectionIndex"] as! Int,
			              from: message["from"] as! Int,
			              apiServerUri: message["apiUri"] as! String,
			              group: message["group"] as! String,
			              count: message["count"] as! Int,
			              onlyUnread: message["onlyUnread"] as! Bool,
			              replyHandler: replyHandler)

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

	private func buildItemList(type: String, sectionIndex: Int, from: Int, apiServerUri: String, group: String, count: Int, onlyUnread: Bool, replyHandler: ([String : AnyObject]) -> Void) {

		let showLabels = Settings.showLabels
		let showStatuses: Bool
		let entity: String
		if type == "prs" {
			entity = "PullRequest"
			showStatuses = Settings.showStatusItems
		} else {
			entity = "Issue"
			showStatuses = false
		}

		let f: NSFetchRequest
		if !apiServerUri.isEmpty, let aid = DataManager.idForUriPath(apiServerUri) {
			let criterion = GroupingCriterion(apiServerId: aid)
			f = ListableItem.requestForItemsOfType(entity, withFilter: nil, sectionIndex: sectionIndex, criterion: criterion, onlyUnread: onlyUnread)
		} else if !group.isEmpty {
			let criterion = GroupingCriterion(repoGroup: group)
			f = ListableItem.requestForItemsOfType(entity, withFilter: nil, sectionIndex: sectionIndex, criterion: criterion, onlyUnread: onlyUnread)
		} else {
			f = ListableItem.requestForItemsOfType(entity, withFilter: nil, sectionIndex: sectionIndex, onlyUnread: onlyUnread)
		}

		f.fetchOffset = from
		f.fetchLimit = count

		// This is needed to avoid a Core Data bug with fetchOffset
		let tempMoc = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
		tempMoc.persistentStoreCoordinator = mainObjectContext.persistentStoreCoordinator
		tempMoc.undoManager = nil

		var items = [[String : AnyObject]]()
		for item in try! tempMoc.executeFetchRequest(f) as! [ListableItem] {
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

		var views = [[String:AnyObject]]()

		for tabSet in popupManager.getMasterController().allTabSets() {

			let c = tabSet.viewCriterion

			let myPrs = countsForType("PullRequest", inSection: .Mine, criterion: c)
			let participatedPrs = countsForType("PullRequest", inSection: .Participated, criterion: c)
			let mentionedPrs = countsForType("PullRequest", inSection: .Mentioned, criterion: c)
			let mergedPrs = countsForType("PullRequest", inSection: .Merged, criterion: c)
			let closedPrs = countsForType("PullRequest", inSection: .Closed, criterion: c)
			let otherPrs = countsForType("PullRequest", inSection: .All, criterion: c)
			let snoozedPrs = countsForType("PullRequest", inSection: .Snoozed, criterion: c)
			let totalPrs = [ myPrs, participatedPrs, mentionedPrs, mergedPrs, closedPrs, otherPrs, snoozedPrs ].reduce(0, combine: { $0 + $1["total"]! })
			let totalOpenPrs = countOpenAndVisibleForType("PullRequest", criterion: c)
			let unreadPrCount = PullRequest.badgeCountInMoc(mainObjectContext, criterion: c)

			let myIssues = countsForType("Issue", inSection: .Mine, criterion: c)
			let participatedIssues = countsForType("Issue", inSection: .Participated, criterion: c)
			let mentionedIssues = countsForType("Issue", inSection: .Mentioned, criterion: c)
			let closedIssues = countsForType("Issue", inSection: .Closed, criterion: c)
			let otherIssues = countsForType("Issue", inSection: .All, criterion: c)
			let snoozedIssues = countsForType("Issue", inSection: .Snoozed, criterion: c)
			let totalIssues = [ myIssues, participatedIssues, mentionedIssues, closedIssues, otherIssues, snoozedIssues ].reduce(0, combine: { $0 + $1["total"]! })
			let totalOpenIssues = countOpenAndVisibleForType("Issue", criterion: c)
			let unreadIssueCount = Issue.badgeCountInMoc(mainObjectContext, criterion: c)

			views.append([
				"title": S(c?.label),
				"apiUri": S(c?.apiServerId?.URIRepresentation().absoluteString),
				"prs": [
					"mine": myPrs, "participated": participatedPrs, "mentioned": mentionedPrs,
					"merged": mergedPrs, "closed": closedPrs, "other": otherPrs, "snoozed": snoozedPrs,
					"total": totalPrs, "total_open": totalOpenPrs, "unread": unreadPrCount,
					"error": totalPrs == 0 ? PullRequest.reasonForEmptyWithFilter(nil, criterion: c).string : ""
				],
				"issues": [
					"mine": myIssues, "participated": participatedIssues, "mentioned": mentionedIssues,
					"closed": closedIssues, "other": otherIssues, "snoozed": snoozedIssues,
					"total": totalIssues, "total_open": totalOpenIssues, "unread": unreadIssueCount,
					"error": totalIssues == 0 ? Issue.reasonForEmptyWithFilter(nil, criterion: c).string : ""
				]])
		}

		return [
			"views": views,
			"preferIssues": Settings.preferIssuesInWatch,
			"lastUpdated": Settings.lastSuccessfulRefresh ?? never()
		]
	}

	private func countsForType(type: String, inSection: Section, criterion: GroupingCriterion?) -> [String : Int] {
		return ["total": countItemsForType(type, inSection: inSection, criterion: criterion),
		        "unread": badgeCountForType(type, inSection: inSection, criterion: criterion)]
	}

	private func countAllItemsOfType(type: String, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest(entityName: type)
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex > 0 and unreadComments > 0") : NSPredicate(format: "sectionIndex > 0")
		DataItem.addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		return mainObjectContext.countForFetchRequest(f, error: nil)
	}

	private func countItemsForType(type: String, inSection: Section, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest(entityName: type)
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex == %d and unreadComments > 0", inSection.rawValue) : NSPredicate(format: "sectionIndex == %d", inSection.rawValue)
		DataItem.addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		return mainObjectContext.countForFetchRequest(f, error: nil)
	}

	private func badgeCountForType(type: String, inSection: Section, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest(entityName: type)
		let p = NSPredicate(format: "sectionIndex == %d and unreadComments > 0", inSection.rawValue)
		DataItem.addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		return ListableItem.badgeCountFromFetch(f, inMoc: mainObjectContext)
	}

	private func countOpenAndVisibleForType(type: String, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest(entityName: type)
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex > 0 and (condition == %d or condition == nil) and unreadComments > 0", ItemCondition.Open.rawValue) : NSPredicate(format: "sectionIndex > 0 and (condition == %d or condition == nil)", ItemCondition.Open.rawValue)
		DataItem.addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		return mainObjectContext.countForFetchRequest(f, error: nil)
	}

}
