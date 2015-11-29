
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
			var legacyApiHost = d.objectForKey("API_BACKEND_SERVER") as? String ?? ""
			if legacyApiHost.isEmpty { legacyApiHost = "api.github.com" }

			let legacyApiPath = d.objectForKey("API_SERVER_PATH") as? String ?? ""

			var legacyWebHost = d.objectForKey("API_FRONTEND_SERVER") as? String ?? ""
			if legacyWebHost.isEmpty { legacyWebHost = "github.com" }

			let actualApiPath = (legacyApiHost + "/" + legacyApiPath).stringByReplacingOccurrencesOfString("//", withString:"/")

			let newApiServer = ApiServer.addDefaultGithubInMoc(mainObjectContext)
			newApiServer.apiPath = "https://" + actualApiPath
			newApiServer.webPath = "https://" + legacyWebHost
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

		DLog("Marking all unspecified (nil) anounced flags as announced")
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
			if p.isVisibleOnMenu() {
				if !p.createdByMe() {
					if !(p.isNewAssignment?.boolValue ?? false) && !(p.announced?.boolValue ?? false) {
						app.postNotificationOfType(PRNotificationType.NewPr, forItem: p)
						p.announced = true
					}
					if let reopened = p.reopened?.boolValue where reopened == true {
						app.postNotificationOfType(PRNotificationType.PrReopened, forItem: p)
						p.reopened = false
					}
					if let newAssignment = p.isNewAssignment?.boolValue where newAssignment == true {
						app.postNotificationOfType(PRNotificationType.NewPrAssigned, forItem: p)
						p.isNewAssignment = false
					}
				}
				#if os(iOS)
					NSOperationQueue.mainQueue().addOperationWithBlock {
						p.indexForSpotlight()
					}
				#endif
			} else {
				#if os(iOS)
					NSOperationQueue.mainQueue().addOperationWithBlock {
						p.deIndexFromSpotlight()
					}
				#endif
			}
		}

		let allIssues = Issue.allItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue]
		for i in allIssues {
			if i.isVisibleOnMenu() {
				if !i.createdByMe() {
					if !(i.isNewAssignment?.boolValue ?? false) && !(i.announced?.boolValue ?? false) {
						app.postNotificationOfType(PRNotificationType.NewIssue, forItem: i)
						i.announced = true
					}
					if let reopened = i.reopened?.boolValue where reopened == true {
						app.postNotificationOfType(PRNotificationType.IssueReopened, forItem: i)
						i.reopened = false
					}
					if let newAssignment = i.isNewAssignment?.boolValue where newAssignment == true {
						app.postNotificationOfType(PRNotificationType.NewIssueAssigned, forItem: i)
						i.isNewAssignment = false
					}
				}
				#if os(iOS)
					NSOperationQueue.mainQueue().addOperationWithBlock {
						i.indexForSpotlight()
					}
				#endif
			} else {
				#if os(iOS)
					NSOperationQueue.mainQueue().addOperationWithBlock {
						i.deIndexFromSpotlight()
					}
				#endif
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
				if pr.isVisibleOnMenu() && (Settings.notifyOnStatusUpdatesForAllPrs || pr.createdByMe() || pr.assignedToParticipated() || pr.assignedToMySection()) {
					if !coveredPrs.contains(pr.objectID) {
						coveredPrs.insert(pr.objectID)
						if let s = pr.displayedStatuses().first {
							let displayText = s.descriptionText
							if pr.lastStatusNotified != displayText && pr.postSyncAction?.integerValue != PostSyncAction.NoteNew.rawValue {
								app.postNotificationOfType(PRNotificationType.NewStatus, forItem: s)
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
		c.parentContext = mainObjectContext
		c.undoManager = nil
		return c
	}

	class func infoForType(type: PRNotificationType, item: DataItem) -> [String : AnyObject] {
		switch type {
		case .NewMention: fallthrough
		case .NewComment:
			return [COMMENT_ID_KEY : item.objectID.URIRepresentation().absoluteString]
		case .NewPr: fallthrough
		case .PrReopened: fallthrough
		case .NewPrAssigned: fallthrough
		case .PrClosed: fallthrough
		case .PrMerged:
			return [NOTIFICATION_URL_KEY : (item as! PullRequest).webUrl!, PULL_REQUEST_ID_KEY: item.objectID.URIRepresentation().absoluteString]
		case .NewRepoSubscribed: fallthrough
		case .NewRepoAnnouncement:
			return [NOTIFICATION_URL_KEY : (item as! Repo).webUrl!]
		case .NewStatus:
			let pr = (item as! PRStatus).pullRequest
			return [NOTIFICATION_URL_KEY : pr.webUrl!, STATUS_ID_KEY: pr.objectID.URIRepresentation().absoluteString]
		case .NewIssue: fallthrough
		case .IssueReopened: fallthrough
		case .NewIssueAssigned: fallthrough
		case .IssueClosed:
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

	class func reasonForEmptyWithFilter(filterValue: String?) -> NSAttributedString {
		let openRequests = PullRequest.countOpenRequestsInMoc(mainObjectContext)

		var color = COLOR_CLASS.lightGrayColor()
		var message: String = ""

		if !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
		} else if app.isRefreshing {
			message = "Refreshing PR information, please wait a moment..."
		} else if !(filterValue ?? "").isEmpty {
			message = "There are no PRs matching this filter."
		} else if openRequests > 0 {
			message = "\(openRequests) PRs are hidden by your settings."
		} else if Repo.countVisibleReposInMoc(mainObjectContext)==0 {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "You have no watched repositories, please add some to your watchlist and refresh after a little while."
		} else if !Repo.interestedInPrs() && !Repo.interestedInIssues() {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs for some of them."
		} else if openRequests==0 {
			message = "No open PRs in your configured repositories."
		}

		return emptyMessage(message, color: color)
	}

	class func reasonForEmptyIssuesWithFilter(filterValue: String?) -> NSAttributedString {
		let openIssues = Issue.countOpenIssuesInMoc(mainObjectContext)

		var color = COLOR_CLASS.lightGrayColor()
		var message: String = ""

		if !ApiServer.someServersHaveAuthTokensInMoc(mainObjectContext) {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
		} else if app.isRefreshing {
			message = "Refreshing issue information, please wait a moment..."
		} else if !(filterValue ?? "").isEmpty {
			message = "There are no issues matching this filter."
		} else if openIssues > 0 {
			message = "\(openIssues) issues are hidden by your settings."
		} else if Repo.countVisibleReposInMoc(mainObjectContext)==0 {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "You have no watched repositories, please add some to your watchlist and refresh after a little while."
		} else if !Repo.interestedInPrs() && !Repo.interestedInIssues() {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs for some of them."
		} else if openIssues==0 {
			message = "No open issues in your configured repositories."
		}

		return emptyMessage(message, color: color)
	}

	class func emptyMessage(message: String, color: COLOR_CLASS) -> NSAttributedString {
		let p = NSMutableParagraphStyle()
		p.lineBreakMode = NSLineBreakMode.ByWordWrapping
		#if os(OSX)
			p.alignment = NSTextAlignment.Center
			return NSAttributedString(string: message,
			attributes: [NSForegroundColorAttributeName: color, NSParagraphStyleAttributeName: p])
		#elseif os(iOS)
			p.alignment = NSTextAlignment.Center
			return NSAttributedString(string: message, attributes: [
				NSForegroundColorAttributeName: color,
				NSParagraphStyleAttributeName: p,
				NSFontAttributeName: FONT_CLASS.systemFontOfSize(FONT_CLASS.smallSystemFontSize())
			])
		#endif
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
	do {
		return try mainObjectContext.existingObjectWithID(id)
	} catch {
		return nil
	}
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
