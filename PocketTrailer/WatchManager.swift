
import UIKit
import CoreData
import WatchConnectivity

final class WatchManager : NSObject, WCSessionDelegate {

	private var session: WCSession?

	override init() {
		super.init()
		if WCSession.isSupported() {
			session = WCSession.default
			session?.delegate = self
			session?.activate()
		}
	}

	func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
		if session.isPaired, session.isWatchAppInstalled, activationState == .activated {
			atNextEvent(self) { S in
				S.sendOverview()
			}
		}
	}

	func sessionReachabilityDidChange(_ session: WCSession) {
		if session.isPaired, session.isWatchAppInstalled, session.activationState == .activated, session.isReachable {
			atNextEvent(self) { S in
				S.sendOverview()
			}
		}
	}

	func sessionDidDeactivate(_ session: WCSession) {}

	func sessionDidBecomeInactive(_ session: WCSession) {}

	private func sendOverview() {

		let validSession = (session?.isPaired ?? false)
			&& (session?.isWatchAppInstalled ?? false)
			&& session?.activationState == .activated

		do {
			if validSession, let overview = NSDictionary(contentsOf: overviewPath) {
				try session?.updateApplicationContext(["overview": overview])
			}
		} catch {
			DLog("Error updating watch session: %@", error.localizedDescription)
		}
	}

	func updateContext() {
		DataManager.saveDB()

		buildOverview { [weak self] overview in
			guard let s = self else { return }

			(overview as NSDictionary).write(to: s.overviewPath, atomically: true)
			s.sendOverview()
		}
	}

	private var overviewPath: URL {
		return DataManager.dataFilesDirectory.appendingPathComponent("overview.plist")
	}

	func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
		atNextEvent(self) { s in
			s.handle(message: message, replyHandler: replyHandler)
		}
	}

	private func handle(message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {

		switch(S(message["command"] as? String)) {

		case "refresh":
			let status = app.startRefresh()
			switch status {
			case .started:
				reportSuccess(result: [:], replyHandler: replyHandler)
			case .noNetwork:
				reportFailure(reason: "Can't refresh, check your Internet connection.", result: [:], replyHandler: replyHandler)
			case .alreadyRefreshing:
				reportFailure(reason: "Already refreshing, please wait.", result: [:], replyHandler: replyHandler)
			case .noConfiguredServers:
				reportFailure(reason: "Can't refresh, there are no configured servers.", result: [:], replyHandler: replyHandler)
			}

		case "openItem":
			if let itemId = message["localId"] as? String {
				popupManager.masterController.openItemWithUriPath(uriPath: itemId)
			}
			processList(message: message, replyHandler: replyHandler)

		case "opencomment":
			if let itemId = message["id"] as? String {
				popupManager.masterController.openCommentWithId(cId: itemId)
			}
			processList(message: message, replyHandler: replyHandler)

		case "clearAllMerged":
			app.clearAllMerged()
			processList(message: message, replyHandler: replyHandler)

		case "clearAllClosed":
			app.clearAllClosed()
			processList(message: message, replyHandler: replyHandler)

		case "markEverythingRead":
			app.markEverythingRead()
			processList(message: message, replyHandler: replyHandler)

		case "markItemsRead":
			if let
				uri = message["localId"] as? String,
				let oid = DataManager.id(for: uri),
				let dataItem = existingObject(with: oid) as? ListableItem,
				dataItem.hasUnreadCommentsOrAlert {

				dataItem.catchUpWithComments()

			} else if let uris = message["itemUris"] as? [String] {
				for uri in uris {
					if let
						oid = DataManager.id(for: uri),
						let dataItem = existingObject(with: oid) as? ListableItem,
						dataItem.hasUnreadCommentsOrAlert {

						dataItem.catchUpWithComments()
					}
				}
			}
			processList(message: message, replyHandler: replyHandler)

		case "needsOverview":
			sendOverview()
			reportSuccess(result: [:], replyHandler: replyHandler)

		default:
			processList(message: message, replyHandler: replyHandler)
		}
	}

	private func processList(message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {

		var result = [String : Any]()

		switch(S(message["list"] as? String)) {

		case "overview":
			buildOverview { [weak self] overview in
				result["result"] = overview
				self?.reportSuccess(result: result, replyHandler: replyHandler)
			}

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

	private func reportFailure(reason: String, result: [String : Any], replyHandler: ([String : Any]) -> Void) {
		var r = result
		r["error"] = true
		r["status"] = reason
		replyHandler(r)
	}

	private func reportSuccess(result: [String : Any], replyHandler: ([String : Any]) -> Void) {
		var r = result
		r["status"] = "Success"
		replyHandler(r)
	}

	////////////////////////////

	private func buildItemList(type: String, sectionIndex: Int64, from: Int, apiServerUri: String, group: String, count: Int, onlyUnread: Bool, replyHandler: @escaping ([String : Any]) -> Void) {

		let showLabels = Settings.showLabels
		let entity: ListableItem.Type
		if type == "prs" {
			entity = PullRequest.self
		} else {
			entity = Issue.self
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

		let tempMoc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		tempMoc.undoManager = nil
		tempMoc.persistentStoreCoordinator = DataManager.main.persistentStoreCoordinator
		tempMoc.perform { [weak self] in
			let items = try! tempMoc.fetch(f).map { self?.baseDataForItem(item: $0, showLabels: showLabels) }
			let compressedData = (try? NSKeyedArchiver.archivedData(withRootObject: items, requiringSecureCoding: false).data(operation: .compress)) ?? Data()
			replyHandler(["result" : compressedData])
		}
	}

	private func baseDataForItem(item: ListableItem, showLabels: Bool) -> [String : Any] {

		let font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
		let smallFont = UIFont.systemFont(ofSize: UIFont.systemFontSize-4)

		var itemData: [String : Any] = [
			"commentCount": item.totalComments,
			"unreadCount": item.unreadComments,
			"localId": item.objectID.uriRepresentation().absoluteString,
			"title" : item.title(with: font, labelFont: font, titleColor: .white, darkMode: true),
			"subtitle" : item.subtitle(with: smallFont, lightColor: .lightGray, darkColor: .gray),
			]

		if showLabels {
			itemData["labels"] = labelsForItem(item: item)
		}
		if let item = item as? PullRequest, item.shouldShowStatuses {
			itemData["statuses"] = statusLinesForPr(pr: item)
		}
		return itemData
	}

	private func labelsForItem(item: ListableItem) -> [[String : Any]] {
		var labels = [[String : Any]]()
		for l in item.labels {
			labels.append([
				"color": l.colorForDisplay,
				"text": S(l.name)
				])
		}
		return labels
	}

	private func statusLinesForPr(pr: PullRequest) -> [[String : Any]] {
		var statusLines = [[String : Any]]()
		for status in pr.displayedStatuses {
			statusLines.append([
				"color": status.colorForDarkDisplay,
				"text": S(status.descriptionText)
				])
		}
		return statusLines
	}

	/////////////////////////////

	private func buildItemDetail(localId: String) -> Data? {
		if let oid = DataManager.id(for: localId), let item = existingObject(with: oid) as? ListableItem {
			var result = baseDataForItem(item: item, showLabels: Settings.showLabels)
			result["description"] = item.body
			result["comments"] = commentsForItem(item: item)

            return try? NSKeyedArchiver.archivedData(withRootObject: result, requiringSecureCoding: false).data(operation: .compress)
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

	private func buildOverview(completion: @escaping ([String:Any])->Void) {

		//DLog("Building remote overview")

		let allTabSets = popupManager.masterController.allTabSets

		let tempMoc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		tempMoc.undoManager = nil
		tempMoc.persistentStoreCoordinator = DataManager.main.persistentStoreCoordinator
		tempMoc.perform {

			var views = [[String : Any]]()

			var totalUnreadPrCount = 0
			var totalUnreadIssueCount = 0

			for tabSet in allTabSets {

				let c = tabSet.viewCriterion

				let myPrs = WatchManager.counts(for: PullRequest.self, in: .mine, criterion: c, moc: tempMoc)
				let participatedPrs = WatchManager.counts(for: PullRequest.self, in: .participated, criterion: c, moc: tempMoc)
				let mentionedPrs = WatchManager.counts(for: PullRequest.self, in: .mentioned, criterion: c, moc: tempMoc)
				let mergedPrs = WatchManager.counts(for: PullRequest.self, in: .merged, criterion: c, moc: tempMoc)
				let closedPrs = WatchManager.counts(for: PullRequest.self, in: .closed, criterion: c, moc: tempMoc)
				let otherPrs = WatchManager.counts(for: PullRequest.self, in: .all, criterion: c, moc: tempMoc)
				let snoozedPrs = WatchManager.counts(for: PullRequest.self, in: .snoozed, criterion: c, moc: tempMoc)
				let totalPrs = [ myPrs, participatedPrs, mentionedPrs, mergedPrs, closedPrs, otherPrs, snoozedPrs ].reduce(0, { $0 + $1["total"]! })

				let totalOpenPrs = WatchManager.countOpenAndVisible(of: PullRequest.self, criterion: c, moc: tempMoc)
				let unreadPrCount = PullRequest.badgeCount(in: tempMoc, criterion: c)
				totalUnreadPrCount += unreadPrCount

				let myIssues = WatchManager.counts(for: Issue.self, in: .mine, criterion: c, moc: tempMoc)
				let participatedIssues = WatchManager.counts(for: Issue.self, in: .participated, criterion: c, moc: tempMoc)
				let mentionedIssues = WatchManager.counts(for: Issue.self, in: .mentioned, criterion: c, moc: tempMoc)
				let closedIssues = WatchManager.counts(for: Issue.self, in: .closed, criterion: c, moc: tempMoc)
				let otherIssues = WatchManager.counts(for: Issue.self, in: .all, criterion: c, moc: tempMoc)
				let snoozedIssues = WatchManager.counts(for: Issue.self, in: .snoozed, criterion: c, moc: tempMoc)
				let totalIssues = [ myIssues, participatedIssues, mentionedIssues, closedIssues, otherIssues, snoozedIssues ].reduce(0, { $0 + $1["total"]! })

				let totalOpenIssues = WatchManager.countOpenAndVisible(of: Issue.self, criterion: c, moc: tempMoc)
				let unreadIssueCount = Issue.badgeCount(in: tempMoc, criterion: c)
				totalUnreadIssueCount += unreadIssueCount

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

			DispatchQueue.main.async {
				completion([
					"views": views,
					"preferIssues": Settings.preferIssuesInWatch,
					"lastUpdated": Settings.lastSuccessfulRefresh ?? .distantPast
					])
				UIApplication.shared.applicationIconBadgeNumber = totalUnreadPrCount + totalUnreadIssueCount
			}

			DLog("Remote overview updated")
		}
	}

	private static func counts<T: ListableItem>(for type: T.Type, in section: Section, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> [String : Int] {
		return ["total": countItems(of: type, in: section, criterion: criterion, moc: moc),
		        "unread": badgeCount(for: type, in: section, criterion: criterion, moc: moc)]
	}

	private static func countallItems<T: ListableItem>(of type: T.Type, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.includesSubentities = false
		let p = Settings.hideUncommentedItems
			? NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, type.includeInUnreadPredicate])
			: Section.nonZeroPredicate
		DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
		return try! moc.count(for: f)
	}

	private static func countItems<T: ListableItem>(of type: T.Type, in section: Section, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.includesSubentities = false
		let p = Settings.hideUncommentedItems
			? NSCompoundPredicate(type: .and, subpredicates: [section.matchingPredicate, type.includeInUnreadPredicate])
			: section.matchingPredicate
		DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
		return try! moc.count(for: f)
	}

	private static func badgeCount<T: ListableItem>(for type: T.Type, in section: Section, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.includesSubentities = false
		let p = NSCompoundPredicate(type: .and, subpredicates: [section.matchingPredicate, type.includeInUnreadPredicate])
		DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
		return ListableItem.badgeCount(from: f, in: moc)
	}

	private static func countOpenAndVisible<T: ListableItem>(of type: T.Type, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> Int {
		let f = NSFetchRequest<T>(entityName: String(describing: type))
		f.includesSubentities = false
		let p = Settings.hideUncommentedItems
			? NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, ItemCondition.open.matchingPredicate, type.includeInUnreadPredicate])
			: NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, ItemCondition.open.matchingPredicate])
		DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
		return try! moc.count(for: f)
	}

}
