
import CoreData
#if os(iOS)
	import UIKit
#endif

final class DataManager : NSObject {

	static var postMigrationRepoPrPolicy: RepoDisplayPolicy?
	static var postMigrationRepoIssuePolicy: RepoDisplayPolicy?

	class func checkMigration() {
		if Settings.lastRunVersion != versionString() {
			DLog("VERSION UPDATE MAINTENANCE NEEDED")
			#if os(iOS)
				migrateDatabaseToShared()
			#endif
			DataManager.performVersionChangedTasks()
			Settings.lastRunVersion = versionString()
		}
		ApiServer.ensureAtLeastGithubInMoc(mainObjectContext)
	}

	private class func performVersionChangedTasks() {

		let d = NSUserDefaults.standardUserDefaults()
		if let legacyAuthToken = d.objectForKey("GITHUB_AUTH_TOKEN") as? String {
			var legacyApiHost = S(d.objectForKey("API_BACKEND_SERVER") as? String)
			if legacyApiHost.isEmpty { legacyApiHost = "api.github.com" }

			let legacyApiPath = S(d.objectForKey("API_SERVER_PATH") as? String)

			var legacyWebHost = S(d.objectForKey("API_FRONTEND_SERVER") as? String)
			if legacyWebHost.isEmpty { legacyWebHost = "github.com" }

			let actualApiPath = "\(legacyApiHost)/\(legacyApiPath)".stringByReplacingOccurrencesOfString("//", withString:"/")

			let newApiServer = ApiServer.addDefaultGithubInMoc(mainObjectContext)
			newApiServer.apiPath = "https://\(actualApiPath)"
			newApiServer.webPath = "https://\(legacyWebHost)"
			newApiServer.authToken = legacyAuthToken
			newApiServer.lastSyncSucceeded = true

			d.removeObjectForKey("API_BACKEND_SERVER")
			d.removeObjectForKey("API_SERVER_PATH")
			d.removeObjectForKey("API_FRONTEND_SERVER")
			d.removeObjectForKey("GITHUB_AUTH_TOKEN")
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
			if let markedAsHidden = r.hidden?.boolValue where markedAsHidden == true {
				r.displayPolicyForPrs = RepoDisplayPolicy.Hide.rawValue
				r.displayPolicyForIssues = RepoDisplayPolicy.Hide.rawValue
			} else {
				if let prDisplayPolicy = postMigrationRepoPrPolicy where r.displayPolicyForPrs == nil {
					r.displayPolicyForPrs = prDisplayPolicy.rawValue
				}
				if let issueDisplayPolicy = postMigrationRepoIssuePolicy where r.displayPolicyForIssues == nil {
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
			let oldDocumentsDirectory = legacyFilesDirectory().path!
			let newDocumentsDirectory = sharedFilesDirectory().path!
			let fm = NSFileManager.defaultManager()
			let files = try fm.contentsOfDirectoryAtPath(oldDocumentsDirectory)
			DLog("Migrating DB files into group container from %@ to %@", oldDocumentsDirectory, newDocumentsDirectory)
			for file in files {
				if file.rangeOfString("Trailer.sqlite") != nil {
					DLog("Moving database file: %@",file)
					let oldPath = oldDocumentsDirectory.stringByAppendingPathComponent(file)
					let newPath = newDocumentsDirectory.stringByAppendingPathComponent(file)
					if fm.fileExistsAtPath(newPath) {
						try! fm.removeItemAtPath(newPath)
					}
					try! fm.moveItemAtPath(oldPath, toPath: newPath)
				}
			}
			try! fm.removeItemAtPath(oldDocumentsDirectory)
		} catch {
			/* No legacy directory */
		}
	}

	class func sendNotificationsIndexAndSave() {

		let allPrs = PullRequest.allItemsOfType("PullRequest", inMoc: mainObjectContext) as! [PullRequest]
		for p in allPrs {
			if p.isVisibleOnMenu {
				if !p.createdByMe {
					if !(p.isNewAssignment?.boolValue ?? false) && !(p.announced?.boolValue ?? false) {
						app.postNotificationOfType(.NewPr, forItem: p)
						p.announced = true
					}
					if let reopened = p.reopened?.boolValue where reopened == true {
						app.postNotificationOfType(.PrReopened, forItem: p)
						p.reopened = false
					}
					if let newAssignment = p.isNewAssignment?.boolValue where newAssignment == true {
						app.postNotificationOfType(.NewPrAssigned, forItem: p)
						p.isNewAssignment = false
					}
				}
				#if os(iOS)
					atNextEvent {
						p.indexForSpotlight()
					}
				#endif
			} else {
				atNextEvent {
					p.ensureInvisible()
				}
			}
		}

		let allIssues = Issue.allItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue]
		for i in allIssues {
			if i.isVisibleOnMenu {
				if !i.createdByMe {
					if !(i.isNewAssignment?.boolValue ?? false) && !(i.announced?.boolValue ?? false) {
						app.postNotificationOfType(.NewIssue, forItem: i)
						i.announced = true
					}
					if let reopened = i.reopened?.boolValue where reopened == true {
						app.postNotificationOfType(.IssueReopened, forItem: i)
						i.reopened = false
					}
					if let newAssignment = i.isNewAssignment?.boolValue where newAssignment == true {
						app.postNotificationOfType(.NewIssueAssigned, forItem: i)
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

		let latestComments = PRComment.newItemsOfType("PRComment", inMoc: mainObjectContext) as! [PRComment]
		for c in latestComments {
			c.processNotifications()
			c.postSyncAction = PostSyncAction.DoNothing.rawValue
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
							if pr.lastStatusNotified != displayText && pr.postSyncAction?.integerValue != PostSyncAction.NoteNew.rawValue {
								if pr.isSnoozing && Settings.snoozeWakeOnStatusUpdate {
									DLog("Waking up snoozed PR ID %@ because of a status update", pr.serverId)
									pr.wakeUp()
								}
								app.postNotificationOfType(.NewStatus, forItem: s)
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
			s.postSyncAction = PostSyncAction.DoNothing.rawValue
		}

		for p in allPrs {
			if p.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
				p.postSyncAction = PostSyncAction.DoNothing.rawValue
			}
		}

		for i in allIssues {
			if i.postSyncAction?.integerValue != PostSyncAction.DoNothing.rawValue {
				i.postSyncAction = PostSyncAction.DoNothing.rawValue
			}
		}

		DataManager.saveDB()
	}

	class func saveDB() -> Bool {
		if mainObjectContext.hasChanges {
			DLog("Saving DB")
			do {
				try mainObjectContext.save()
			} catch {
				DLog("Error while saving DB: %@", (error as NSError).localizedDescription)
			}
		}
		return true
	}

	class func tempContext() -> NSManagedObjectContext {
		let c = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
		c.mergePolicy = NSMergePolicy(mergeType: NSMergePolicyType.MergeByPropertyObjectTrumpMergePolicyType)
		c.parentContext = mainObjectContext
		c.undoManager = nil
		return c
	}

	class func infoForType(type: NotificationType, item: DataItem) -> [String : AnyObject] {
		switch type {
		case .NewMention, .NewComment:
			return [COMMENT_ID_KEY : item.objectID.URIRepresentation().absoluteString]
		case .NewPr, .PrReopened, .NewPrAssigned, .PrClosed, .PrMerged:
			return [NOTIFICATION_URL_KEY : (item as! PullRequest).webUrl!, PULL_REQUEST_ID_KEY: item.objectID.URIRepresentation().absoluteString]
		case .NewRepoSubscribed, .NewRepoAnnouncement:
			return [NOTIFICATION_URL_KEY : (item as! Repo).webUrl!]
		case .NewStatus:
			let pr = (item as! PRStatus).pullRequest
			return [NOTIFICATION_URL_KEY : pr.webUrl!, STATUS_ID_KEY: pr.objectID.URIRepresentation().absoluteString]
		case .NewIssue, .IssueReopened, .NewIssueAssigned, .IssueClosed:
			return [NOTIFICATION_URL_KEY : (item as! Issue).webUrl!, ISSUE_ID_KEY: item.objectID.URIRepresentation().absoluteString]
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

	class func idForUriPath(uriPath: String?) -> NSManagedObjectID? {
		if let up = uriPath, u = NSURL(string: up) {
			return persistentStoreCoordinator.managedObjectIDForURIRepresentation(u)
		}
		return nil
	}
}

///////////////////////////////////////

let mainObjectContext = { () -> NSManagedObjectContext in
	let m = NSManagedObjectContext(concurrencyType:NSManagedObjectContextConcurrencyType.MainQueueConcurrencyType)
	m.undoManager = nil
	m.persistentStoreCoordinator = persistentStoreCoordinator
	m.mergePolicy = NSMergePolicy(mergeType: NSMergePolicyType.MergeByPropertyObjectTrumpMergePolicyType)
	DLog("Database setup complete")
	return m
}()

var _justMigrated: Bool = false
let persistentStoreCoordinator = { ()-> NSPersistentStoreCoordinator in

	let dataDir = dataFilesDirectory()
	let sqlStorePath = dataDir.URLByAppendingPathComponent("Trailer.sqlite")
	let mom = NSManagedObjectModel(contentsOfURL: NSBundle.mainBundle().URLForResource("Trailer", withExtension: "momd")!)!

	let fileManager = NSFileManager.defaultManager()
	if fileManager.fileExistsAtPath(sqlStorePath.path!) {
		let m = try! NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(NSSQLiteStoreType, URL: sqlStorePath, options: nil)
		_justMigrated = !mom.isConfiguration(nil, compatibleWithStoreMetadata: m)
	} else {
		try! fileManager.createDirectoryAtPath(dataDir.path!, withIntermediateDirectories: true, attributes: nil)
	}

	var newCoordinator = NSPersistentStoreCoordinator(managedObjectModel:mom)
	if !addStorePath(sqlStorePath, newCoordinator: newCoordinator) {
		DLog("Failed to migrate/load DB store - will nuke it and retry")
		removeDatabaseFiles()

		newCoordinator = NSPersistentStoreCoordinator(managedObjectModel:mom)
		if !addStorePath(sqlStorePath, newCoordinator: newCoordinator) {
			DLog("Catastrophic failure, app is probably corrupted and needs reinstall")
			abort()
		}
	}
	return newCoordinator
}()

func dataFilesDirectory() -> NSURL {
	#if os(iOS)
		let sharedFiles = sharedFilesDirectory()
		DLog("Shared files in %@", sharedFiles)
		return sharedFiles
	#else
		return legacyFilesDirectory()
	#endif
}

private func legacyFilesDirectory() -> NSURL {
	let f = NSFileManager.defaultManager()
	var appSupportURL = f.URLsForDirectory(NSSearchPathDirectory.ApplicationSupportDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask).last! 
	appSupportURL = appSupportURL.URLByAppendingPathComponent("com.housetrip.Trailer")
	DLog("Files in %@", appSupportURL)
	return appSupportURL
}

func sharedFilesDirectory() -> NSURL {
	return NSFileManager.defaultManager().containerURLForSecurityApplicationGroupIdentifier("group.Trailer")!
}

private func addStorePath(sqlStore: NSURL, newCoordinator: NSPersistentStoreCoordinator) -> Bool {

	do {
		let storeOptions = [
			NSMigratePersistentStoresAutomaticallyOption: NSNumber(bool: true),
			NSInferMappingModelAutomaticallyOption: NSNumber(bool: true),
			NSSQLitePragmasOption: ["synchronous":"OFF", "fullfsync":"0"]]

		try newCoordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: sqlStore, options: storeOptions)
	} catch {
		DLog("Error while mounting DB store %@", (error as NSError).localizedDescription)
		return false
	}

	return true
}

func existingObjectWithID(id: NSManagedObjectID) -> NSManagedObject? {
	return try? mainObjectContext.existingObjectWithID(id)
}

func removeDatabaseFiles() {
	let fm = NSFileManager.defaultManager()
	let documentsDirectory = dataFilesDirectory().path!
	do {
		for file in try fm.contentsOfDirectoryAtPath(documentsDirectory) {
			if file.rangeOfString("Trailer.sqlite") != nil {
				DLog("Removing old database file: %@",file)
				try! fm.removeItemAtPath(documentsDirectory.stringByAppendingPathComponent(file))
			}
		}
	} catch { /* no directory */ }
}

////////////////////////////////
