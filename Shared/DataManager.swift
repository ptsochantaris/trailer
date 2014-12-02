
class DataManager : NSObject {
	let managedObjectContext = buildMainContext()

	override init() {
		super.init()
		if versionBumpOccured() {
			DLog("VERSION UPDATE MAINTENANCE NEEDED")
			performVersionChangedTasks()
			versionBumpComplete()
		} else {
			ApiServer.ensureAtLeastGithubInMoc(managedObjectContext)
		}
	}

	func performVersionChangedTasks() {
		let d = NSUserDefaults.standardUserDefaults()
		if let legacyAuthToken = d.objectForKey("GITHUB_AUTH_TOKEN") as String? {
			var legacyApiHost = d.objectForKey("API_BACKEND_SERVER") as String?
			if(legacyApiHost == nil || legacyApiHost?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0) {
				legacyApiHost = "api.github.com"
			}

			var legacyApiPath = d.objectForKey("API_SERVER_PATH") as String?
			if(legacyApiPath == nil || legacyApiPath?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0) {
				legacyApiPath = ""
			}

			var legacyWebHost = d.objectForKey("API_FRONTEND_SERVER") as String?
			if(legacyWebHost == nil || legacyWebHost?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) == 0) {
				legacyWebHost = "github.com"
			}

			var actualApiPath = legacyApiHost! + "/" + legacyApiPath!
			actualApiPath = actualApiPath.stringByReplacingOccurrencesOfString("//", withString:"/")

			let newApiServer = ApiServer.addDefaultGithubInMoc(managedObjectContext)
			newApiServer.apiPath = "https://".stringByAppendingString(actualApiPath)
			newApiServer.webPath = "https://".stringByAppendingString(legacyWebHost!)
			newApiServer.authToken = legacyAuthToken
			newApiServer.lastSyncSucceeded = true

			d.removeObjectForKey("API_BACKEND_SERVER")
			d.removeObjectForKey("API_SERVER_PATH")
			d.removeObjectForKey("API_FRONTEND_SERVER")
			d.removeObjectForKey("GITHUB_AUTH_TOKEN")
		} else {
			ApiServer.ensureAtLeastGithubInMoc(managedObjectContext)
		}

		DLog("Marking all repos as dirty")
		for r in Repo.allItemsOfType("Repo", inMoc:managedObjectContext) as [Repo] {
			r.dirty = true
			r.lastDirtied = NSDate()
		}
	}

	func sendNotifications() {

		let newPrs = PullRequest.newItemsOfType("PullRequest", inMoc: managedObjectContext) as [PullRequest]
		for p in newPrs {
			if !p.isMine() {
				app.postNotificationOfType(PRNotificationType.NewPr, forItem: p)
			}
		}

		let updatedPrs = PullRequest.updatedItemsOfType("PullRequest", inMoc: managedObjectContext) as [PullRequest]
		for p in updatedPrs {
			if let reopened = p.reopened?.boolValue {
				if reopened {
					if !p.isMine() {
						app.postNotificationOfType(PRNotificationType.PrReopened, forItem: p)
					}
					p.reopened = false
				}
			}
		}

		let allTouchedPrs = newPrs + updatedPrs
		for p in allTouchedPrs {
			if let newAssignment = p.isNewAssignment?.boolValue {
				if newAssignment {
					app.postNotificationOfType(PRNotificationType.NewPrAssigned, forItem: p)
					p.isNewAssignment = false
				}
			}
		}

		var latestComments = PRComment.newItemsOfType("PRComment", inMoc: managedObjectContext) as [PRComment]
		for c in latestComments {
			let p = c.pullRequest
			if p.postSyncAction?.integerValue == PostSyncAction.NoteUpdated.rawValue {
				if c.refersToMe() {
					app.postNotificationOfType(PRNotificationType.NewMention, forItem: c)
				} else if (Settings.showCommentsEverywhere || p.isMine() || p.commentedByMe()) && !c.isMine() {
					if let authorName = c.userName {
						var blocked = false
						for blockedAuthor in Settings.commentAuthorBlacklist as [String] {
							if authorName.compare(blockedAuthor, options: NSStringCompareOptions.CaseInsensitiveSearch|NSStringCompareOptions.DiacriticInsensitiveSearch)==NSComparisonResult.OrderedSame {
								blocked = true
								break;
							}
						}
						if blocked {
							DLog("Blocked notification for user '%@' as their name is on the blacklist",authorName);
						} else {
							DLog("user '%@' not on blacklist, can post notification",authorName);
							app.postNotificationOfType(PRNotificationType.NewComment, forItem:c)
						}
					}
				}
			}
			c.postSyncAction = PostSyncAction.DoNothing.rawValue
		}

		for p in allTouchedPrs {
			p.postSyncAction = PostSyncAction.DoNothing.rawValue
		}
	}

	func saveDB() -> Bool {
		if managedObjectContext.hasChanges {
			DLog("Saving DB")
			return managedObjectContext.save(nil)
		}
		return true
	}

	func tempContext() -> NSManagedObjectContext {
		let c = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.ConfinementConcurrencyType)
		c.parentContext = managedObjectContext
		c.undoManager = nil
		return c
	}

	func deleteEverything() {
		autoreleasepool {
			let tempMoc = self.tempContext()
			for entity in managedObjectModel().entities {
				if let name = entity.name {
					if name != "ApiServer" {
						autoreleasepool {
							let f = NSFetchRequest(entityName: name)
							f.includesPropertyValues = false;
							f.includesSubentities = false;
							for o in tempMoc.executeFetchRequest(f, error:nil) as [NSManagedObject] {
								tempMoc.deleteObject(o)
							}
						}
					}
				}
			}
			tempMoc.save(nil)
		}
		saveDB()
	}

	func infoForType(type: PRNotificationType, item: NSManagedObject) -> Dictionary<String, AnyObject> {
		switch type {
		case .NewMention: fallthrough
		case .NewComment:
			return [COMMENT_ID_KEY : item.objectID.URIRepresentation().absoluteString!]
		case .NewPr: fallthrough
		case .PrReopened: fallthrough
		case .NewPrAssigned:
			return [PULL_REQUEST_ID_KEY : item.objectID.URIRepresentation().absoluteString!]
		case .PrClosed: fallthrough
		case .PrMerged:
			return [NOTIFICATION_URL_KEY : (item as PullRequest).webUrl!, PULL_REQUEST_ID_KEY: item.objectID.URIRepresentation().absoluteString!]
		case .NewRepoSubscribed: fallthrough
		case .NewRepoAnnouncement:
			return [NOTIFICATION_URL_KEY : (item as PullRequest).webUrl!]
		default:
			break
		}
	}

	func postMigrationTasks() {
		if _justMigrated {
			DLog("FORCING ALL PRS TO BE REFETCHED")
			for p in PullRequest.allItemsOfType("PullRequest", inMoc:managedObjectContext) as [PullRequest] {
				p.updatedAt = NSDate.distantPast() as? NSDate
			}
			_justMigrated = false
		}
	}

	func postProcessAllPrs() {
		for p in PullRequest.allItemsOfType("PullRequest", inMoc:managedObjectContext) as [PullRequest] {
			p.postProcess()
		}
	}

	func reasonForEmptyWithFilter(filterValue: String?) -> NSAttributedString {
		let openRequests = PullRequest.countOpenRequestsInMoc(managedObjectContext)

		var messageColor = COLOR_CLASS.lightGrayColor()
		var message: String = ""

		if !ApiServer.someServersHaveAuthTokensInMoc(managedObjectContext) {
			messageColor = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "There are no configured API servers in your settings, please ensure you have added at least one server with a valid API token."
		} else if app.isRefreshing {
			message = "Refreshing PR information, please wait a moment..."
		} else if filterValue != nil && filterValue?.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 0 {
			message = "There are no PRs matching this filter."
		} else if openRequests > 0 {
			message = "\(openRequests) PRs are hidden by your Settings."
		} else if Repo.countVisibleReposInMoc(managedObjectContext)==0 {
			messageColor = MAKECOLOR(0.8, 0.0, 0.0, 1.0)
			message = "There are no watched repositories, please watch or unhide some."
		} else if openRequests==0 {
			message = "There are no open PRs for your selected repositories."
		}

		let p = NSMutableParagraphStyle()
		p.lineBreakMode = NSLineBreakMode.ByWordWrapping
		#if os(OSX)
			p.alignment = NSTextAlignment.CenterTextAlignment;
			return NSAttributedString(string: message,
				attributes: [NSForegroundColorAttributeName: messageColor, NSParagraphStyleAttributeName: p])
			#elseif os(iOS)
			p.alignment = NSTextAlignment.Center;
			return NSAttributedString(string: message,
			attributes: [	NSForegroundColorAttributeName: messageColor,
			NSParagraphStyleAttributeName: p,
			NSFontAttributeName: FONT_CLASS.systemFontOfSize(FONT_CLASS.smallSystemFontSize())])
		#endif

	}

	func idForUriPath(uriPath: String?) -> NSManagedObjectID? {
		if uriPath == nil { return nil }
		let u = NSURL(string: uriPath!)
		return persistentStoreCoordinator()!.managedObjectIDForURIRepresentation(u!)
	}

	func versionBumpComplete() {
		let d = NSUserDefaults.standardUserDefaults()
		d.setObject(app.currentAppVersion, forKey: "LAST_RUN_VERSION_KEY")
		d.synchronize()
	}

	func versionBumpOccured() -> Bool {
		let d = NSUserDefaults.standardUserDefaults()
		if let thisVersion = d.objectForKey("LAST_RUN_VERSION_KEY") as? String {
			return !(thisVersion == app.currentAppVersion)
		} else {
			return true
		}
	}
}

///////////////////////////////////////

var _managedObjectModel: NSManagedObjectModel?
var _persistentStoreCoordinator: NSPersistentStoreCoordinator?
var _justMigrated: Bool = false

func buildMainContext() -> NSManagedObjectContext {

	if let coordinator = persistentStoreCoordinator() {
		let m = NSManagedObjectContext(concurrencyType:NSManagedObjectContextConcurrencyType.MainQueueConcurrencyType)
		m.undoManager = nil;
		m.persistentStoreCoordinator = coordinator
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

	let mom = managedObjectModel()
	_persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel:mom)
	let fileManager = NSFileManager.defaultManager()
	let applicationDirectory = applicationFilesDirectory()

	var error:NSError?
	let properties = applicationDirectory.resourceValuesForKeys([NSURLIsDirectoryKey], error:&error)
	if(properties != nil && properties!.count > 0) {
		let isDir = properties![NSURLIsDirectoryKey] as NSNumber
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
		DLog("Failed to migrate/load DB store - will nuke it and retry");
		removeDatabaseFiles()
		if !addStorePath(sqlStorePath) {
			DLog("Catastrophic failure, app is probably corrupted and needs reinstall")
			abort()
		}
	}
	return _persistentStoreCoordinator
}

func applicationFilesDirectory() -> NSURL {
	let f = NSFileManager.defaultManager()
	var appSupportURL = f.URLsForDirectory(NSSearchPathDirectory.ApplicationSupportDirectory, inDomains: NSSearchPathDomainMask.UserDomainMask).last! as NSURL
	appSupportURL = appSupportURL.URLByAppendingPathComponent("com.housetrip.Trailer")
	DLog("Files in %@", appSupportURL)
	return appSupportURL
}

func managedObjectModel() -> NSManagedObjectModel {
	if let m = _managedObjectModel { return m }
	let modelURL = NSBundle.mainBundle().URLForResource("Trailer", withExtension: "momd")!
	_managedObjectModel = NSManagedObjectModel(contentsOfURL: modelURL)
	return _managedObjectModel!
}

func addStorePath(sqlStore: NSURL) -> Bool {
	var error:NSError?
	let store = _persistentStoreCoordinator!.addPersistentStoreWithType(NSSQLiteStoreType,
		configuration:nil,
		URL:sqlStore,
		options:[
			NSMigratePersistentStoresAutomaticallyOption:true,
			NSInferMappingModelAutomaticallyOption:true,
			NSSQLitePragmasOption:["synchronous":"OFF", "fullfsync":"0"]],
		error:&error)
	if(error != nil) { DLog("%@",error) }
	return store != nil
}

func removeDatabaseFiles() {
	let fm = NSFileManager.defaultManager()
	let documentsDirectory = applicationFilesDirectory().path!
	if let files = fm.contentsOfDirectoryAtPath(documentsDirectory, error: nil) as? [String] {
		for file in files {
			if file.rangeOfString("Trailer.sqlite") != nil {
				DLog("Removing old database file: %@",file);
				fm.removeItemAtPath(documentsDirectory.stringByAppendingPathComponent(file), error:nil)
			}
		}
	}
}

////////////////////////////////
