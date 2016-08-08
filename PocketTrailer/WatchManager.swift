
import UIKit
import CoreData
import WatchConnectivity

final class WatchManager : NSObject, WCSessionDelegate {

	private var backgroundTask = UIBackgroundTaskInvalid
	private var session: WCSession?

	override init() {
		super.init()
		if WCSession.isSupported() {
			session = WCSession.default()
			session?.delegate = self
			session?.activate()
		}
	}

	@available(iOS 9.3, *)
	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		atNextEvent(self) { S in
			S.updateContext()
		}
	}

	func sessionDidDeactivate(_ session: WCSession) { }

	func sessionDidBecomeInactive(_ session: WCSession) { }

	func updateContext() {
		let overview = buildOverview()
		_ = try? session?.updateApplicationContext(["overview": overview])
		let overviewPath = DataManager.sharedFilesDirectory().appendingPathComponent("overview.plist")
		(overview as NSDictionary).write(to: overviewPath, atomically: true)
	}

	private func startBGTask() {
		backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "com.housetrip.Trailer.watchrequest") { [weak self] in
			self?.endBGTask()
		}
	}

	private func endBGTask() {
		if backgroundTask != UIBackgroundTaskInvalid {
			UIApplication.shared.endBackgroundTask(backgroundTask)
			backgroundTask = UIBackgroundTaskInvalid
		}
	}

	func session(_ session: WCSession, didReceiveMessage message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {

		atNextEvent(self) { s in

			s.startBGTask()

			switch(S(message["command"] as? String)) {

			case "refresh":
				let lastSuccessfulSync = Settings.lastSuccessfulRefresh ?? Date()
				_ = app.startRefresh()
				DispatchQueue.global().async {
					while appIsRefreshing { Thread.sleep(forTimeInterval: 0.1) }
					atNextEvent {
						let l = Settings.lastSuccessfulRefresh
						if l == nil || lastSuccessfulSync == l! {
							s.reportFailure(reason: "Refresh Failed", result: message, replyHandler: replyHandler)
						} else {
							s.processList(message: message, replyHandler: replyHandler)
						}
					}
				}

			case "openItem":
				if let itemId = message["localId"] as? String {
					popupManager.getMasterController().openItemWithUriPath(uriPath: itemId)
					DataManager.saveDB()
				}
				s.processList(message: message, replyHandler: replyHandler)

			case "opencomment":
				if let itemId = message["id"] as? String {
					popupManager.getMasterController().openCommentWithId(cId: itemId)
					DataManager.saveDB()
				}
				s.processList(message: message, replyHandler: replyHandler)

			case "clearAllMerged":
				app.clearAllMerged()
				s.processList(message: message, replyHandler: replyHandler)

			case "clearAllClosed":
				app.clearAllClosed()
				s.processList(message: message, replyHandler: replyHandler)

			case "markEverythingRead":
				app.markEverythingRead()
				s.processList(message: message, replyHandler: replyHandler)

			case "markItemsRead":
				if let
					uri = message["localId"] as? String,
					let oid = DataManager.idForUriPath(uri),
					let dataItem = existingObjectWithID(oid) as? ListableItem,
					dataItem.unreadComments > 0 {

					dataItem.catchUpWithComments()
					
				} else if let uris = message["itemUris"] as? [String] {
					for uri in uris {
						if let
							oid = DataManager.idForUriPath(uri),
							let dataItem = existingObjectWithID(oid) as? ListableItem,
							dataItem.unreadComments > 0 {

							dataItem.catchUpWithComments()
						}
					}
				}
				DataManager.saveDB()
				app.updateBadge()
				s.processList(message: message, replyHandler: replyHandler)

			case "needsOverview":
				s.updateContext()
				s.reportSuccess(result: [:], replyHandler: replyHandler)

			default:
				s.processList(message: message, replyHandler: replyHandler)
			}
		}
	}

	private func processList(message: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {

		var result = [String : AnyObject]()

		switch(S(message["list"] as? String)) {

		case "overview":
			result["result"] = buildOverview()
			reportSuccess(result: result, replyHandler: replyHandler)

		case "item_list":
			buildItemList(type: message["type"] as! String,
			              sectionIndex: message["sectionIndex"] as! Int64,
			              from: message["from"] as! Int,
			              apiServerUri: message["apiUri"] as! String,
			              group: message["group"] as! String,
			              count: message["count"] as! Int,
			              onlyUnread: message["onlyUnread"] as! Bool,
			              replyHandler: replyHandler)

		case "item_detail":
			if let lid = message["localId"] as? String, let details = buildItemDetail(localId: lid) {
				result["result"] = details
				reportSuccess(result: result, replyHandler: replyHandler)
			} else {
				reportFailure(reason: "Item Not Found", result: result, replyHandler: replyHandler)
			}

		default:
			reportSuccess(result: result, replyHandler: replyHandler)
		}
	}

	private func reportFailure(reason: String, result: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {
		var r = result
		r["error"] = true
		r["status"] = reason
		r["color"] = "FF0000"
		replyHandler(r)
		endBGTask()
	}

	private func reportSuccess(result: [String : AnyObject], replyHandler: ([String : AnyObject]) -> Void) {
		var r = result
		r["status"] = "Success"
		r["color"] = "00FF00"
		replyHandler(r)
		endBGTask()
	}

	////////////////////////////

	private func buildItemList(type: String, sectionIndex: Int64, from: Int, apiServerUri: String, group: String, count: Int, onlyUnread: Bool, replyHandler: ([String : AnyObject]) -> Void) {

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

		let f: NSFetchRequest<ListableItem>
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
		let tempMoc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		tempMoc.persistentStoreCoordinator = mainObjectContext.persistentStoreCoordinator
		tempMoc.undoManager = nil

		var items = [[String : AnyObject]]()
		for item in try! tempMoc.fetch(f) {
			items.append(baseDataForItem(item: item, showStatuses: showStatuses, showLabels: showLabels))
		}
		replyHandler(["result" : items])
	}

	private func baseDataForItem(item: ListableItem, showStatuses: Bool, showLabels: Bool) -> [String : AnyObject] {

		var itemData = [
			"commentCount": NSNumber(value: item.totalComments),
			"unreadCount": NSNumber(value: item.unreadComments),
			"localId": item.objectID.uriRepresentation().absoluteString,
		]

		let font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
		let smallFont = UIFont.systemFont(ofSize: UIFont.systemFontSize-4)
		let lightGray = UIColor.lightGray
		let gray = UIColor.gray

		let title = item.titleWithFont(font, labelFont: font, titleColor: UIColor.white)
		itemData["title"] = NSKeyedArchiver.archivedData(withRootObject: title)

		if let i = item as? PullRequest {
			let subtitle = i.subtitleWithFont(smallFont, lightColor: lightGray, darkColor: gray)
			itemData["subtitle"] = NSKeyedArchiver.archivedData(withRootObject: subtitle)
		} else if let i = item as? Issue {
			let subtitle = i.subtitleWithFont(smallFont, lightColor: lightGray, darkColor: gray)
			itemData["subtitle"] = NSKeyedArchiver.archivedData(withRootObject: subtitle)
		}

		if showLabels {
			itemData["labels"] = labelsForItem(item: item)
		}
		if showStatuses {
			itemData["statuses"] = statusLinesForPr(pr: item as! PullRequest)
		}
		return itemData
	}

	private func labelsForItem(item: ListableItem) -> [[String : AnyObject]] {
		var labels = [[String : AnyObject]]()
		for l in item.labels {
			labels.append([
				"color": colorToHex(c: l.colorForDisplay),
				"text": S(l.name)
				])
		}
		return labels
	}

	private func statusLinesForPr(pr: PullRequest) -> [[String : AnyObject]] {
		var statusLines = [[String : AnyObject]]()
		for status in pr.displayedStatuses {
			statusLines.append([
				"color": colorToHex(c: status.colorForDarkDisplay),
				"text": S(status.descriptionText)
				])
		}
		return statusLines
	}

	/////////////////////////////

	private func buildItemDetail(localId: String) -> [String : AnyObject]? {
		if let oid = DataManager.idForUriPath(localId), let item = existingObjectWithID(oid) as? ListableItem {
			let showStatuses = (item is PullRequest) ? Settings.showStatusItems : false
			var result = baseDataForItem(item: item, showStatuses: showStatuses, showLabels: Settings.showLabels)
			result["description"] = item.body
			result["comments"] = commentsForItem(item: item)
			return result
		}
		return nil
	}

	private func commentsForItem(item: ListableItem) -> [[String : AnyObject]] {
		var comments = [[String : AnyObject]]()
		for comment in item.sortedComments(.orderedDescending) {
			comments.append([
				"user": S(comment.userName),
				"date": comment.createdAt ?? Date.distantPast,
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

			let myPrs = countsForType(type: "PullRequest", inSection: .mine, criterion: c)
			let participatedPrs = countsForType(type: "PullRequest", inSection: .participated, criterion: c)
			let mentionedPrs = countsForType(type: "PullRequest", inSection: .mentioned, criterion: c)
			let mergedPrs = countsForType(type: "PullRequest", inSection: .merged, criterion: c)
			let closedPrs = countsForType(type: "PullRequest", inSection: .closed, criterion: c)
			let otherPrs = countsForType(type: "PullRequest", inSection: .all, criterion: c)
			let snoozedPrs = countsForType(type: "PullRequest", inSection: .snoozed, criterion: c)
			let totalPrs = [ myPrs, participatedPrs, mentionedPrs, mergedPrs, closedPrs, otherPrs, snoozedPrs ].reduce(0, { $0 + $1["total"]! })
			let totalOpenPrs = countOpenAndVisibleForType(type: "PullRequest", criterion: c)
			let unreadPrCount = PullRequest.badgeCountInMoc(mainObjectContext, criterion: c)

			let myIssues = countsForType(type: "Issue", inSection: .mine, criterion: c)
			let participatedIssues = countsForType(type: "Issue", inSection: .participated, criterion: c)
			let mentionedIssues = countsForType(type: "Issue", inSection: .mentioned, criterion: c)
			let closedIssues = countsForType(type: "Issue", inSection: .closed, criterion: c)
			let otherIssues = countsForType(type: "Issue", inSection: .all, criterion: c)
			let snoozedIssues = countsForType(type: "Issue", inSection: .snoozed, criterion: c)
			let totalIssues = [ myIssues, participatedIssues, mentionedIssues, closedIssues, otherIssues, snoozedIssues ].reduce(0, { $0 + $1["total"]! })
			let totalOpenIssues = countOpenAndVisibleForType(type: "Issue", criterion: c)
			let unreadIssueCount = Issue.badgeCountInMoc(mainObjectContext, criterion: c)

			views.append([
				"title": S(c?.label),
				"apiUri": S(c?.apiServerId?.uriRepresentation().absoluteString),
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
			"lastUpdated": Settings.lastSuccessfulRefresh ?? Date.distantPast
		]
	}

	private func countsForType(type: String, inSection: Section, criterion: GroupingCriterion?) -> [String : Int] {
		return ["total": countItemsForType(type: type, inSection: inSection, criterion: criterion),
		        "unread": badgeCountForType(type: type, inSection: inSection, criterion: criterion)]
	}

	private func countAllItemsOfType(type: String, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest<ListableItem>(entityName: type)
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex > 0 and unreadComments > 0") : NSPredicate(format: "sectionIndex > 0")
		DataItem.addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		return try! mainObjectContext.count(for: f)
	}

	private func countItemsForType(type: String, inSection: Section, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest<ListableItem>(entityName: type)
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex == %lld and unreadComments > 0", inSection.rawValue) : NSPredicate(format: "sectionIndex == %d", inSection.rawValue)
		DataItem.addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		return try! mainObjectContext.count(for: f)
	}

	private func badgeCountForType(type: String, inSection: Section, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest<ListableItem>(entityName: type)
		let p = NSPredicate(format: "sectionIndex == %lld and unreadComments > 0", inSection.rawValue)
		DataItem.addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		return ListableItem.badgeCountFromFetch(f, inMoc: mainObjectContext)
	}

	private func countOpenAndVisibleForType(type: String, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest<ListableItem>(entityName: type)
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex > 0 and (condition == %lld or condition == nil) and unreadComments > 0", ItemCondition.open.rawValue) : NSPredicate(format: "sectionIndex > 0 and (condition == %lld or condition == nil)", ItemCondition.open.rawValue)
		DataItem.addCriterion(criterion, toFetchRequest: f, originalPredicate: p, inMoc: mainObjectContext)
		return try! mainObjectContext.count(for: f)
	}

}
