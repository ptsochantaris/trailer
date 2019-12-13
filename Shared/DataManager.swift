
import CoreData

final class DataManager {

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

	static func checkMigration() {

		guard let count = main.persistentStoreCoordinator?.persistentStores.count, count > 0 else { return }

		if Settings.lastRunVersion != versionString {
			DLog("VERSION UPDATE MAINTENANCE NEEDED")
			performVersionChangedTasks()
			Settings.lastRunVersion = versionString
		}
		ApiServer.ensureAtLeastGithub(in: main)
	}

	private static func performVersionChangedTasks() {

		#if os(OSX)
		let nc = NSUserNotificationCenter.default

		// Unstick macOS notifications with custom actions but without an identifier, causes macOS to keep them forever
		for notification in nc.deliveredNotifications {
			if notification.additionalActions != nil && notification.identifier == nil {
				nc.removeAllDeliveredNotifications()
				break
			}
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

			let actualApiPath = "\(legacyApiHost)/\(legacyApiPath)".replacingOccurrences(of: "//", with:"/")

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
		for i in DataItem.allItems(of: PullRequest.self, in: main) {
			if i.value(forKey: "announced") == nil {
				i.announced = true
			}
		}
		for i in DataItem.allItems(of: Issue.self, in: main) {
			if i.value(forKey: "announced") == nil {
				i.announced = true
			}
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

		for s in DataItem.allItems(of: PRStatus.self, in: DataManager.main) {
			if s.context == nil {
				s.resetSyncState()
			}
		}
	}

	static func sendNotificationsIndexAndSave() {

		func processItems<T: ListableItem>(of type: T.Type, newNotification: NotificationType, reopenedNotification: NotificationType, assignmentNotification: NotificationType) -> [T] {
			let allItems = DataItem.allItems(of: type, in: main)
			for i in allItems {
				if i.isVisibleOnMenu {
					if !i.createdByMe {
						if i.isNewAssignment {
							NotificationQueue.add(type: assignmentNotification, for: i)
							i.announced = true
							i.isNewAssignment = false
						} else if !i.announced {
							NotificationQueue.add(type: newNotification, for: i)
							i.announced = true
						} else if i.reopened {
							NotificationQueue.add(type: reopenedNotification, for: i)
							i.announced = true
							i.reopened = false
						}
					}
					if #available(OSX 10.11, iOS 9, *) {
						atNextEvent {
							i.indexForSpotlight()
						}
					}
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

		let latestComments = PRComment.newItems(of: PRComment.self, in: main)
		for c in latestComments {
			c.processNotifications()
			c.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		let latestStatuses = PRStatus.newItems(of: PRStatus.self, in: main)
		if Settings.notifyOnStatusUpdates {
			var coveredPrs = Set<NSManagedObjectID>()
			for s in latestStatuses {
				let pr = s.pullRequest
				if pr.isVisibleOnMenu && (Settings.notifyOnStatusUpdatesForAllPrs || pr.createdByMe || pr.assignedToParticipated || pr.assignedToMySection) {
					if !coveredPrs.contains(pr.objectID) {
						coveredPrs.insert(pr.objectID)
						if let s = pr.displayedStatuses.first {
							let displayText = s.descriptionText
							if pr.lastStatusNotified != displayText && pr.postSyncAction != PostSyncAction.isNew.rawValue {
								if pr.isSnoozing && pr.shouldWakeOnStatusChange {
									DLog("Waking up snoozed PR ID %@ because of a status update", pr.serverId)
									pr.wakeUp()
								}
								NotificationQueue.add(type: .newStatus, for: s)
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

		for r in DataItem.newOrUpdatedItems(of: Review.self, in: main) {
			r.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		for r in DataItem.newOrUpdatedItems(of: PRComment.self, in: main) {
			r.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		for r in DataItem.newOrUpdatedItems(of: Reaction.self, in: main) {
			r.postSyncAction = PostSyncAction.doNothing.rawValue
		}

		saveDB()

		NotificationQueue.commit()
	}

	static func saveDB() {
		if main.hasChanges {
			DLog("Saving DB")
			do {
				try main.save()
			} catch {
				DLog("Error while saving DB: %@", error.localizedDescription)
			}
		}
	}

	static func buildChildContext() -> NSManagedObjectContext {
		let c = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
		c.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
		c.undoManager = nil
		c.parent = main
		return c
	}

	static func buildParallelContext() -> NSManagedObjectContext {
		let c = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
		c.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
		c.undoManager = nil
		c.persistentStoreCoordinator = persistentStoreCoordinator
		return c
	}

	static func info(for item: DataItem) -> [String : Any] {

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

	static func postProcessAllItems(in moc: NSManagedObjectContext? = nil) {
		let context = moc ?? main
		for p in DataItem.allItems(of: PullRequest.self, in: context, prefetchRelationships: ["comments", "reactions", "reviews"]) {
			p.postProcess()
		}
		for i in DataItem.allItems(of: Issue.self, in: context, prefetchRelationships: ["comments", "reactions"]) {
			i.postProcess()
		}
	}

	static func id(for uriPath: String?) -> NSManagedObjectID? {
		if let up = uriPath, let u = URL(string: up), let p = main.persistentStoreCoordinator {
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
			for file in try fm.contentsOfDirectory(atPath: documentsDirectory) {
				if file.contains("Trailer.sqlite") {
					DLog("Removing old database file: %@",file)
					try! fm.removeItem(atPath: documentsDirectory.appending(pathComponent: file))
				}
			}
		} catch { /* no directory */ }
	}

	static var appIsConfigured: Bool {
		return ApiServer.someServersHaveAuthTokens(in: main) && Repo.anyVisibleRepos(in: main)
	}

	private static var _justMigrated = false

	private static var persistentStoreCoordinator: NSPersistentStoreCoordinator? = {

		let storeOptions: [AnyHashable : Any] = [
			NSMigratePersistentStoresAutomaticallyOption: true,
			NSInferMappingModelAutomaticallyOption: true,
			NSSQLitePragmasOption: ["synchronous":"NORMAL"]
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
