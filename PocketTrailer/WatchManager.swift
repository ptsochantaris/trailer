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

    func session(_: WCSession, didReceiveMessage message: JSON, replyHandler: @escaping (JSON) -> Void) {
        Task {
            let reply = await handle(message: message)
            replyHandler(reply)
        }
    }

    func updateContext() {
        if let session, session.isReachable {
            session.sendMessage(["newInfoAvailable": true], replyHandler: nil)
        }
    }

    @MainActor
    private func handle(message: JSON) async -> JSON {
        let settings = Settings.cache

        switch (message["command"] as? String).orEmpty {
        case "refresh":
            let status = await app.startRefresh()
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
            return await processList(message: message, settings: settings)

        case "openItem":
            if let itemId = message["localId"] as? String {
                popupManager.masterController.highightItemWithUriPath(uriPath: itemId)
            }
            return await processList(message: message, settings: settings)

        case "opencomment":
            if let itemId = message["id"] as? String {
                popupManager.masterController.openCommentWithId(cId: itemId)
            }
            return await processList(message: message, settings: settings)

        case "clearAllMerged":
            app.clearAllMerged()
            return await processList(message: message, settings: settings)

        case "clearAllClosed":
            app.clearAllClosed()
            return await processList(message: message, settings: settings)

        case "markEverythingRead":
            app.markEverythingRead(settings: settings)
            return await processList(message: message, settings: settings)

        case "markItemsRead":
            if let
                uri = message["localId"] as? String,
                let oid = DataManager.id(for: uri),
                let dataItem = try? DataManager.main.existingObject(with: oid) as? ListableItem,
                dataItem.hasUnreadCommentsOrAlert {
                dataItem.catchUpWithComments(settings: settings)

            } else if let uris = message["itemUris"] as? [String] {
                for uri in uris {
                    if let oid = DataManager.id(for: uri),
                       let dataItem = try? DataManager.main.existingObject(with: oid) as? ListableItem,
                       dataItem.hasUnreadCommentsOrAlert {
                        dataItem.catchUpWithComments(settings: settings)
                    }
                }
            }
            return await processList(message: message, settings: settings)

        default:
            return await processList(message: message, settings: settings)
        }
    }

    @MainActor
    private func processList(message: JSON, settings: Settings.Cache) async -> JSON {
        var result = JSON()

        switch (message["list"] as? String).orEmpty {
        case "overview":
            result["result"] = await buildOverview()
            return reportSuccess(result: result)

        case "item_list":
            return await buildItemList(
                type: message["type"] as! String,
                sectionIndex: message["sectionIndex"] as! Int,
                from: message["from"] as! Int,
                apiServerUri: message["apiUri"] as! String,
                group: message["group"] as! String,
                count: message["count"] as! Int,
                onlyUnread: message["onlyUnread"] as! Bool,
                settings: settings
            )

        case "item_detail":
            if let lid = message["localId"] as? String, let details = buildItemDetail(localId: lid, settings: settings) {
                result["result"] = details
                return reportSuccess(result: result)
            } else {
                return reportFailure(reason: "Item Not Found", result: result)
            }

        default:
            return reportSuccess(result: result)
        }
    }

    private func reportFailure(reason: String, result: JSON) -> JSON {
        var r = result
        r["error"] = true
        r["status"] = reason
        return r
    }

    private func reportSuccess(result: JSON) -> JSON {
        var r = result
        r["status"] = "Success"
        return r
    }

    ////////////////////////////

    @MainActor
    private func buildItemList(type: String, sectionIndex: Int, from: Int, apiServerUri: String, group: String, count: Int, onlyUnread: Bool, settings: Settings.Cache) async -> JSON {
        let showLabels = Settings.showLabels
        let entity: ListableItem.Type
        if type == "prs" {
            entity = PullRequest.self
        } else {
            entity = Issue.self
        }

        let f: NSFetchRequest<ListableItem>
        if !apiServerUri.isEmpty, let aid = DataManager.id(for: apiServerUri) {
            let criterion = GroupingCriterion.server(aid)
            f = ListableItem.requestForItems(of: entity, withFilter: nil, sectionIndex: sectionIndex, criterion: criterion, onlyUnread: onlyUnread, settings: settings)
        } else if !group.isEmpty {
            let criterion = GroupingCriterion.group(group)
            f = ListableItem.requestForItems(of: entity, withFilter: nil, sectionIndex: sectionIndex, criterion: criterion, onlyUnread: onlyUnread, settings: settings)
        } else {
            f = ListableItem.requestForItems(of: entity, withFilter: nil, sectionIndex: sectionIndex, onlyUnread: onlyUnread, settings: settings)
        }

        f.fetchOffset = from
        f.fetchLimit = count

        let items = try! DataManager.main.fetch(f).map { self.baseDataForItem(item: $0, showLabels: showLabels, settings: settings) }
        let compressedData = (try? NSKeyedArchiver.archivedData(withRootObject: items, requiringSecureCoding: false).data(operation: .compress)) ?? Data()
        return ["result": compressedData]
    }

    @MainActor
    private func baseDataForItem(item: ListableItem, showLabels: Bool, settings: Settings.Cache) -> JSON {
        let font = UIFont.systemFont(ofSize: UIFont.systemFontSize)
        let smallFont = UIFont.systemFont(ofSize: UIFont.systemFontSize - 4)

        var itemData: JSON = [
            "commentCount": item.totalComments,
            "unreadCount": item.unreadComments,
            "localId": item.objectID.uriRepresentation().absoluteString,
            "title": item.title(with: font, labelFont: font, titleColor: .white, numberColor: .gray, settings: settings),
            "subtitle": item.subtitle(with: smallFont, lightColor: .lightGray, darkColor: .gray, separator: "\n", settings: settings),
            "labels": item.labelsAttributedString(labelFont: smallFont, settings: settings) ?? emptyAttributedString,
            "reviews": item.asPr?.reviewsAttributedString(labelFont: smallFont, settings: settings) ?? emptyAttributedString
        ]

        if showLabels {
            itemData["labels"] = labelsForItem(item: item)
        }
        if let item = item.asPr, item.section.shouldListStatuses(settings: settings) {
            itemData["statuses"] = statusLinesForPr(pr: item, settings: settings)
        }
        return itemData
    }

    @MainActor
    private func labelsForItem(item: ListableItem) -> [JSON] {
        var labels = [JSON]()
        for l in item.labels {
            labels.append([
                "color": l.colorForDisplay,
                "text": l.name.orEmpty
            ])
        }
        return labels
    }

    @MainActor
    private func statusLinesForPr(pr: PullRequest, settings: Settings.Cache) -> [JSON] {
        var statusLines = [JSON]()
        for status in pr.displayedStatusLines(settings: settings) {
            statusLines.append([
                "color": status.colorForDisplay,
                "text": status.descriptionText.orEmpty
            ])
        }
        return statusLines
    }

    /////////////////////////////

    @MainActor
    private func buildItemDetail(localId: String, settings: Settings.Cache) -> Data? {
        if let oid = DataManager.id(for: localId), let item = try? DataManager.main.existingObject(with: oid) as? ListableItem {
            var result = baseDataForItem(item: item, showLabels: Settings.showLabels, settings: settings)
            result["description"] = item.body
            result["comments"] = commentsForItem(item: item)

            return try? NSKeyedArchiver.archivedData(withRootObject: result, requiringSecureCoding: false).data(operation: .compress)
        }
        return nil
    }

    @MainActor
    private func commentsForItem(item: ListableItem) -> [JSON] {
        var comments = [JSON]()
        for comment in item.sortedComments(using: .orderedDescending) {
            comments.append([
                "user": comment.userName.orEmpty,
                "date": comment.createdAt ?? .distantPast,
                "text": comment.body.orEmpty,
                "mine": comment.createdByMe
            ])
        }
        return comments
    }

    //////////////////////////////

    @MainActor
    private func buildOverview() async -> JSON {
        let allViewCriteria = popupManager.masterController.allTabSets.map(\.viewCriterion)

        return await DataManager.runInChild(of: DataManager.main) { tempMoc in
            var views = [JSON]()
            var totalUnreadPrCount = 0
            var totalUnreadIssueCount = 0

            let settings = Settings.cache

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
                let unreadPrCount = PullRequest.badgeCount(in: tempMoc, criterion: c, settings: settings)
                totalUnreadPrCount += unreadPrCount

                let myIssues = WatchManager.counts(for: Issue.self, in: .mine, criterion: c, moc: tempMoc)
                let participatedIssues = WatchManager.counts(for: Issue.self, in: .participated, criterion: c, moc: tempMoc)
                let mentionedIssues = WatchManager.counts(for: Issue.self, in: .mentioned, criterion: c, moc: tempMoc)
                let closedIssues = WatchManager.counts(for: Issue.self, in: .closed, criterion: c, moc: tempMoc)
                let otherIssues = WatchManager.counts(for: Issue.self, in: .all, criterion: c, moc: tempMoc)
                let snoozedIssues = WatchManager.counts(for: Issue.self, in: .snoozed, criterion: c, moc: tempMoc)
                let totalIssues = [myIssues, participatedIssues, mentionedIssues, closedIssues, otherIssues, snoozedIssues].reduce(0) { $0 + $1["total"]! }

                let totalOpenIssues = WatchManager.countOpenAndVisible(of: Issue.self, criterion: c, moc: tempMoc)
                let unreadIssueCount = Issue.badgeCount(in: tempMoc, criterion: c, settings: settings)
                totalUnreadIssueCount += unreadIssueCount

                let prList = [
                    "mine": myPrs, "participated": participatedPrs, "mentioned": mentionedPrs,
                    "merged": mergedPrs, "closed": closedPrs, "other": otherPrs, "snoozed": snoozedPrs,
                    "total": totalPrs, "total_open": totalOpenPrs, "unread": unreadPrCount,
                    "error": totalPrs == 0 ? PullRequest.reasonForEmpty(with: nil, criterion: c).string : ""
                ] as JSON

                let issueList = [
                    "mine": myIssues, "participated": participatedIssues, "mentioned": mentionedIssues,
                    "closed": closedIssues, "other": otherIssues, "snoozed": snoozedIssues,
                    "total": totalIssues, "total_open": totalOpenIssues, "unread": unreadIssueCount,
                    "error": totalIssues == 0 ? Issue.reasonForEmpty(with: nil, criterion: c).string : ""
                ] as JSON

                views.append([
                    "title": (c?.label).orEmpty,
                    "apiUri": (c?.apiServerId?.uriRepresentation().absoluteString).orEmpty,
                    "prs": prList,
                    "issues": issueList
                ])
            }
            let badgeCount = totalUnreadPrCount + totalUnreadIssueCount
            Task { @MainActor in
                UIApplication.shared.applicationIconBadgeNumber = badgeCount
            }
            return [
                "views": views,
                "preferIssues": Settings.preferIssuesInWatch,
                "lastUpdated": Settings.lastSuccessfulRefresh ?? .distantPast
            ]
        }
    }

    @MainActor
    private static func counts(for type: (some ListableItem).Type, in section: Section, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> [String: Int] {
        ["total": countItems(of: type, in: section, criterion: criterion, moc: moc),
         "unread": badgeCount(for: type, in: section, criterion: criterion, moc: moc)]
    }

    @MainActor
    private static func countallItems<T: ListableItem>(of type: T.Type, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<T>(entityName: type.typeName)
        f.includesSubentities = false
        let p = Settings.hideUncommentedItems
            ? NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, type.includeInUnreadPredicate])
            : Section.nonZeroPredicate
        DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
        return try! moc.count(for: f)
    }

    @MainActor
    private static func countItems<T: ListableItem>(of type: T.Type, in section: Section, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<T>(entityName: type.typeName)
        f.includesSubentities = false
        let p = Settings.hideUncommentedItems
            ? NSCompoundPredicate(type: .and, subpredicates: [section.matchingPredicate, type.includeInUnreadPredicate])
            : section.matchingPredicate
        DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
        return try! moc.count(for: f)
    }

    @MainActor
    private static func badgeCount<T: ListableItem>(for type: T.Type, in section: Section, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<T>(entityName: type.typeName)
        f.includesSubentities = false
        let p = NSCompoundPredicate(type: .and, subpredicates: [section.matchingPredicate, type.includeInUnreadPredicate])
        DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
        return ListableItem.badgeCount(from: f, in: moc)
    }

    @MainActor
    private static func countOpenAndVisible<T: ListableItem>(of type: T.Type, criterion: GroupingCriterion?, moc: NSManagedObjectContext) -> Int {
        let f = NSFetchRequest<T>(entityName: type.typeName)
        f.includesSubentities = false
        let p = Settings.hideUncommentedItems
            ? NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, ItemCondition.open.matchingPredicate, type.includeInUnreadPredicate])
            : NSCompoundPredicate(type: .and, subpredicates: [Section.nonZeroPredicate, ItemCondition.open.matchingPredicate])
        DataItem.add(criterion: criterion, toFetchRequest: f, originalPredicate: p, in: moc)
        return try! moc.count(for: f)
    }
}
