
import CoreData

let mainObjectContext = DataManager.buildMainContext()

final class DataManager {

	static var postMigrationRepoPrPolicy: RepoDisplayPolicy?
	static var postMigrationRepoIssuePolicy: RepoDisplayPolicy?

	class func checkMigration() {

		guard mainObjectContext.persistentStoreCoordinator?.persistentStores.count > 0 else { return }

		if Settings.lastRunVersion != versionString() {
			DLog("VERSION UPDATE MAINTENANCE NEEDED")
			#if os(iOS)
				migrateDatabaseToShared()
			#endif
			performVersionChangedTasks()
			Settings.lastRunVersion = versionString()
		}
		ApiServer.ensureAtLeastGithubInMoc(mainObjectContext)
	}

	private class func performVersionChangedTasks() {

		let d = UserDefaults.standard
		if let legacyAuthToken = d.object(forKey: "GITHUB_AUTH_TOKEN") as? String {
			var legacyApiHost = S(d.object(forKey: "API_BACKEND_SERVER") as? String)
			if legacyApiHost.isEmpty { legacyApiHost = "api.github.com" }

			let legacyApiPath = S(d.object(forKey: "API_SERVER_PATH") as? String)

			var legacyWebHost = S(d.object(forKey: "API_FRONTEND_SERVER") as? String)
			if legacyWebHost.isEmpty { legacyWebHost = "github.com" }

			let actualApiPath = "\(legacyApiHost)/\(legacyApiPath)".replacingOccurrences(of: "//", with:"/")

			let newApiServer = ApiServer.addDefaultGithubInMoc(mainObjectContext)
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
			ApiServer.ensureAtLeastGithubInMoc(mainObjectContext)
		}

		DLog("Marking all repos as dirty")
		ApiServer.resetSyncOfEverything()

		DLog("Marking all unspecified (nil) announced flags as announced")
		for i in DataItem.allItemsOfType("PullRequest", inMoc: mainObjectContext) as! [PullRequest] {
			if i.announced == nil {
				i.announced = true
			}
		}
		for i in DataItem.allItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue] {
			if i.announced == nil {
				i.announced = true
			}
		}

		DLog("Migrating display policies")
		for r in DataItem.allItemsOfType("Repo", inMoc:mainObjectContext) as! [Repo] {
			if let markedAsHidden = r.hidden?.boolValue, markedAsHidden == true {
				r.displayPolicyForPrs = RepoDisplayPolicy.hide.rawValue
				r.displayPolicyForIssues = RepoDisplayPolicy.hide.rawValue
			} else {
				if let prDisplayPolicy = postMigrationRepoPrPolicy, r.displayPolicyForPrs == nil {
					r.displayPolicyForPrs = prDisplayPolicy.rawValue
				}
				if let issueDisplayPolicy = postMigrationRepoIssuePolicy, r.displayPolicyForIssues == nil {
					r.displayPolicyForIssues = issueDisplayPolicy.rawValue
				}
			}
			if r.hidden != nil {
				r.hidden = nil
			}
		}
	}

	private class func migrateDatabaseToShared() {
		do {
			let oldDocumentsDirectory = legacyFilesDirectory().path
			let newDocumentsDirectory = sharedFilesDirectory().path
			let fm = FileManager.default
			let files = try fm.contentsOfDirectory(atPath: oldDocumentsDirectory)
			DLog("Migrating DB files into group container from %@ to %@", oldDocumentsDirectory, newDocumentsDirectory)
			for file in files {
				if file.contains("Trailer.sqlite") {
					DLog("Moving database file: %@",file)
					let oldPath = oldDocumentsDirectory.stringByAppendingPathComponent(file)
					let newPath = newDocumentsDirectory.stringByAppendingPathComponent(file)
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

		func processItems(_ type: String, newNotification: NotificationType, reopenedNotification: NotificationType, assignmentNotification: NotificationType) -> [ListableItem] {
			let allItems = DataItem.allItemsOfType(type, inMoc: mainObjectContext) as! [ListableItem]
			for i in allItems {
				if i.isVisibleOnMenu {
					if !i.createdByMe {
						if !(i.isNewAssignment?.boolValue ?? false) && !(i.announced?.boolValue ?? false) {
							app.postNotification(type: newNotification, forItem: i)
							i.announced = true
						}
						if let reopened = i.reopened?.boolValue, reopened == true {
							app.postNotification(type: reopenedNotification, forItem: i)
							i.reopened = false
						}
						if let newAssignment = i.isNewAssignment?.boolValue, newAssignment == true {
							app.postNotification(type: assignmentNotification, forItem: i)
							i.isNewAssignment = false
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

		let allPrs = processItems("PullRequest", newNotification: .newPr, reopenedNotification: .prReopened, assignmentNotification: .newPrAssigned)
		let allIssues = processItems("Issue", newNotification: .newIssue, reopenedNotification: .issueReopened, assignmentNotification: .newIssueAssigned)

		let latestComments = PRComment.newItemsOfType("PRComment", inMoc: mainObjectContext) as! [PRComment]
		for c in latestComments {
			c.processNotifications()
			c.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		let latestStatuses = PRStatus.newItemsOfType("PRStatus", inMoc: mainObjectContext) as! [PRStatus]
		if Settings.notifyOnStatusUpdates {
			var coveredPrs = Set<NSManagedObjectID>()
			for s in latestStatuses {
				let pr = s.pullRequest
				if pr.isVisibleOnMenu && (Settings.notifyOnStatusUpdatesForAllPrs || pr.createdByMe || pr.assignedToParticipated || pr.assignedToMySection) {
					if !coveredPrs.contains(pr.objectID) {
						coveredPrs.insert(pr.objectID)
						if let s = pr.displayedStatuses.first {
							let displayText = s.descriptionText
							if pr.lastStatusNotified != displayText && pr.postSyncAction?.intValue != PostSyncAction.noteNew.rawValue {
								if pr.isSnoozing && Settings.snoozeWakeOnStatusUpdate {
									DLog("Waking up snoozed PR ID %@ because of a status update", pr.serverId)
									pr.wakeUp()
								}
								app.postNotification(type: .newStatus, forItem: s)
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
			if p.postSyncAction?.intValue != PostSyncAction.doNothing.rawValue {
				p.postSyncAction = PostSyncAction.doNothing.rawValue
			}
		}

		for i in allIssues {
			if i.postSyncAction?.intValue != PostSyncAction.doNothing.rawValue {
				i.postSyncAction = PostSyncAction.doNothing.rawValue
			}
		}

		_ = saveDB()
	}

	class func saveDB() {
		if mainObjectContext.hasChanges {
			DLog("Saving DB")
			do {
				try mainObjectContext.save()
			} catch {
				DLog("Error while saving DB: %@", (error as NSError).localizedDescription)
			}
		}
	}

	class func childContext() -> NSManagedObjectContext {
		let c = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		c.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
		c.parent = mainObjectContext
		c.undoManager = nil
		return c
	}

	class func infoForType(_ type: NotificationType, item: DataItem) -> [String : AnyObject] {
		switch type {
		case .newMention, .newComment:
			return [COMMENT_ID_KEY : item.objectID.uriRepresentation().absoluteString]
		case .newPr, .prReopened, .newPrAssigned, .prClosed, .prMerged:
			return [NOTIFICATION_URL_KEY : (item as! PullRequest).webUrl!, PULL_REQUEST_ID_KEY: item.objectID.uriRepresentation().absoluteString]
		case .newRepoSubscribed, .newRepoAnnouncement:
			return [NOTIFICATION_URL_KEY : (item as! Repo).webUrl!]
		case .newStatus:
			let pr = (item as! PRStatus).pullRequest
			return [NOTIFICATION_URL_KEY : pr.webUrl!, STATUS_ID_KEY: pr.objectID.uriRepresentation().absoluteString]
		case .newIssue, .issueReopened, .newIssueAssigned, .issueClosed:
			return [NOTIFICATION_URL_KEY : (item as! Issue).webUrl!, ISSUE_ID_KEY: item.objectID.uriRepresentation().absoluteString]
		}
	}

	class func postMigrationTasks() {
		if _justMigrated {
			ApiServer.resetSyncOfEverything()
			_justMigrated = false
		}
	}

	class func postProcessAllItems() {
		for p in DataItem.allItemsOfType("PullRequest", inMoc: mainObjectContext) as! [PullRequest] {
			p.postProcess()
		}
		for i in DataItem.allItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue] {
			i.postProcess()
		}
	}

	class func idForUriPath(_ uriPath: String?) -> NSManagedObjectID? {
		if let up = uriPath, let u = URL(string: up), let p = mainObjectContext.persistentStoreCoordinator {
			return p.managedObjectID(forURIRepresentation: u)
		}
		return nil
	}

	private class func dataFilesDirectory() -> URL {
		#if os(iOS)
			let sharedFiles = sharedFilesDirectory()
		#else
			let sharedFiles = legacyFilesDirectory()
		#endif
		DLog("Files in %@", sharedFiles)
		return sharedFiles
	}

	private class func legacyFilesDirectory() -> URL {
		let f = FileManager.default
		let appSupportURL = f.urls(for: FileManager.SearchPathDirectory.applicationSupportDirectory, in: FileManager.SearchPathDomainMask.userDomainMask).last!
		return appSupportURL.appendingPathComponent("com.housetrip.Trailer")
	}

	class func sharedFilesDirectory() -> URL {
		return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.Trailer")!
	}

	class func removeDatabaseFiles() {
		let fm = FileManager.default
		let documentsDirectory = dataFilesDirectory().path
		do {
			for file in try fm.contentsOfDirectory(atPath: documentsDirectory) {
				if file.contains("Trailer.sqlite") {
					DLog("Removing old database file: %@",file)
					try! fm.removeItem(atPath: documentsDirectory.stringByAppendingPathComponent(file))
				}
			}
		} catch { /* no directory */ }
	}

	class var appIsConfigured: Bool {
		return ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) && Repo.anyVisibleReposInMoc(mainObjectContext)
	}

	private static var _justMigrated = false

	class func buildMainContext() -> NSManagedObjectContext {

		let storeOptions = [
			NSMigratePersistentStoresAutomaticallyOption: true,
			NSInferMappingModelAutomaticallyOption: true,
			NSSQLitePragmasOption: ["synchronous":"OFF", "fullfsync":"0"]
		]

		let dataDir = dataFilesDirectory()
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
			DLog("Database setup error: %@", (error as NSError).localizedDescription)
		}

		return m
	}
}
