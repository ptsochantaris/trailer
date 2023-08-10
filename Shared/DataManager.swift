import CoreData
import CoreSpotlight
import Lista
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
            Logging.log("VERSION UPDATE MAINTENANCE NEEDED")
            ApiServer.ensureAtLeastGithub(in: main)
            ApiServer.resetSyncOfEverything()
            Settings.lastRunVersion = versionString
            migrated = true
        }
        ApiServer.ensureAtLeastGithub(in: main)
    }

    private static func processNotificationsForItems(of type: (some ListableItem).Type, newNotification: NotificationType, reopenedNotification: NotificationType, assignmentNotification: NotificationType) async {
        await runInChild(of: main) { child in
            for i in type.allItems(in: child) {
                if i.stateChanged != 0 {
                    switch i.stateChanged {
                    case ListableItem.StateChange.reopened.rawValue:
                        NotificationQueue.add(type: reopenedNotification, for: i)
                        i.announced = true

                    case ListableItem.StateChange.merged.rawValue:
                        i.handleMerging()

                    case ListableItem.StateChange.closed.rawValue:
                        i.handleClosing()

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

    private static func processCommentAndReviewNotifications(postProcessContext: PostProcessContext) async {
        await runInChild(of: main) { child in
            for c in PRComment.newItems(in: child) {
                c.processNotifications(postProcessContext: postProcessContext)
                c.postSyncAction = PostSyncAction.doNothing.rawValue
            }

            for r in Review.newOrUpdatedItems(in: child) {
                r.processNotifications()
                r.postSyncAction = PostSyncAction.doNothing.rawValue
            }
        }
    }

    private static func processStatusNotifications(postProcessContext: PostProcessContext) async {
        await runInChild(of: main) { child in
            let latestStatuses = PRStatus.newItems(in: child)
            var coveredPrs = Set<NSManagedObjectID>()
            if postProcessContext.notifyOnStatusUpdates {
                for pr in latestStatuses.map(\.pullRequest) where pr.shouldAnnounceStatus && !coveredPrs.contains(pr.objectID) {
                    coveredPrs.insert(pr.objectID)
                    if let s = pr.displayedStatuses.first {
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
                Logging.log("Waking up snoozed PR ID \(pr.nodeId ?? "<no ID>") because of a status update")
                pr.wakeUp()
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

    static func sendNotificationsIndexAndSave() async {
        await saveDB() // get IDs

        let postProcessContext = PostProcessContext()

        await postProcessAllItems(in: main, postProcessContext: postProcessContext)

        await processNotificationsForItems(of: PullRequest.self, newNotification: .newPr, reopenedNotification: .prReopened, assignmentNotification: .newPrAssigned)

        await processNotificationsForItems(of: Issue.self, newNotification: .newIssue, reopenedNotification: .issueReopened, assignmentNotification: .newIssueAssigned)

        await processCommentAndReviewNotifications(postProcessContext: postProcessContext)

        await processStatusNotifications(postProcessContext: postProcessContext)

        await runInChild(of: main) { child in
            let nothing = PostSyncAction.doNothing.rawValue

            for r in Reaction.newOrUpdatedItems(in: child) {
                r.checkNotifications()
                r.postSyncAction = nothing
            }

            for r in Review.newOrUpdatedItems(in: child) {
                r.postSyncAction = nothing
            }

            for r in PRComment.newOrUpdatedItems(in: child) {
                r.postSyncAction = nothing
            }

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

    private static func updateIndexingFromScratch() async {
        guard CSSearchableIndex.isIndexingAvailable() else {
            return
        }

        Logging.log("Re-indexing spotlight")

        let itemsToIndex = Lista<CSSearchableItem>()
        let itemsToRemove = Lista<String>()

        for pr in PullRequest.allItems(in: main) {
            switch await pr.handleSpotlight() {
            case let .needsIndexing(item):
                itemsToIndex.append(item)
            case let .needsRemoval(uri):
                itemsToRemove.append(uri)
            }
        }

        for issue in Issue.allItems(in: main) {
            switch await issue.handleSpotlight() {
            case let .needsIndexing(item):
                itemsToIndex.append(item)
            case let .needsRemoval(uri):
                itemsToRemove.append(uri)
            }
        }

        let index = CSSearchableIndex.default()

        do {
            Logging.log("Clearing spotlight indexes")
            try await index.deleteAllSearchableItems()
        } catch {
            Logging.log("Error clearing existing spotlight index: \(error.localizedDescription)")
        }

        Logging.log("Comitting spotlight indexes")
        if itemsToRemove.count > 0 {
            Logging.log("De-indexing \(itemsToRemove.count) items...")
            try? await index.deleteSearchableItems(withIdentifiers: Array(itemsToRemove))
        }
        if itemsToIndex.count > 0 {
            Logging.log("Indexing \(itemsToIndex.count) items...")
            try? await index.indexSearchableItems(Array(itemsToIndex))
        }
        Logging.log("Committed spotlight changes")
    }

    static func saveDB() async {
        #if os(iOS)
            BackgroundTask.registerForBackground()
        #endif

        guard main.hasChanges else {
            Logging.log("No DB changes")
            if migrated {
                await processSpotlight(newItems: [])
            }
            return
        }

        if !migrated {
            #if os(iOS)
                BackgroundTask.registerForBackground()
            #endif
            Task {
                await processSpotlight(updates: main.updatedObjects, deletions: main.deletedObjects)
                #if os(iOS)
                    BackgroundTask.unregisterForBackground()
                #endif
            }
        }

        let newObjects = main.insertedObjects

        Logging.log("Saving DB")
        do {
            try main.save()
        } catch {
            Logging.log("Error while saving DB: \(error.localizedDescription)")
        }

        Task {
            await processSpotlight(newItems: newObjects)
        }
    }

    private static func processSpotlight(newItems: Set<NSManagedObject>) async {
        if migrated {
            migrated = false
            await updateIndexingFromScratch()
        } else {
            await processSpotlight(updates: newItems, deletions: [])
        }
        #if os(iOS)
            BackgroundTask.unregisterForBackground()
        #endif
    }

    private static func processSpotlight(updates: Set<NSManagedObject>, deletions: Set<NSManagedObject>) async {
        guard CSSearchableIndex.isIndexingAvailable() else {
            return
        }
        let urisToDelete = Lista<String>()
        let itemsToReIndex = Lista<CSSearchableItem>()
        for updatedItem in updates {
            guard let updatedItem = updatedItem as? ListableItem else {
                continue
            }
            let result = await updatedItem.handleSpotlight()
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
            Logging.log("Deleting spotlight indexes for \(urisToDelete.count) items")
            try? await index.deleteSearchableItems(withIdentifiers: Array(urisToDelete))
        }
        if itemsToReIndex.count > 0 {
            Logging.log("Updating spotlight indexes for \(itemsToReIndex.count) items")
            try? await index.indexSearchableItems(Array(itemsToReIndex))
        }
    }

    static func info(for item: DataItem) -> JSON {
        if let item = item as? PRComment {
            let uri = item.objectID.uriRepresentation().absoluteString
            let parentUri = item.parent?.objectID.uriRepresentation().absoluteString ?? ""
            return [COMMENT_ID_KEY: uri, LISTABLE_URI_KEY: parentUri]

        } else if let item = item as? ListableItem {
            let uri = item.objectID.uriRepresentation().absoluteString
            return [NOTIFICATION_URL_KEY: item.webUrl!, LISTABLE_URI_KEY: uri]

        } else if let item = item as? Review {
            let pr = item.pullRequest
            let uri = pr.objectID.uriRepresentation().absoluteString
            return [NOTIFICATION_URL_KEY: pr.webUrl!, LISTABLE_URI_KEY: uri]

        } else if let item = item as? Repo {
            return [NOTIFICATION_URL_KEY: item.webUrl!]

        } else if let item = item as? PRStatus {
            let pr = item.pullRequest
            let uri = pr.objectID.uriRepresentation().absoluteString
            return [NOTIFICATION_URL_KEY: pr.webUrl!, LISTABLE_URI_KEY: uri]

        } else if let item = item as? Reaction {
            if let issue = item.issue {
                let uri = issue.objectID.uriRepresentation().absoluteString
                return [NOTIFICATION_URL_KEY: issue.webUrl!, LISTABLE_URI_KEY: uri]
            } else if let pr = item.pullRequest {
                let uri = pr.objectID.uriRepresentation().absoluteString
                return [NOTIFICATION_URL_KEY: pr.webUrl!, LISTABLE_URI_KEY: uri]
            } else if let comment = item.comment {
                let uri = comment.objectID.uriRepresentation().absoluteString
                let parentUri = comment.parent?.objectID.uriRepresentation().absoluteString ?? ""
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

    static func postProcessAllItems(in context: NSManagedObjectContext, postProcessContext: PostProcessContext = PostProcessContext()) async {
        let start = Date()
        let increment = 200

        await withTaskGroup(of: Void.self) { group in
            let prCount = PullRequest.countItems(in: context)
            for i in stride(from: 0, to: prCount, by: increment) {
                group.addTask(priority: .high) {
                    await runInChild(of: context) { child in
                        for p in PullRequest.allItems(offset: i, count: increment, in: child, prefetchRelationships: ["comments", "reactions", "reviews"]) {
                            p.postProcess(context: postProcessContext)
                        }
                    }
                }
            }

            let issueCount = Issue.countItems(in: context)
            for i in stride(from: 0, to: issueCount, by: increment) {
                group.addTask(priority: .high) {
                    await runInChild(of: context) { child in
                        for i in Issue.allItems(offset: i, count: increment, in: child, prefetchRelationships: ["comments", "reactions"]) {
                            i.postProcess(context: postProcessContext)
                        }
                    }
                }
            }
        }

        Logging.log("Postprocess done - \(-start.timeIntervalSinceNow) sec")
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
        Logging.log("Files in \(finalURL.path)")
        return finalURL
    }()

    static func removeDatabaseFiles() {
        let fm = FileManager.default
        let documentsDirectory = dataFilesDirectory.path
        do {
            for file in try fm.contentsOfDirectory(atPath: documentsDirectory) where file.contains("Trailer.sqlite") {
                Logging.log("Removing old database file: \(file)")
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
        Logging.log("DB: \(sqlStorePath.path)")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sqlStorePath.path) {
            if let m = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: sqlStorePath, options: nil) {
                _justMigrated = !mom.isConfiguration(withName: nil, compatibleWithStoreMetadata: m)
            }
        } else {
            do {
                try fileManager.createDirectory(atPath: dataDir.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                Logging.log("Database directory creation error: \(error.localizedDescription)")
                return nil
            }
        }

        do {
            let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: mom)
            try persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: sqlStorePath, options: storeOptions)
            Logging.log("Database setup complete")
            return persistentStoreCoordinator
        } catch {
            Logging.log("Database setup error: \(error.localizedDescription)")
            return nil
        }
    }()
}
