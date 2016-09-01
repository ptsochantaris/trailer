
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

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		if activationState == .activated {
			atNextEvent(self) { S in
				S.updateContext()
			}
		}
	}

	func sessionDidDeactivate(_ session: WCSession) { }

	func sessionDidBecomeInactive(_ session: WCSession) { }

	func updateContext() {
		let overview = buildOverview()
		_ = try? session?.updateApplicationContext(["overview": overview])
		let overviewPath = DataManager.sharedFilesDirectory.appendingPathComponent("overview.plist")
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

	func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {

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
					popupManager.masterController.openItemWithUriPath(uriPath: itemId)
					DataManager.saveDB()
				}
				s.processList(message: message, replyHandler: replyHandler)

			case "opencomment":
				if let itemId = message["id"] as? String {
					popupManager.masterController.openCommentWithId(cId: itemId)
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
					let oid = DataManager.id(for: uri),
					let dataItem = existingObject(with: oid) as? ListableItem,
					dataItem.unreadComments > 0 {

					dataItem.catchUpWithComments()
					
				} else if let uris = message["itemUris"] as? [String] {
					for uri in uris {
						if let
							oid = DataManager.id(for: uri),
							let dataItem = existingObject(with: oid) as? ListableItem,
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

	private func processList(message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {

		var result = [String : Any]()

		switch(S(message["list"] as? String)) {

		case "overview":
			result["result"] = buildOverview()
			reportSuccess(result: result, replyHandler: replyHandler)

		case "item_list":
			buildItemList(type: message["type"] as! String,
			              sectionIndex: (message["sectionIndex"] as! NSNumber).int64Value,
			              from: (message["from"] as! NSNumber).intValue,
			              apiServerUri: message["apiUri"] as! String,
			              group: message["group"] as! String,
			              count: (message["count"] as! NSNumber).intValue,
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

	private func reportFailure(reason: String, result: [String : Any], replyHandler: ([String : Any]) -> Void) {
		var r = result
		r["error"] = true
		r["status"] = reason
		r["color"] = "FF0000"
		replyHandler(r)
		endBGTask()
	}

	private func reportSuccess(result: [String : Any], replyHandler: ([String : Any]) -> Void) {
		var r = result
		r["status"] = "Success"
		r["color"] = "00FF00"
		replyHandler(r)
		endBGTask()
	}

	////////////////////////////

	private func buildItemList(type: String, sectionIndex: Int64, from: Int, apiServerUri: String, group: String, count: Int, onlyUnread: Bool, replyHandler: @escaping ([String : Any]) -> Void) {

		let showLabels = Settings.showLabels
		let showStatuses: Bool
		let entity: ListableItem.Type
		if type == "prs" {
			entity = PullRequest.self
			showStatuses = Settings.showStatusItems
		} else {
			entity = Issue.self
			showStatuses = false
		}

		let f: NSFetchRequest<ListableItem>
		if !apiServerUri.isEmpty, let aid = DataManager.id(for: apiServerUri) {
			let criterion = GroupingCriterion(apiServerId: aid)
			f = ListableItem.requestForItems(of: entity, withFilter: nil, sectionIndex: sectionIndex, criterion: criterion, onlyUnread: onlyUnread)
		} else if !group.isEmpty {
			let criterion = GroupingCriterion(repoGroup: group)
			f = ListableItem.requestForItems(of: entity, withFilter: nil, sectionIndex: sectionIndex, criterion: criterion, onlyUnread: onlyUnread)
		} else {
			f = ListableItem.requestForItems(of: entity, withFilter: nil, sectionIndex: sectionIndex, onlyUnread: onlyUnread)
		}

		f.fetchOffset = from
		f.fetchLimit = count

		// This is needed to avoid a Core Data bug with fetchOffset
		let tempMoc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		tempMoc.persistentStoreCoordinator = DataManager.main.persistentStoreCoordinator
		tempMoc.undoManager = nil

		var items = [[String : Any]]()
		for item in try! tempMoc.fetch(f) {
			items.append(baseDataForItem(item: item, showStatuses: showStatuses, showLabels: showLabels))
		}
		replyHandler(["result" : items])
	}

	private func baseDataForItem(item: ListableItem, showStatuses: Bool, showLabels: Bool) -> [String : Any] {

		var itemData: [String : Any] = [
			"commentCount": NSNumber(value: item.totalComments),
			"unreadCount": NSNumber(value: item.unreadComments),
			"localId": item.objectID.uriRepresentation().absoluteString,
		]

		let font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
		let smallFont = UIFont.systemFont(ofSize: UIFont.systemFontSize-4)

		let title = item.title(with: font, labelFont: font, titleColor: .white)
		itemData["title"] = NSKeyedArchiver.archivedData(withRootObject: title)

		if let i = item as? PullRequest {
			let subtitle = i.subtitle(with: smallFont, lightColor: .lightGray, darkColor: .gray)
			itemData["subtitle"] = NSKeyedArchiver.archivedData(withRootObject: subtitle)
		} else if let i = item as? Issue {
			let subtitle = i.subtitle(with: smallFont, lightColor: .lightGray, darkColor: .gray)
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

	private func labelsForItem(item: ListableItem) -> [[String : Any]] {
		var labels = [[String : Any]]()
		for l in item.labels {
			labels.append([
				"color": colorToHex(c: l.colorForDisplay),
				"text": S(l.name)
				])
		}
		return labels
	}

	private func statusLinesForPr(pr: PullRequest) -> [[String : Any]] {
		var statusLines = [[String : Any]]()
		for status in pr.displayedStatuses {
			statusLines.append([
				"color": colorToHex(c: status.colorForDarkDisplay),
				"text": S(status.descriptionText)
				])
		}
		return statusLines
	}

	private func colorToHex(c: UIColor) -> String {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		c.getRed(&r, green: &g, blue: &b, alpha: &a)
		r *= 255.0
		g *= 255.0
		b *= 255.0
		return String(format: "%02X%02X%02X", Int(r), Int(g), Int(b))
	}

	/////////////////////////////

	private func buildItemDetail(localId: String) -> [String : Any]? {
		if let oid = DataManager.id(for: localId), let item = existingObject(with: oid) as? ListableItem {
			let showStatuses = (item is PullRequest) ? Settings.showStatusItems : false
			var result = baseDataForItem(item: item, showStatuses: showStatuses, showLabels: Settings.showLabels)
			result["description"] = item.body
			result["comments"] = commentsForItem(item: item)
			return result
		}
		return nil
	}

	private func commentsForItem(item: ListableItem) -> [[String : Any]] {
		var comments = [[String : Any]]()
		for comment in item.sortedComments(using: .orderedDescending) {
			comments.append([
				"user": S(comment.userName),
				"date": comment.createdAt ?? .distantPast,
				"text": S(comment.body),
				"mine": comment.isMine
				])
		}
		return comments
	}

	//////////////////////////////

	private func buildOverview() -> [String : Any] {

		var views = [[String : Any]]()

		for tabSet in popupManager.masterController.allTabSets {

			let c = tabSet.viewCriterion

			let myPrs = counts(for: PullRequest.self, in: .mine, criterion: c)
			let participatedPrs = counts(for: PullRequest.self, in: .participated, criterion: c)
			let mentionedPrs = counts(for: PullRequest.self, in: .mentioned, criterion: c)
			let mergedPrs = counts(for: PullRequest.self, in: .merged, criterion: c)
			let closedPrs = counts(for: PullRequest.self, in: .closed, criterion: c)
			let otherPrs = counts(for: PullRequest.self, in: .all, criterion: c)
			let snoozedPrs = counts(for: PullRequest.self, in: .snoozed, criterion: c)
			let totalPrs = [ myPrs, participatedPrs, mentionedPrs, mergedPrs, closedPrs, otherPrs, snoozedPrs ].reduce(0, { $0 + $1["total"]! })

			let totalOpenPrs = countOpenAndVisible(of: PullRequest.self, criterion: c)
			let unreadPrCount = PullRequest.badgeCount(in: DataManager.main, criterion: c)

			let myIssues = counts(for: Issue.self, in: .mine, criterion: c)
			let participatedIssues = counts(for: Issue.self, in: .participated, criterion: c)
			let mentionedIssues = counts(for: Issue.self, in: .mentioned, criterion: c)
			let closedIssues = counts(for: Issue.self, in: .closed, criterion: c)
			let otherIssues = counts(for: Issue.self, in: .all, criterion: c)
			let snoozedIssues = counts(for: Issue.self, in: .snoozed, criterion: c)
			let totalIssues = [ myIssues, participatedIssues, mentionedIssues, closedIssues, otherIssues, snoozedIssues ].reduce(0, { $0 + $1["total"]! })

			let totalOpenIssues = countOpenAndVisible(of: Issue.self, criterion: c)
			let unreadIssueCount = Issue.badgeCount(in: DataManager.main, criterion: c)

			views.append([
				"title": S(c?.label),
				"apiUri": S(c?.apiServerId?.uriRepresentation().absoluteString),
				"prs": [
					"mine": myPrs, "participated": participatedPrs, "mentioned": mentionedPrs,
					"merged": mergedPrs, "closed": closedPrs, "other": otherPrs, "snoozed": snoozedPrs,
					"total": totalPrs, "total_open": totalOpenPrs, "unread": unreadPrCount,
					"error": totalPrs == 0 ? PullRequest.reasonForEmpty(with: nil, criterion: c).string : ""
				],
				"issues": [
					"mine": myIssues, "participated": participatedIssues, "mentioned": mentionedIssues,
					"closed": closedIssues, "other": otherIssues, "snoozed": snoozedIssues,
					"total": totalIssues, "total_open": totalOpenIssues, "unread": unreadIssueCount,
					"error": totalIssues == 0 ? Issue.reasonForEmpty(with: nil, criterion: c).string : ""
				]])
		}

		return [
			"views": views,
			"preferIssues": Settings.preferIssuesInWatch,
			"lastUpdated": Settings.lastSuccessfulRefresh ?? .distantPast
		]
	}

	private func counts<T: ListableItem>(for type: T.Type, in section: Section, criterion: GroupingCriterion?) -> [String : Int] {
		return ["total": countItems(of: type, in: section, criterion: criterion),
		        "unread": badgeCount(for: type, in: section, criterion: criterion)]
	}

	private func countallItems<T: ListableItem>(of type: T.Type, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest<T>(entityName: typeName(type))
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex > 0 and unreadComments > 0") : NSPredicate(format: "sectionIndex > 0")
		DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: DataManager.main)
		return try! DataManager.main.count(for: f)
	}

	private func countItems<T: ListableItem>(of type: T.Type, in section: Section, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest<T>(entityName: typeName(type))
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex == %lld and unreadComments > 0", section.rawValue) : NSPredicate(format: "sectionIndex == %lld", section.rawValue)
		DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: DataManager.main)
		return try! DataManager.main.count(for: f)
	}

	private func badgeCount<T: ListableItem>(for type: T.Type, in section: Section, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest<T>(entityName: typeName(type))
		let p = NSPredicate(format: "sectionIndex == %lld and unreadComments > 0", section.rawValue)
		DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: DataManager.main)
		return ListableItem.badgeCount(from: f, in: DataManager.main)
	}

	private func countOpenAndVisible<T: ListableItem>(of type: T.Type, criterion: GroupingCriterion?) -> Int {
		let f = NSFetchRequest<T>(entityName: typeName(type))
		let p = Settings.hideUncommentedItems ? NSPredicate(format: "sectionIndex > 0 and (condition == %lld or condition == nil) and unreadComments > 0", ItemCondition.open.rawValue) : NSPredicate(format: "sectionIndex > 0 and (condition == %lld or condition == nil)", ItemCondition.open.rawValue)
		DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: DataManager.main)
		return try! DataManager.main.count(for: f)
	}

}
