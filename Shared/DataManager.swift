import CoreData
import CoreSpotlight
import Lista
import Maintini
import TrailerQL

extension NSManagedObjectContext {
    func buildChildContext() -> NSManagedObjectContext {
        let child = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        child.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        child.undoManager = nil
        child.parent = self
        return child
    }
}

@MainActor
enum DataManager {
    static var postMigrationRepoPrPolicy: RepoDisplayPolicy?
    static var postMigrationRepoIssuePolicy: RepoDisplayPolicy?
    static var postMigrationSnoozeWakeOnComment: Bool?
    static var postMigrationSnoozeWakeOnMention: Bool?
    static var postMigrationSnoozeWakeOnStatusUpdate: Bool?

    static var main: NSManagedObjectContext = {
        let m = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        m.undoManager = nil
        m.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        m.persistentStoreCoordinator = persistentStoreCoordinator
        return m
    }()

    private static var migrated = false

    static func checkMigration() {
        guard let count = persistentStoreCoordinator?.persistentStores.count, count > 0 else { return }

        if Settings.lastRunVersion != versionString {
            Task {
                await Logging.shared.log("VERSION UPDATE MAINTENANCE NEEDED")
            }
            ApiServer.ensureAtLeastGithub(in: main)
            ApiServer.resetSyncOfEverything()
            Settings.lastRunVersion = versionString
            migrated = true
        }
        ApiServer.ensureAtLeastGithub(in: main)
    }

    private static func processNotificationsForItems(of type: (some ListableItem).Type, newNotification: NotificationType, reopenedNotification: NotificationType, assignmentNotification: NotificationType, settings: Settings.Cache) async {
        await runInChild(of: main) { child in
            for i in type.allItems(in: child) {
                if i.stateChanged != 0 {
                    switch i.stateChanged {
                    case ListableItem.StateChange.reopened.rawValue:
                        NotificationQueue.add(type: reopenedNotification, for: i)
                        i.announced = true

                    case ListableItem.StateChange.merged.rawValue:
                        i.handleMerging(settings: settings)

                    case ListableItem.StateChange.closed.rawValue:
                        i.handleClosing(settings: settings)

                    default: break
                    }
                    i.stateChanged = 0

                } else if !i.createdByMe, i.isVisibleOnMenu {
                    if i.isNewAssignment {
                        NotificationQueue.add(type: assignmentNotification, for: i)
                        i.announced = true
                        i.isNewAssignment = false
                    } else if !i.announced {
                        NotificationQueue.add(type: newNotification, for: i)
                        i.announced = true
                    }
                }
            }
        }
    }

    private static func processCommentAndReviewNotifications(settings: Settings.Cache) async {
        await runInChild(of: main) { child in
            for c in PRComment.newItems(in: child) {
                c.processNotifications(settings: settings)
                c.postSyncAction = PostSyncAction.doNothing.rawValue
            }

            for r in Review.newOrUpdatedItems(in: child) {
                r.processNotifications(settings: settings)
                r.postSyncAction = PostSyncAction.doNothing.rawValue
            }
        }
    }

    private static func processStatusNotifications(settings: Settings.Cache) async {
        await runInChild(of: main) { child in
            let latestStatuses = PRStatus.newItems(in: child)
            var coveredPrs = Set<NSManagedObjectID>()
            if settings.notifyOnStatusUpdates {
                for pr in latestStatuses.map(\.pullRequest) where pr.shouldAnnounceStatus(settings: settings) && !coveredPrs.contains(pr.objectID) {
                    coveredPrs.insert(pr.objectID)
                    if let s = pr.displayedStatusLines(settings: settings).first {
                        let displayText = s.descriptionText
                        if pr.lastStatusNotified != displayText, pr.postSyncAction != PostSyncAction.isNew.rawValue {
                            NotificationQueue.add(type: .newStatus, for: s)
                            pr.lastStatusNotified = displayText
                        }
                    } else {
                        pr.lastStatusNotified = nil
                    }
                }
                coveredPrs.removeAll()
            }

            for pr in latestStatuses.map(\.pullRequest) where pr.isSnoozing && pr.shouldWakeOnStatusChange && !coveredPrs.contains(pr.objectID) {
                coveredPrs.insert(pr.objectID)
                let prNodeId = pr.nodeId ?? "<no ID>"
                Task {
                    await Logging.shared.log("Waking up snoozed PR ID \(prNodeId) because of a status update")
                }
                pr.wakeUp(settings: settings)
            }

            for s in latestStatuses {
                s.postSyncAction = PostSyncAction.doNothing.rawValue
            }
        }
    }

    static func runInChild<T>(of moc: NSManagedObjectContext, block: @escaping (NSManagedObjectContext) -> T) async -> T {
        await withCheckedContinuation { continuation in
            let child = moc.buildChildContext()
            child.perform {
                let res = block(child)
                if child.hasChanges {
                    try? child.save()
                }
                continuation.resume(returning: res)
            }
        }
    }

    static func sendNotificationsIndexAndSave(settings: Settings.Cache) async {
        await saveDB() // get IDs

        await postProcessAllItems(in: main, settings: settings)

        await processNotificationsForItems(of: PullRequest.self, newNotification: .newPr, reopenedNotification: .prReopened, assignmentNotification: .newPrAssigned, settings: settings)

        await processNotificationsForItems(of: Issue.self, newNotification: .newIssue, reopenedNotification: .issueReopened, assignmentNotification: .newIssueAssigned, settings: settings)

        await processCommentAndReviewNotifications(settings: settings)

        await processStatusNotifications(settings: settings)

        await runInChild(of: main) { child in
            let nothing = PostSyncAction.doNothing.rawValue

            for r in Reaction.newOrUpdatedItems(in: child) {
                r.checkNotifications(settings: settings)
                r.postSyncAction = nothing
            }

            for r in Review.newOrUpdatedItems(in: child) {
                r.postSyncAction = nothing
            }

            for r in PRComment.newOrUpdatedItems(in: child) {
                r.postSyncAction = nothing
            }

            removeUntouchedMergedOrClosedItems(in: child)

            for p in PullRequest.newOrUpdatedItems(in: child) {
                p.postSyncAction = nothing
            }

            for i in Issue.newOrUpdatedItems(in: child) {
                i.postSyncAction = nothing
            }
        }

        await saveDB() // commit all changes

        NotificationQueue.commit()

        preferencesDirty = false
    }

    private static func removeUntouchedMergedOrClosedItems(in child: NSManagedObjectContext) {
        let mergeExpiration = TimeInterval(Settings.autoRemoveMergedItems)
        if mergeExpiration > 0 {
            let cutoff = Date(timeIntervalSinceNow: -24 * 3600 * mergeExpiration)
            for untouched in PullRequest.untouchedMergedItems(in: child) {
                if let updatedAt = untouched.updatedAt, updatedAt < cutoff {
                    let nodeId = untouched.nodeId
                    Task {
                        await Logging.shared.log("Deleting closed PR which hasn't been updated: \(nodeId.orEmpty)")
                    }
                    child.delete(untouched)
                }
            }
        }

        let closeExpiration = TimeInterval(Settings.autoRemoveClosedItems)
        if closeExpiration > 0 {
            let cutoff = Date(timeIntervalSinceNow: -24 * 3600 * closeExpiration)
            for untouched in PullRequest.untouchedClosedItems(in: child) {
                if let updatedAt = untouched.updatedAt, updatedAt < cutoff {
                    let nodeId = untouched.nodeId
                    Task {
                        await Logging.shared.log("Deleting closed PR which hasn't been updated: \(nodeId.orEmpty)")
                    }
                    child.delete(untouched)
                }
            }
            for untouched in Issue.untouchedClosedItems(in: child) {
                if let updatedAt = untouched.updatedAt, updatedAt < cutoff {
                    let nodeId = untouched.nodeId
                    Task {
                        await Logging.shared.log("Deleting closed issue which hasn't been updated: \(nodeId.orEmpty)")
                    }
                    child.delete(untouched)
                }
            }
        }
    }

    private static func updateIndexingFromScratch(settings: Settings.Cache) async {
        guard CSSearchableIndex.isIndexingAvailable() else {
            return
        }

        await Logging.shared.log("Re-indexing spotlight")

        let itemsToIndex = Lista<CSSearchableItem>()
        let itemsToRemove = Lista<String>()

        for pr in PullRequest.allItems(in: main) {
            switch await pr.handleSpotlight(settings: settings) {
            case let .needsIndexing(item):
                itemsToIndex.append(item)
            case let .needsRemoval(uri):
                itemsToRemove.append(uri)
            }
        }

        for issue in Issue.allItems(in: main) {
            switch await issue.handleSpotlight(settings: settings) {
            case let .needsIndexing(item):
                itemsToIndex.append(item)
            case let .needsRemoval(uri):
                itemsToRemove.append(uri)
            }
        }

        let index = CSSearchableIndex.default()

        do {
            await Logging.shared.log("Clearing spotlight indexes")
            try await index.deleteAllSearchableItems()
        } catch {
            await Logging.shared.log("Error clearing existing spotlight index: \(error.localizedDescription)")
        }

        await Logging.shared.log("Comitting spotlight indexes")
        if itemsToRemove.count > 0 {
            await Logging.shared.log("De-indexing \(itemsToRemove.count) items...")
            try? await index.deleteSearchableItems(withIdentifiers: Array(itemsToRemove))
        }
        if itemsToIndex.count > 0 {
            await Logging.shared.log("Indexing \(itemsToIndex.count) items...")
            try? await index.indexSearchableItems(Array(itemsToIndex))
        }
        await Logging.shared.log("Committed spotlight changes")
    }

    static func saveDB() async {
        Maintini.startMaintaining()
        defer {
            Maintini.endMaintaining()
        }

        let settings = Settings.cache

        guard main.hasChanges else {
            await Logging.shared.log("No DB changes")
            if migrated {
                migrated = false
                Task {
                    await Maintini.maintain {
                        await updateIndexingFromScratch(settings: settings)
                    }
                }
            }
            return
        }

        let newObjects = main.insertedObjects.union(main.updatedObjects)
        let deletedObjects = main.deletedObjects

        await Logging.shared.log("Saving DB")
        do {
            try main.save()
        } catch {
            await Logging.shared.log("Error while saving DB: \(error.localizedDescription)")
        }

        if migrated {
            migrated = false
            Task {
                await Maintini.maintain {
                    await updateIndexingFromScratch(settings: settings)
                }
            }
        } else {
            Task {
                await Maintini.maintain {
                    await processSpotlight(updates: newObjects, deletions: deletedObjects, settings: settings)
                }
            }
        }
    }

    private static func processSpotlight(updates: Set<NSManagedObject>, deletions: Set<NSManagedObject>, settings: Settings.Cache) async {
        guard CSSearchableIndex.isIndexingAvailable() else {
            return
        }
        let urisToDelete = Lista<String>()
        let itemsToReIndex = Lista<CSSearchableItem>()
        for updatedItem in updates {
            guard let updatedItem = updatedItem as? ListableItem else {
                continue
            }
            let result = await updatedItem.handleSpotlight(settings: settings)
            switch result {
            case let .needsIndexing(item):
                itemsToReIndex.append(item)
            case let .needsRemoval(uri):
                urisToDelete.append(uri)
            }
        }
        for deletedItem in deletions {
            guard let deletedItem = deletedItem as? ListableItem else {
                continue
            }
            let uri = deletedItem.objectID.uriRepresentation().absoluteString
            urisToDelete.append(uri)
        }
        let index = CSSearchableIndex.default()
        if urisToDelete.count > 0 {
            await Logging.shared.log("Deleting spotlight indexes for \(urisToDelete.count) items")
            try? await index.deleteSearchableItems(withIdentifiers: Array(urisToDelete))
        }
        if itemsToReIndex.count > 0 {
            await Logging.shared.log("Updating spotlight indexes for \(itemsToReIndex.count) items")
            try? await index.indexSearchableItems(Array(itemsToReIndex))
        }
    }

    static func info(for item: DataItem) -> [String: Sendable] {
        if let item = item.asComment {
            let uri = item.objectID.uriRepresentation().absoluteString
            let parentUri = (item.parent?.objectID.uriRepresentation().absoluteString).orEmpty
            return [COMMENT_ID_KEY: uri, LISTABLE_URI_KEY: parentUri]

        } else if let item = item.asPr ?? item.asIssue {
            let uri = item.objectID.uriRepresentation().absoluteString
            return [NOTIFICATION_URL_KEY: item.webUrl!, LISTABLE_URI_KEY: uri]

        } else if let item = item.asReview {
            let pr = item.pullRequest
            let uri = pr.objectID.uriRepresentation().absoluteString
            return [NOTIFICATION_URL_KEY: pr.webUrl!, LISTABLE_URI_KEY: uri]

        } else if let item = item.asRepo {
            return [NOTIFICATION_URL_KEY: item.webUrl!]

        } else if let item = item.asStatus {
            let pr = item.pullRequest
            let uri = pr.objectID.uriRepresentation().absoluteString
            return [NOTIFICATION_URL_KEY: pr.webUrl!, LISTABLE_URI_KEY: uri]

        } else if let item = item.asReaction {
            if let issue = item.issue {
                let uri = issue.objectID.uriRepresentation().absoluteString
                return [NOTIFICATION_URL_KEY: issue.webUrl!, LISTABLE_URI_KEY: uri]
            } else if let pr = item.pullRequest {
                let uri = pr.objectID.uriRepresentation().absoluteString
                return [NOTIFICATION_URL_KEY: pr.webUrl!, LISTABLE_URI_KEY: uri]
            } else if let comment = item.comment {
                let uri = comment.objectID.uriRepresentation().absoluteString
                let parentUri = (comment.parent?.objectID.uriRepresentation().absoluteString).orEmpty
                return [COMMENT_ID_KEY: uri, LISTABLE_URI_KEY: parentUri]
            } else {
                abort()
            }

        } else {
            abort()
        }
    }

    static func postMigrationTasks() {
        if _justMigrated {
            ApiServer.resetSyncOfEverything()
            _justMigrated = false
        }
    }

    static func postProcessAllItems(in context: NSManagedObjectContext, settings: Settings.Cache) async {
        let start = Date()
        let increment = 200

        await withTaskGroup { group in
            let prCount = PullRequest.countItems(in: context)
            for i in stride(from: 0, to: prCount, by: increment) {
                group.addTask(priority: .high) {
                    await runInChild(of: context) { child in
                        for p in PullRequest.allItems(offset: i, count: increment, in: child, prefetchRelationships: ["comments", "reactions", "reviews"]) {
                            p.postProcess(settings: settings)
                        }
                    }
                }
            }

            let issueCount = Issue.countItems(in: context)
            for i in stride(from: 0, to: issueCount, by: increment) {
                group.addTask(priority: .high) {
                    await runInChild(of: context) { child in
                        for i in Issue.allItems(offset: i, count: increment, in: child, prefetchRelationships: ["comments", "reactions"]) {
                            i.postProcess(settings: settings)
                        }
                    }
                }
            }
        }

        await Logging.shared.log("Postprocess done - \(-start.timeIntervalSinceNow) sec")
    }

    static func id(for uriPath: String?) -> NSManagedObjectID? {
        if let uriPath, let url = URL(string: uriPath), let persistentStoreCoordinator {
            return persistentStoreCoordinator.managedObjectID(forURIRepresentation: url)
        }
        return nil
    }

    static let dataFilesDirectory: URL = {
        #if os(iOS)
            let finalURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Trailer")!
        #else
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).last!
            let finalURL = appSupportURL.appendingPathComponent("com.housetrip.Trailer")
        #endif
        Task {
            await Logging.shared.log("Files in \(finalURL.path)")
        }
        return finalURL
    }()

    static func removeDatabaseFiles() {
        let fm = FileManager.default
        let documentsDirectory = dataFilesDirectory.path
        do {
            for file in try fm.contentsOfDirectory(atPath: documentsDirectory) where file.contains("Trailer.sqlite") {
                Task {
                    await Logging.shared.log("Removing old database file: \(file)")
                }
                try! fm.removeItem(atPath: documentsDirectory.appending(pathComponent: file))
            }
        } catch { /* no directory */ }
    }

    static var appIsConfigured: Bool {
        ApiServer.someServersHaveAuthTokens(in: main) && Repo.anyVisibleRepos(in: main)
    }

    private static var _justMigrated = false

    static var persistentStoreCoordinator: NSPersistentStoreCoordinator? = {
        let storeOptions: [AnyHashable: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true,
            NSSQLitePragmasOption: ["synchronous": "OFF"]
        ]

        let modelPath = Bundle.main.url(forResource: "Trailer", withExtension: "momd")!
        let mom = NSManagedObjectModel(contentsOf: modelPath)!

        let dataDir = dataFilesDirectory
        let sqlStorePath = dataDir.appendingPathComponent("Trailer.sqlite")
        Task {
            await Logging.shared.log("DB: \(sqlStorePath.path)")
        }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sqlStorePath.path) {
            if let m = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: sqlStorePath, options: nil) {
                _justMigrated = !mom.isConfiguration(withName: nil, compatibleWithStoreMetadata: m)
            }
        } else {
            do {
                try fileManager.createDirectory(atPath: dataDir.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Task {
                    await Logging.shared.log("Database directory creation error: \(error.localizedDescription)")
                }
                return nil
            }
        }

        do {
            let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: mom)
            try persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: sqlStorePath, options: storeOptions)
            Task {
                await Logging.shared.log("Database setup complete")
            }
            return persistentStoreCoordinator
        } catch {
            Task {
                await Logging.shared.log("Database setup error: \(error.localizedDescription)")
            }
            return nil
        }
    }()
}
