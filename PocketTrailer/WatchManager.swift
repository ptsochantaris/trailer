import CoreData
import UIKit
import WatchConnectivity

final class WatchManager: NSObject, WCSessionDelegate {
    private var session: WCSession?

    override init() {
        super.init()
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { [weak self] in
                _ = await self?.buildOverview()
            }
        }
    }

    func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}

    func sessionDidDeactivate(_: WCSession) {}

    func sessionDidBecomeInactive(_: WCSession) {}

    private var overviewPath: URL {
        DataManager.dataFilesDirectory.appendingPathComponent("overview.plist")
    }

    func session(_: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task {
            let reply = await handle(message: message)
            replyHandler(reply)
        }
    }

    func updateContext() {
        if let session = session, session.isReachable {
            session.sendMessage(["newInfoAvailable": true], replyHandler: nil)
        }
    }

    @MainActor
    private func handle(message: [String: Any]) async -> [String: Any] {
        switch S(message["command"] as? String) {
        case "refresh":
            let status = app.startRefresh()
            switch status {
            case .started:
                return reportSuccess(result: [:])
            case .noNetwork:
                return reportFailure(reason: "Can't refresh, check your Internet connection.", result: [:])
            case .alreadyRefreshing:
                return reportFailure(reason: "Already refreshing, please wait.", result: [:])
            case .noConfiguredServers:
                return reportFailure(reason: "Can't refresh, there are no configured servers.", result: [:])
            }

        case "overview":
            return await processList(message: message)

        case "openItem":
            if let itemId = message["localId"] as? String {
                popupManager.masterController.highightItemWithUriPath(uriPath: itemId)
            }
            return await processList(message: message)

        case "opencomment":
            if let itemId = message["id"] as? String {
                popupManager.masterController.openCommentWithId(cId: itemId)
            }
            return await processList(message: message)

        case "clearAllMerged":
            app.clearAllMerged()
            return await processList(message: message)

        case "clearAllClosed":
            app.clearAllClosed()
            return await processList(message: message)

        case "markEverythingRead":
            app.markEverythingRead()
            return await processList(message: message)

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
            return await processList(message: message)

        default:
            return await processList(message: message)
        }
    }

    private func processList(message: [String: Any]) async -> [String: Any] {
        var result = [String: Any]()

        switch S(message["list"] as? String) {
        case "overview":
            result["result"] = await buildOverview()
            return reportSuccess(result: result)

        case "item_list":
            return await buildItemList(
                type: message["type"] as! String,
                sectionIndex: message["sectionIndex"] as! Int64,
                from: message["from"] as! Int,
                apiServerUri: message["apiUri"] as! String,
                group: message["group"] as! String,
                count: message["count"] as! Int,
                onlyUnread: message["onlyUnread"] as! Bool
            )

        case "item_detail":
            if let lid = message["localId"] as? String, let details = buildItemDetail(localId: lid) {
                result["result"] = details
                return reportSuccess(result: result)
            } else {
                return reportFailure(reason: "Item Not Found", result: result)
            }

        default:
            return reportSuccess(result: result)
        }
    }

    private func reportFailure(reason: String, result: [String: Any]) -> [String: Any] {
        var r = result
        r["error"] = true
        r["status"] = reason
        return r
    }

    private func reportSuccess(result: [String: Any]) -> [String: Any] {
        var r = result
        r["status"] = "Success"
        return r
    }

    ////////////////////////////

    private func buildItemList(type: String, sectionIndex: Int64, from: Int, apiServerUri: String, group: String, count: Int, onlyUnread: Bool) async -> [String: Any] {
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
        return await tempMoc.perform { [weak self] in
            guard let self = self else { return [:] }
            let items = try! tempMoc.fetch(f).map { self.baseDataForItem(item: $0, showLabels: showLabels) }
            let compressedData = (try? NSKeyedArchiver.archivedData(withRootObject: items, requiringSecureCoding: false).data(operation: .compress)) ?? Data()
            return ["result": compressedData]
        }
    }

    private func baseDataForItem(item: ListableItem, showLabels: Bool) -> [String: Any] {
        let font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
        let smallFont = UIFont.systemFont(ofSize: UIFont.systemFontSize - 4)

        var itemData: [String: Any] = [
            "commentCount": item.totalComments,
            "unreadCount": item.unreadComments,
            "localId": item.objectID.uriRepresentation().absoluteString,
            "title": item.title(with: font, labelFont: font, titleColor: .white, numberColor: .gray),
            "subtitle": item.subtitle(with: smallFont, lightColor: .lightGray, darkColor: .gray, separator: "\n"),
            "labels": item.labelsAttributedString(labelFont: smallFont) ?? emptyAttributedString,
            "reviews": (item as? PullRequest)?.reviewsAttributedString(labelFont: smallFont) ?? emptyAttributedString
        ]

        if showLabels {
            itemData["labels"] = labelsForItem(item: item)
        }
        if let item = item as? PullRequest, item.section.shouldListStatuses {
            itemData["statuses"] = statusLinesForPr(pr: item)
        }
        return itemData
    }

    private func labelsForItem(item: ListableItem) -> [[String: Any]] {
        var labels = [[String: Any]]()
        for l in item.labels {
            labels.append([
                "color": l.colorForDisplay,
                "text": S(l.name)
            ])
        }
        return labels
    }

    private func statusLinesForPr(pr: PullRequest) -> [[String: Any]] {
        var statusLines = [[String: Any]]()
        for status in pr.displayedStatuses {
            statusLines.append([
                "color": status.colorForDisplay,
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

    private func commentsForItem(item: ListableItem) -> [[String: Any]] {
        var comments = [[String: Any]]()
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

    @MainActor
    private func buildOverview() async -> [String: Any] {
        let allViewCriteria = popupManager.masterController.allTabSets.map(\.viewCriterion)

        let tempMoc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        tempMoc.undoManager = nil
        tempMoc.parent = DataManager.main

        return await tempMoc.perform {
            var views = [[String: Any]]()
            var totalUnreadPrCount = 0
            var totalUnreadIssueCount = 0

            for c in allViewCriteria {
                let myPrs = WatchManager.counts(for: PullRequest.self, in: .mine, criterion: c, moc: tempMoc)
                let participatedPrs = WatchManager.counts(for: PullRequest.self, in: .participated, criterion: c, moc: tempMoc)
                let mentionedPrs = WatchManager.counts(for: PullRequest.self, in: .mentioned, criterion: c, moc: tempMoc)
                let mergedPrs = WatchManager.counts(for: PullRequest.self, in: .merged, criterion: c, moc: tempMoc)
                let closedPrs = WatchManager.counts(for: PullRequest.self, in: .closed, criterion: c, moc: tempMoc)
                let otherPrs = WatchManager.counts(for: PullRequest.self, in: .all, criterion: c, moc: tempMoc)
                let snoozedPrs = WatchManager.counts(for: PullRequest.self, in: .snoozed, criterion: c, moc: tempMoc)
                let totalPrs = [myPrs, participatedPrs, mentionedPrs, mergedPrs, closedPrs, otherPrs, snoozedPrs].reduce(0) { $0 + $1["total"]! }

                let totalOpenPrs = WatchManager.countOpenAndVisible(of: PullRequest.self, criterion: c, moc: tempMoc)
                let unreadPrCount = PullRequest.badgeCount(in: tempMoc, criterion: c)
                totalUnreadPrCount += unreadPrCount

                let myIssues = WatchManager.counts(for: Issue.self, in: .mine, criterion: c, moc: tempMoc)
                let participatedIssues = WatchManager.counts(for: Issue.self, in: .participated, criterion: c, moc: tempMoc)
                let mentionedIssues = WatchManager.counts(for: Issue.self, in: .mentioned, criterion: c, moc: tempMoc)
                let closedIssues = WatchManager.counts(for: Issue.self, in: .closed, criterion: c, moc: tempMoc)
                let otherIssues = WatchManager.counts(for: Issue.self, in: .all, criterion: c, moc: tempMoc)
                let snoozedIssues = WatchManager.counts(for: Issue.self, in: .snoozed, criterion: c, moc: tempMoc)
                let totalIssues = [myIssues, participatedIssues, mentionedIssues, closedIssues, otherIssues, snoozedIssues].reduce(0) { $0 + $1["total"]! }

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
                    ]
                ])
            }
            let badgeCount = totalUnreadPrCount + totalUnreadIssueCount
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
            }
            return [
                "views": views,
                "preferIssues": Settings.preferIssuesInWatch,
                "lastUpdated": Settings.lastSuccessfulRefresh ?? .distantPast
            ]
        }
    }

    private static func counts<T: ListableItem>(for type: T.Type, in section: Section, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> [String: Int] {
        ["total": countItems(of: type, in: section, criterion: criterion, moc: moc),
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
