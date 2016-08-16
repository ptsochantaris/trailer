
import CoreData

let mainObjectContext = DataManager.buildMainContext()

final class DataManager {

	static var postMigrationRepoPrPolicy: RepoDisplayPolicy?
	static var postMigrationRepoIssuePolicy: RepoDisplayPolicy?
	static var postMigrationSnoozeWakeOnComment: Bool?
	static var postMigrationSnoozeWakeOnMention: Bool?
	static var postMigrationSnoozeWakeOnStatusUpdate: Bool?

	class func checkMigration() {

		guard let count = mainObjectContext.persistentStoreCoordinator?.persistentStores.count, count > 0 else { return }

		if Settings.lastRunVersion != versionString {
			DLog("VERSION UPDATE MAINTENANCE NEEDED")
			#if os(iOS)
				migrateDatabaseToShared()
			#endif
			performVersionChangedTasks()
			Settings.lastRunVersion = versionString
		}
		ApiServer.ensureAtLeastGithub(in: mainObjectContext)
	}

	private class func performVersionChangedTasks() {

		#if os(OSX)
		let nc = NSUserNotificationCenter.default

		// Unstick OS X notifications with custom actions but without an identifier, causes OS X to keep them forever
		if #available(OSX 10.10, *) {
			for notification in nc.deliveredNotifications {
				if notification.additionalActions != nil && notification.identifier == nil {
					nc.removeAllDeliveredNotifications()
					break
				}
			}
		}

		// Migrate delivered notifications from old keys
		for notification in nc.deliveredNotifications {
			if let userInfo = notification.userInfo, let u = (userInfo["pullRequestIdKey"] ?? userInfo["issueIdKey"] ?? userInfo["statusIdKey"]) as? String {
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

			let actualApiPath = "\(legacyApiHost)/\(legacyApiPath)".replacingOccurrences(of: "//", with:"/")

			let newApiServer = ApiServer.addDefaultGithub(in: mainObjectContext)
			newApiServer.apiPath = "https://\(actualApiPath)"
			newApiServer.webPath = "https://\(legacyWebHost)"
			newApiServer.authToken = legacyAuthToken
			newApiServer.lastSyncSucceeded = true

			d.removeObject(forKey: "API_BACKEND_SERVER")
			d.removeObject(forKey: "API_SERVER_PATH")
			d.removeObject(forKey: "API_FRONTEND_SERVER")
			d.removeObject(forKey: "GITHUB_AUTH_TOKEN")
			d.synchronize()
		} else {
			ApiServer.ensureAtLeastGithub(in: mainObjectContext)
		}

		DLog("Marking all repos as dirty")
		ApiServer.resetSyncOfEverything()

		DLog("Marking all unspecified (nil) announced flags as announced")
		for i in DataItem.allItems(of: PullRequest.self, in: mainObjectContext) {
			if i.value(forKey: "announced") == nil {
				i.announced = true
			}
		}
		for i in DataItem.allItems(of: Issue.self, in: mainObjectContext) {
			if i.value(forKey: "announced") == nil {
				i.announced = true
			}
		}

		DLog("Migrating display policies")
		for r in DataItem.allItems(of: Repo.self, in: mainObjectContext) {
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
		for s in SnoozePreset.allSnoozePresets(in: mainObjectContext) {
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
	}

	private class func migrateDatabaseToShared() {
		do {
			let oldDocumentsDirectory = legacyFilesDirectory.path
			let newDocumentsDirectory = sharedFilesDirectory.path
			let fm = FileManager.default
			let files = try fm.contentsOfDirectory(atPath: oldDocumentsDirectory)
			DLog("Migrating DB files into group container from %@ to %@", oldDocumentsDirectory, newDocumentsDirectory)
			for file in files {
				if file.contains("Trailer.sqlite") {
					DLog("Moving database file: %@",file)
					let oldPath = oldDocumentsDirectory.appending(pathComponent: file)
					let newPath = newDocumentsDirectory.appending(pathComponent: file)
					if fm.fileExists(atPath: newPath) {
						try! fm.removeItem(atPath: newPath)
					}
					try! fm.moveItem(atPath: oldPath, toPath: newPath)
				}
			}
			try! fm.removeItem(atPath: oldDocumentsDirectory)
		} catch {
			// No legacy directory
		}
	}

	class func sendNotificationsIndexAndSave() {

		func processItems<T: ListableItem>(of type: T.Type, newNotification: NotificationType, reopenedNotification: NotificationType, assignmentNotification: NotificationType) -> [T] {
			let allItems = DataItem.allItems(of: type, in: mainObjectContext)
			for i in allItems {
				if i.isVisibleOnMenu {
					if !i.createdByMe {
						if i.isNewAssignment {
							app.postNotification(type: assignmentNotification, for: i)
							i.isNewAssignment = false
						} else if !i.announced {
							app.postNotification(type: newNotification, for: i)
							i.announced = true
						} else if i.reopened {
							app.postNotification(type: reopenedNotification, for: i)
							i.reopened = false
						}
					}
					#if os(iOS)
						atNextEvent {
							i.indexForSpotlight()
						}
					#endif
				} else {
					atNextEvent {
						i.ensureInvisible()
					}
				}
			}
			return allItems
		}

		let allPrs = processItems(of: PullRequest.self, newNotification: .newPr, reopenedNotification: .prReopened, assignmentNotification: .newPrAssigned)
		let allIssues = processItems(of: Issue.self, newNotification: .newIssue, reopenedNotification: .issueReopened, assignmentNotification: .newIssueAssigned)

		let latestComments = PRComment.newItems(of: PRComment.self, in: mainObjectContext)
		for c in latestComments {
			c.processNotifications()
			c.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		let latestStatuses = PRStatus.newItems(of: PRStatus.self, in: mainObjectContext)
		if Settings.notifyOnStatusUpdates {
			var coveredPrs = Set<NSManagedObjectID>()
			for s in latestStatuses {
				let pr = s.pullRequest
				if pr.isVisibleOnMenu && (Settings.notifyOnStatusUpdatesForAllPrs || pr.createdByMe || pr.assignedToParticipated || pr.assignedToMySection) {
					if !coveredPrs.contains(pr.objectID) {
						coveredPrs.insert(pr.objectID)
						if let s = pr.displayedStatuses.first {
							let displayText = s.descriptionText
							if pr.lastStatusNotified != displayText && pr.postSyncAction != PostSyncAction.noteNew.rawValue {
								if pr.isSnoozing && pr.shouldWakeOnStatusChange {
									DLog("Waking up snoozed PR ID %lld because of a status update", pr.serverId)
									pr.wakeUp()
								}
								app.postNotification(type: .newStatus, for: s)
								pr.lastStatusNotified = displayText
							}
						} else {
							pr.lastStatusNotified = nil
						}
					}
				}
			}
		}

		for s in latestStatuses {
			s.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		for p in allPrs {
			p.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		for i in allIssues {
			i.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		_ = saveDB()
	}

	class func saveDB() {
		if mainObjectContext.hasChanges {
			DLog("Saving DB")
			do {
				try mainObjectContext.save()
			} catch {
				DLog("Error while saving DB: %@", error.localizedDescription)
			}
		}
	}

	class func buildChildContext() -> NSManagedObjectContext {
		let c = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		c.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
		c.parent = mainObjectContext
		c.undoManager = nil
		return c
	}

	class func info(for type: NotificationType, item: DataItem) -> [String : Any] {
		switch type {
		case .newMention, .newComment:
			let uri = item.objectID.uriRepresentation().absoluteString
			let parent = (item as! PRComment).parent
			let parentUri = parent?.objectID.uriRepresentation().absoluteString ?? ""
			return [COMMENT_ID_KEY: uri, LISTABLE_URI_KEY: parentUri]
		case .newPr, .prReopened, .newPrAssigned, .prClosed, .prMerged, .newIssue, .issueReopened, .newIssueAssigned, .issueClosed:
			let uri = item.objectID.uriRepresentation().absoluteString
			return [NOTIFICATION_URL_KEY: (item as! ListableItem).webUrl!, LISTABLE_URI_KEY: uri]
		case .newRepoSubscribed, .newRepoAnnouncement:
			return [NOTIFICATION_URL_KEY: (item as! Repo).webUrl!]
		case .newStatus:
			let pr = (item as! PRStatus).pullRequest
			let uri = pr.objectID.uriRepresentation().absoluteString
			return [NOTIFICATION_URL_KEY: pr.webUrl!, LISTABLE_URI_KEY: uri]
		}
	}

	class func postMigrationTasks() {
		if _justMigrated {
			ApiServer.resetSyncOfEverything()
			_justMigrated = false
		}
	}

	class func postProcessAllItems() {
		for p in DataItem.allItems(of: PullRequest.self, in: mainObjectContext) {
			p.postProcess()
		}
		for i in DataItem.allItems(of: Issue.self, in: mainObjectContext) {
			i.postProcess()
		}
	}

	class func id(for uriPath: String?) -> NSManagedObjectID? {
		if let up = uriPath, let u = URL(string: up), let p = mainObjectContext.persistentStoreCoordinator {
			return p.managedObjectID(forURIRepresentation: u)
		}
		return nil
	}

	private class var dataFilesDirectory: URL {
		#if os(iOS)
			let sharedFiles = sharedFilesDirectory
		#else
			let sharedFiles = legacyFilesDirectory
		#endif
		DLog("Files in %@", sharedFiles.absoluteString)
		return sharedFiles
	}

	private class var legacyFilesDirectory: URL {
		let f = FileManager.default
		let appSupportURL = f.urls(for: .applicationSupportDirectory, in: .userDomainMask).last!
		return appSupportURL.appendingPathComponent("com.housetrip.Trailer")
	}

	class var sharedFilesDirectory: URL {
		return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Trailer")!
	}

	class func removeDatabaseFiles() {
		let fm = FileManager.default
		let documentsDirectory = dataFilesDirectory.path
		do {
			for file in try fm.contentsOfDirectory(atPath: documentsDirectory) {
				if file.contains("Trailer.sqlite") {
					DLog("Removing old database file: %@",file)
					try! fm.removeItem(atPath: documentsDirectory.appending(pathComponent: file))
				}
			}
		} catch { /* no directory */ }
	}

	class var appIsConfigured: Bool {
		return ApiServer.someServersHaveAuthTokens(in: mainObjectContext) && Repo.anyVisibleRepos(in: mainObjectContext)
	}

	private static var _justMigrated = false

	class func buildMainContext() -> NSManagedObjectContext {

		let storeOptions: [AnyHashable : Any] = [
			NSMigratePersistentStoresAutomaticallyOption: true,
			NSInferMappingModelAutomaticallyOption: true,
			NSSQLitePragmasOption: ["synchronous":"NORMAL"]
		]

		let dataDir = dataFilesDirectory
		let sqlStorePath = dataDir.appendingPathComponent("Trailer.sqlite")

		let modelPath = Bundle.main.url(forResource: "Trailer", withExtension: "momd")!
		let mom = NSManagedObjectModel(contentsOf: modelPath)!

		let fileManager = FileManager.default
		if fileManager.fileExists(atPath: sqlStorePath.path) {
			if let m = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: sqlStorePath, options: nil) {
				_justMigrated = !mom.isConfiguration(withName: nil, compatibleWithStoreMetadata: m)
			}
		} else {
			try! fileManager.createDirectory(atPath: dataDir.path, withIntermediateDirectories: true, attributes: nil)
		}

		let m = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		m.undoManager = nil
		m.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

		do {
			let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: mom)
			try persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: sqlStorePath, options: storeOptions)
			m.persistentStoreCoordinator = persistentStoreCoordinator
			DLog("Database setup complete")
		} catch {
			DLog("Database setup error: %@", error.localizedDescription)
		}

		return m
	}
}
