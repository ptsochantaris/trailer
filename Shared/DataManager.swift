import CoreData
import CoreSpotlight

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
            DLog("VERSION UPDATE MAINTENANCE NEEDED")
            performVersionChangedTasks()
            Settings.lastRunVersion = versionString
            migrated = true
        }
        ApiServer.ensureAtLeastGithub(in: main)
    }

    private static func performVersionChangedTasks() {
        #if os(OSX)
            let nc = NSUserNotificationCenter.default

            // Unstick macOS notifications with custom actions but without an identifier, causes macOS to keep them forever
            for notification in nc.deliveredNotifications where notification.additionalActions != nil && notification.identifier == nil {
                nc.removeAllDeliveredNotifications()
                break
            }

            // Migrate delivered notifications from old keys
            for notification in nc.deliveredNotifications {
                if let userInfo = notification.userInfo, let u = (userInfo["pullRequestIdKey"] as? String) ?? (userInfo["issueIdKey"] as? String) ?? (userInfo["statusIdKey"] as? String) {
                    notification.userInfo![LISTABLE_URI_KEY] = u
                    notification.userInfo!["pullRequestIdKey"] = nil
                    notification.userInfo!["issueIdKey"] = nil
                    notification.userInfo!["statusIdKey"] = nil
                    nc.deliver(notification)
                }
            }
        #endif

        let d = UserDefaults.standard
        if let legacyAuthToken = d.object(forKey: "GITHUB_AUTH_TOKEN") as? String {
            var legacyApiHost = S(d.object(forKey: "API_BACKEND_SERVER") as? String)
            if legacyApiHost.isEmpty { legacyApiHost = "api.github.com" }

            let legacyApiPath = S(d.object(forKey: "API_SERVER_PATH") as? String)

            var legacyWebHost = S(d.object(forKey: "API_FRONTEND_SERVER") as? String)
            if legacyWebHost.isEmpty { legacyWebHost = "github.com" }

            let actualApiPath = "\(legacyApiHost)/\(legacyApiPath)".replacingOccurrences(of: "//", with: "/")

            let newApiServer = ApiServer.addDefaultGithub(in: main)
            newApiServer.apiPath = "https://\(actualApiPath)"
            newApiServer.webPath = "https://\(legacyWebHost)"
            newApiServer.authToken = legacyAuthToken
            newApiServer.lastSyncSucceeded = true

            d.removeObject(forKey: "API_BACKEND_SERVER")
            d.removeObject(forKey: "API_SERVER_PATH")
            d.removeObject(forKey: "API_FRONTEND_SERVER")
            d.removeObject(forKey: "GITHUB_AUTH_TOKEN")
        } else {
            ApiServer.ensureAtLeastGithub(in: main)
        }

        DLog("Resetting sync state of everything")
        ApiServer.resetSyncOfEverything()

        DLog("Marking all unspecified (nil) announced flags as announced")
        for i in DataItem.allItems(of: PullRequest.self, in: main) where i.value(forKey: "announced") == nil {
            i.announced = true
        }
        for i in DataItem.allItems(of: Issue.self, in: main) where i.value(forKey: "announced") == nil {
            i.announced = true
        }

        DLog("Migrating display policies")
        for r in DataItem.allItems(of: Repo.self, in: main) {
            if let markedAsHidden = (r.value(forKey: "hidden") as AnyObject?)?.boolValue, markedAsHidden == true {
                r.displayPolicyForPrs = RepoDisplayPolicy.hide.rawValue
                r.displayPolicyForIssues = RepoDisplayPolicy.hide.rawValue
            } else {
                if let prDisplayPolicy = postMigrationRepoPrPolicy, r.value(forKey: "displayPolicyForPrs") == nil {
                    r.displayPolicyForPrs = prDisplayPolicy.rawValue
                }
                if let issueDisplayPolicy = postMigrationRepoIssuePolicy, r.value(forKey: "displayPolicyForIssues") == nil {
                    r.displayPolicyForIssues = issueDisplayPolicy.rawValue
                }
            }
        }

        DLog("Migrating snooze presets")
        for s in SnoozePreset.allSnoozePresets(in: main) {
            if let m = postMigrationSnoozeWakeOnComment {
                s.wakeOnComment = m
            }
            if let m = postMigrationSnoozeWakeOnMention {
                s.wakeOnMention = m
            }
            if let m = postMigrationSnoozeWakeOnStatusUpdate {
                s.wakeOnStatusChange = m
            }
        }

        for s in DataItem.allItems(of: PRStatus.self, in: DataManager.main) where s.context == nil {
            s.resetSyncState()
        }
    }

    private static func processNotificationsForItems(of type: (some ListableItem).Type, newNotification: NotificationType, reopenedNotification: NotificationType, assignmentNotification: NotificationType) async {
        await runInChild(of: main) { child in
            let items = DataItem.allItems(of: type, in: child)
            for i in items {
                if i.stateChanged != 0 {
                    switch i.stateChanged {
                    case ListableItem.StateChange.reopened.rawValue:
                        NotificationQueue.add(type: reopenedNotification, for: i)
                        i.announced = true

                    case ListableItem.StateChange.merged.rawValue:
                        (i as? PullRequest)?.handleMerging()

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

    private static func processCommentAndReviewNotifications() async {
        await runInChild(of: main) { child in
            for c in PRComment.newItems(of: PRComment.self, in: child) {
                c.processNotifications()
                c.postSyncAction = PostSyncAction.doNothing.rawValue
            }

            for r in Review.newOrUpdatedItems(of: Review.self, in: child) {
                r.processNotifications()
                r.postSyncAction = PostSyncAction.doNothing.rawValue
            }
        }
    }

    private static func processStatusNotifications() async {
        await runInChild(of: main) { child in
            let latestStatuses = PRStatus.newItems(of: PRStatus.self, in: child)
            var coveredPrs = Set<NSManagedObjectID>()
            if Settings.notifyOnStatusUpdates {
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
                DLog("Waking up snoozed PR ID %@ because of a status update", pr.nodeId ?? "<no ID>")
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
        preferencesDirty = false

        await processNotificationsForItems(of: PullRequest.self, newNotification: .newPr, reopenedNotification: .prReopened, assignmentNotification: .newPrAssigned)

        await processNotificationsForItems(of: Issue.self, newNotification: .newIssue, reopenedNotification: .issueReopened, assignmentNotification: .newIssueAssigned)

        await processCommentAndReviewNotifications()

        await processStatusNotifications()

        await runInChild(of: main) { child in
            for r in DataItem.newOrUpdatedItems(of: Reaction.self, in: child) {
                r.checkNotifications()
                r.postSyncAction = PostSyncAction.doNothing.rawValue
            }

            for r in DataItem.newOrUpdatedItems(of: Review.self, in: child) {
                r.postSyncAction = PostSyncAction.doNothing.rawValue
            }

            for r in DataItem.newOrUpdatedItems(of: PRComment.self, in: child) {
                r.postSyncAction = PostSyncAction.doNothing.rawValue
            }

            for p in DataItem.newOrUpdatedItems(of: PullRequest.self, in: child) {
                p.postSyncAction = PostSyncAction.doNothing.rawValue
            }

            for i in DataItem.newOrUpdatedItems(of: Issue.self, in: child) {
                i.postSyncAction = PostSyncAction.doNothing.rawValue
            }
        }

        await saveDB()

        NotificationQueue.commit()
    }

    private static func updateIndexingFromScratch() async {
        guard CSSearchableIndex.isIndexingAvailable() else {
            return
        }

        DLog("Re-indexing spotlight")

        let itemsToIndex = LinkedList<CSSearchableItem>()
        let itemsToRemove = LinkedList<String>()

        for pr in DataItem.allItems(of: PullRequest.self, in: main) {
            switch await pr.handleSpotlight() {
            case let .needsIndexing(item):
                itemsToIndex.append(item)
            case let .needsRemoval(uri):
                itemsToRemove.append(uri)
            }
        }

        for issue in DataItem.allItems(of: Issue.self, in: main) {
            switch await issue.handleSpotlight() {
            case let .needsIndexing(item):
                itemsToIndex.append(item)
            case let .needsRemoval(uri):
                itemsToRemove.append(uri)
            }
        }

        let index = CSSearchableIndex.default()

        do {
            DLog("Clearing spotlight indexes")
            try await index.deleteAllSearchableItems()
        } catch {
            DLog("Error clearing existing spotlight index: \(error.localizedDescription)")
        }

        DLog("Comitting spotlight indexes")
        if itemsToRemove.count > 0 {
            DLog("De-indexing \(itemsToRemove.count) items...")
            try? await index.deleteSearchableItems(withIdentifiers: Array(itemsToRemove))
        }
        if itemsToIndex.count > 0 {
            DLog("Indexing \(itemsToIndex.count) items...")
            try? await index.indexSearchableItems(Array(itemsToIndex))
        }
        DLog("Committed spotlight changes")
    }

    static func saveDB() async {
        #if os(iOS)
            BackgroundTask.registerForBackground()
        #endif

        guard main.hasChanges else {
            DLog("No DB changes")
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

        DLog("Saving DB")
        do {
            try main.save()
        } catch {
            DLog("Error while saving DB: %@", error.localizedDescription)
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
        let urisToDelete = LinkedList<String>()
        let itemsToReIndex = LinkedList<CSSearchableItem>()
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
            DLog("Deleting spotlight indexes for \(urisToDelete.count) items")
            try? await index.deleteSearchableItems(withIdentifiers: Array(urisToDelete))
        }
        if itemsToReIndex.count > 0 {
            DLog("Updating spotlight indexes for \(itemsToReIndex.count) items")
            try? await index.indexSearchableItems(Array(itemsToReIndex))
        }
    }

    static func info(for item: DataItem) -> [String: Any] {
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

    static func postProcessAllItems(in context: NSManagedObjectContext) async {
        let start = Date()
        let increment = 500
        let postProcessContext = PostProcessContext()

        await withTaskGroup(of: Void.self) { group in
            let prCount = DataItem.countItems(of: PullRequest.self, in: context)
            for i in stride(from: 0, to: prCount, by: increment) {
                group.addTask {
                    await runInChild(of: context) { child in
                        for p in DataItem.allItems(of: PullRequest.self, offset: i, count: increment, in: child, prefetchRelationships: ["comments", "reactions", "reviews"]) {
                            p.postProcess(context: postProcessContext)
                        }
                    }
                }
            }

            let issueCount = DataItem.countItems(of: Issue.self, in: context)
            for i in stride(from: 0, to: issueCount, by: increment) {
                group.addTask {
                    await runInChild(of: context) { child in
                        for i in DataItem.allItems(of: Issue.self, offset: i, count: increment, in: child, prefetchRelationships: ["comments", "reactions"]) {
                            i.postProcess(context: postProcessContext)
                        }
                    }
                }
            }
        }
        DLog("Postprocess done - \(-start.timeIntervalSinceNow) sec")
    }

    static func id(for uriPath: String?) -> NSManagedObjectID? {
        if let up = uriPath, let u = URL(string: up), let p = persistentStoreCoordinator {
            return p.managedObjectID(forURIRepresentation: u)
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
        DLog("Files in \(finalURL.path)")
        return finalURL
    }()

    static func removeDatabaseFiles() {
        let fm = FileManager.default
        let documentsDirectory = dataFilesDirectory.path
        do {
            for file in try fm.contentsOfDirectory(atPath: documentsDirectory) where file.contains("Trailer.sqlite") {
                DLog("Removing old database file: %@", file)
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
        DLog("DB: \(sqlStorePath.path)")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sqlStorePath.path) {
            if let m = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: sqlStorePath, options: nil) {
                _justMigrated = !mom.isConfiguration(withName: nil, compatibleWithStoreMetadata: m)
            }
        } else {
            do {
                try fileManager.createDirectory(atPath: dataDir.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                DLog("Database directory creation error: %@", error.localizedDescription)
                return nil
            }
        }

        do {
            let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: mom)
            try persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: sqlStorePath, options: storeOptions)
            DLog("Database setup complete")
            return persistentStoreCoordinator
        } catch {
            DLog("Database setup error: %@", error.localizedDescription)
            return nil
        }
    }()
}
