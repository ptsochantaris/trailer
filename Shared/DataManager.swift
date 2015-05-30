
import CoreData
#if os(iOS)
	import UIKit
#endif

var dataReadonly = false

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

			var legacyApiPath = d.objectForKey("API_SERVER_PATH") as? String ?? ""

			var legacyWebHost = d.objectForKey("API_FRONTEND_SERVER") as? String ?? ""
			if legacyWebHost.isEmpty { legacyWebHost = "github.com" }

			var actualApiPath = (legacyApiHost + "/" + legacyApiPath).stringByReplacingOccurrencesOfString("//", withString:"/")

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
		for r in DataItem.allItemsOfType("Repo", inMoc:mainObjectContext) as! [Repo] {
			r.resetSyncState()
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
        let oldDocumentsDirectory = legacyFilesDirectory().path!
        let fm = NSFileManager.defaultManager()
        if fm.fileExistsAtPath(oldDocumentsDirectory) {
            DLog("Migrating DB files into group container")
            if let files = fm.contentsOfDirectoryAtPath(oldDocumentsDirectory, error: nil) as? [String] {
                let newDocumentsDirectory = sharedFilesDirectory().path!
                for file in files {
                    if file.rangeOfString("Trailer.sqlite") != nil {
                        DLog("Moving database file: %@",file)
                        let oldPath = oldDocumentsDirectory.stringByAppendingPathComponent(file)
                        let newPath = newDocumentsDirectory.stringByAppendingPathComponent(file)
                        if fm.fileExistsAtPath(newPath) {
                            fm.removeItemAtPath(newPath, error: nil)
                        }
                        fm.moveItemAtPath(oldPath, toPath: newPath, error: nil)
                    }
                }
            }
            fm.removeItemAtPath(oldDocumentsDirectory, error: nil)
        } else {
            DLog("No need to migrate DB into shared container")
        }
    }

	class func sendNotifications() {

		let newPrs = PullRequest.newItemsOfType("PullRequest", inMoc: mainObjectContext) as! [PullRequest]
		for p in newPrs {
			if !p.createdByMe() && !(p.isNewAssignment?.boolValue ?? false) && p.isVisibleOnMenu() {
				app.postNotificationOfType(PRNotificationType.NewPr, forItem: p)
			}
		}

		let updatedPrs = PullRequest.updatedItemsOfType("PullRequest", inMoc: mainObjectContext) as! [PullRequest]
		for p in updatedPrs {
			if let reopened = p.reopened?.boolValue where reopened == true {
				if !p.createdByMe() && p.isVisibleOnMenu() {
					app.postNotificationOfType(PRNotificationType.PrReopened, forItem: p)
				}
				p.reopened = false
			}
		}

		let newIssues = Issue.newItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue]
		for i in newIssues {
			if !i.createdByMe() && !(i.isNewAssignment?.boolValue ?? false) && i.isVisibleOnMenu() {
				app.postNotificationOfType(PRNotificationType.NewIssue, forItem: i)
			}
		}

		let updatedIssues = Issue.updatedItemsOfType("Issue", inMoc: mainObjectContext) as! [Issue]
		for i in updatedIssues {
			if let reopened = i.reopened?.boolValue where reopened == true {
				if !i.createdByMe() && i.isVisibleOnMenu() {
					app.postNotificationOfType(PRNotificationType.IssueReopened, forItem: i)
				}
				i.reopened = false
			}
		}

		let allTouchedPrs = newPrs + updatedPrs
		for p in allTouchedPrs {
			if let newAssignment = p.isNewAssignment?.boolValue where newAssignment == true {
				app.postNotificationOfType(PRNotificationType.NewPrAssigned, forItem: p)
				p.isNewAssignment = false
			}
		}

		let allTouchedIssues = newIssues + updatedIssues
		for i in allTouchedIssues {
			if let newAssignment = i.isNewAssignment?.boolValue where newAssignment == true {
				app.postNotificationOfType(PRNotificationType.NewIssueAssigned, forItem: i)
				i.isNewAssignment = false
			}
		}

		var latestComments = PRComment.newItemsOfType("PRComment", inMoc: mainObjectContext) as! [PRComment]
		for c in latestComments {
			if let i = c.pullRequest ?? c.issue {
				processNotificationsForComment(c, ofItem: c.pullRequest ?? i)
			}
			c.postSyncAction = PostSyncAction.DoNothing.rawValue
		}

		var latestStatuses = PRStatus.newItemsOfType("PRStatus", inMoc: mainObjectContext) as! [PRStatus]
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

		for p in allTouchedPrs {
			p.postSyncAction = PostSyncAction.DoNothing.rawValue
		}

		for i in allTouchedIssues {
			i.postSyncAction = PostSyncAction.DoNothing.rawValue
		}
	}

	class func processNotificationsForComment(c: PRComment, ofItem: ListableItem) {
		if ofItem.postSyncAction?.integerValue == PostSyncAction.NoteUpdated.rawValue && ofItem.isVisibleOnMenu() {
			if c.refersToMe() {
				app.postNotificationOfType(PRNotificationType.NewMention, forItem: c)
			} else if !Settings.disableAllCommentNotifications && ofItem.showNewComments() && !c.isMine() {
				notifyNewComment(c)
			}
		}
	}

	class func notifyNewComment(c: PRComment) {
		if let authorName = c.userName {
			var blocked = false
			for blockedAuthor in Settings.commentAuthorBlacklist as [String] {
				if authorName.compare(blockedAuthor, options: NSStringCompareOptions.CaseInsensitiveSearch|NSStringCompareOptions.DiacriticInsensitiveSearch)==NSComparisonResult.OrderedSame {
					blocked = true
					break
				}
			}
			if blocked {
				DLog("Blocked notification for user '%@' as their name is on the blacklist",authorName)
			} else {
				DLog("User '%@' not on blacklist, can post notification",authorName)
				app.postNotificationOfType(PRNotificationType.NewComment, forItem:c)
			}
		}
	}

	class func saveDB() -> Bool {
		if mainObjectContext.hasChanges {
			DLog("Saving DB")
			var error: NSError?
			var ok = mainObjectContext.save(&error)
			if !ok { DLog("Error while saving DB: %@", error) }
		}
		return true
	}

	class func tempContext() -> NSManagedObjectContext {
		let c = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.ConfinementConcurrencyType)
		c.parentContext = mainObjectContext
		c.undoManager = nil
		return c
	}

	class func infoForType(type: PRNotificationType, item: DataItem) -> [String : AnyObject] {
		switch type {
		case .NewMention: fallthrough
		case .NewComment:
			return [COMMENT_ID_KEY : item.objectID.URIRepresentation().absoluteString!]
		case .NewPr: fallthrough
		case .PrReopened: fallthrough
		case .NewPrAssigned: fallthrough
		case .PrClosed: fallthrough
		case .PrMerged:
			return [NOTIFICATION_URL_KEY : (item as! PullRequest).webUrl!, PULL_REQUEST_ID_KEY: item.objectID.URIRepresentation().absoluteString!]
		case .NewRepoSubscribed: fallthrough
		case .NewRepoAnnouncement:
			return [NOTIFICATION_URL_KEY : (item as! Repo).webUrl!]
		case .NewStatus:
			let pr = (item as! PRStatus).pullRequest
			return [NOTIFICATION_URL_KEY : pr.webUrl!, STATUS_ID_KEY: item.objectID.URIRepresentation().absoluteString!]
		case .NewIssue: fallthrough
		case .IssueReopened: fallthrough
		case .NewIssueAssigned: fallthrough
		case .IssueClosed:
			return [NOTIFICATION_URL_KEY : (item as! Issue).webUrl!, ISSUE_ID_KEY: item.objectID.URIRepresentation().absoluteString!]
		}
	}

	class func postMigrationTasks() {
		if _justMigrated {
			DLog("FORCING ALL PRS TO BE REFETCHED")
			for p in DataItem.allItemsOfType("PullRequest", inMoc:mainObjectContext) as! [PullRequest] {
				p.resetSyncState()
			}
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
		} else if !Repo.interestedInPrs() && !Repo.interestedInIssues() {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs for some of them."
		} else if Repo.countVisibleReposInMoc(mainObjectContext)==0 {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "You have no watched repositories, please add some to your watchlist and refresh in a little while."
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
		} else if !Repo.interestedInPrs() && !Repo.interestedInIssues() {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "All your watched repositories are marked as hidden, please enable issues or PRs for some of them."
		} else if Repo.countVisibleReposInMoc(mainObjectContext)==0 {
			color = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "You have no watched repositories, please add some to your watchlist and refresh in a little while."
		} else if openIssues==0 {
			message = "No open issues in your configured repositories."
		}

		return emptyMessage(message, color: color)
	}

	class func emptyMessage(message: String, color: COLOR_CLASS) -> NSAttributedString {
		let p = NSMutableParagraphStyle()
		p.lineBreakMode = NSLineBreakMode.ByWordWrapping
		#if os(OSX)
			p.alignment = NSTextAlignment.CenterTextAlignment
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
			return persistentStoreCoordinator()!.managedObjectIDForURIRepresentation(u)
		}
		return nil
	}
}

///////////////////////////////////////

let mainObjectContext = buildMainContext()
var _persistentStoreCoordinator: NSPersistentStoreCoordinator?
var _justMigrated: Bool = false

func buildMainContext() -> NSManagedObjectContext {

	if let coordinator = persistentStoreCoordinator() {
		let m = NSManagedObjectContext(concurrencyType:NSManagedObjectContextConcurrencyType.MainQueueConcurrencyType)
		m.undoManager = nil
		m.persistentStoreCoordinator = coordinator
		if dataReadonly==true {
			m.stalenessInterval = 0.0
		}
		DLog("Database setup complete")
		return m
	} else {
		let fm = NSFileManager.defaultManager()
		let url = applicationFilesDirectory().URLByAppendingPathComponent("Trailer.storedata")
		fm.removeItemAtURL(url, error: nil)
		return buildMainContext()
	}
}

func persistentStoreCoordinator() -> NSPersistentStoreCoordinator? {

	if let p = _persistentStoreCoordinator { return p }

	let modelURL = NSBundle.mainBundle().URLForResource("Trailer", withExtension: "momd")!
	let mom = NSManagedObjectModel(contentsOfURL: modelURL)!
	_persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel:mom)
	let fileManager = NSFileManager.defaultManager()
	let applicationDirectory = applicationFilesDirectory()

	var error:NSError?
	let properties = applicationDirectory.resourceValuesForKeys([NSURLIsDirectoryKey], error:&error)
	if properties != nil && properties!.count > 0 {
		let isDir = properties![NSURLIsDirectoryKey] as! NSNumber
		if !isDir.boolValue {
			let description = "Expected a folder to store application data, found a file (\(applicationDirectory.path))."
			error = NSError(domain: "TRAILER_DB_ERROR", code: 101, userInfo: [NSLocalizedDescriptionKey:description])
			DLog("%@", error)
			return nil
		}
	} else {
		var ok = false
		if error != nil && error!.code == NSFileReadNoSuchFileError {
			ok = fileManager.createDirectoryAtURL(applicationDirectory, withIntermediateDirectories: true, attributes: nil, error: &error)
		}
		if !ok {
			DLog("%@", error)
			return nil
		}
	}

	let sqlStorePath = applicationDirectory.URLByAppendingPathComponent("Trailer.sqlite")
	let m = NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(NSSQLiteStoreType, URL: sqlStorePath, error: &error)
	_justMigrated = !mom.isConfiguration(nil, compatibleWithStoreMetadata: m)
	if !addStorePath(sqlStorePath) {
		DLog("Failed to migrate/load DB store - will nuke it and retry")
		removeDatabaseFiles()
		if !addStorePath(sqlStorePath) {
			DLog("Catastrophic failure, app is probably corrupted and needs reinstall")
			abort()
		}
	}
	return _persistentStoreCoordinator
}

func applicationFilesDirectory() -> NSURL {
    #if os(iOS)
        return sharedFilesDirectory()
    #else
        return legacyFilesDirectory()
    #endif
}

private func legacyFilesDirectory() -> NSURL {
	let f = NSFileManager.defaultManager()
	var appSupportURL = f.URLsForDirectory(NSSearchPathDirectory.ApplicationSupportDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask).last! as! NSURL
	appSupportURL = appSupportURL.URLByAppendingPathComponent("com.housetrip.Trailer")
	DLog("Files in %@", appSupportURL)
	return appSupportURL
}

private func sharedFilesDirectory() -> NSURL {
    var appSupportURL = NSFileManager.defaultManager().containerURLForSecurityApplicationGroupIdentifier("group.Trailer")!
    DLog("Shared files in %@", appSupportURL)
    return appSupportURL
}

func addStorePath(sqlStore: NSURL) -> Bool {
	var error:NSError?

	if dataReadonly {
		if NSFileManager.defaultManager().fileExistsAtPath(sqlStore.path!) { // may need migration

			if let m = NSPersistentStoreCoordinator.metadataForPersistentStoreOfType(NSSQLiteStoreType, URL: sqlStore, error: nil)
				where _persistentStoreCoordinator?.managedObjectModel.isConfiguration(nil, compatibleWithStoreMetadata: m) == false {

					let tempStore = _persistentStoreCoordinator?.addPersistentStoreWithType(NSSQLiteStoreType,
						configuration: nil,
						URL: sqlStore,
						options: [
							NSMigratePersistentStoresAutomaticallyOption: true,
							NSInferMappingModelAutomaticallyOption: true],
						error: &error)
					if error != nil || tempStore == nil {
						DLog("Error while migrating DB store before mounting readonly %@", error)
						return false
					} else {
						_persistentStoreCoordinator?.removePersistentStore(tempStore!, error: &error)
						if error != nil {
							DLog("Error while unmounting newly migrated DB store before mounting readonly %@",error)
							return false
						}
					}
			}
		} else { // may need creating

			let tempStore = _persistentStoreCoordinator?.addPersistentStoreWithType(NSSQLiteStoreType,
				configuration: nil,
				URL: sqlStore,
				options: nil,
				error: &error)
			if error != nil || tempStore == nil {
				DLog("Error while creating DB store before mounting readonly %@", error)
				return false
			} else {
				_persistentStoreCoordinator?.removePersistentStore(tempStore!, error: &error)
				if error != nil {
					DLog("Error while unmounting newly created DB store before mounting readonly %@",error)
					return false
				}
			}
		}
	}

	let store = _persistentStoreCoordinator!.addPersistentStoreWithType(NSSQLiteStoreType,
		configuration: nil,
		URL: sqlStore,
		options: [
			NSMigratePersistentStoresAutomaticallyOption: true,
			NSInferMappingModelAutomaticallyOption: true,
            NSReadOnlyPersistentStoreOption: dataReadonly,
			NSSQLitePragmasOption: ["synchronous":"OFF", "fullfsync":"0"]],
		error: &error)

	if error != nil { DLog("Error while mounting DB store %@",error) }

	return store != nil
}

func removeDatabaseFiles() {
	let fm = NSFileManager.defaultManager()
	let documentsDirectory = applicationFilesDirectory().path!
	if let files = fm.contentsOfDirectoryAtPath(documentsDirectory, error: nil) as? [String] {
		for file in files {
			if file.rangeOfString("Trailer.sqlite") != nil {
				DLog("Removing old database file: %@",file)
				fm.removeItemAtPath(documentsDirectory.stringByAppendingPathComponent(file), error:nil)
			}
		}
	}
}

////////////////////////////////
