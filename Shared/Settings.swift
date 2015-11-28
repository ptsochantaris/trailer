
#if os(iOS)
	import UIKit
#endif

final class PopTimer : NSObject {

	var _popTimer: NSTimer?
	let _timeInterval: NSTimeInterval
	let _callback: ()->()

	var isRunning: Bool {
		return _popTimer != nil
	}

	func push() {
		_popTimer?.invalidate()
		_popTimer = NSTimer.scheduledTimerWithTimeInterval(_timeInterval, target: self, selector: Selector("popped"), userInfo: nil, repeats: false)
	}

	func popped() {
		invalidate()
		_callback()
	}

	func invalidate() {
		_popTimer?.invalidate()
		_popTimer = nil
	}

	init(timeInterval: NSTimeInterval, callback: Completion) {
		_timeInterval = timeInterval
		_callback = callback
		super.init()
	}
}

/////////////////////////////

let SETTINGS_EXPORTED = "SETTINGS_EXPORTED"

var _settings_valuesCache = [String : AnyObject]()
let _settings_shared = NSUserDefaults(suiteName: "group.Trailer")!

final class Settings {

	class func allFields() -> [String] {
		return [
			"SORT_METHOD_KEY", "STATUS_FILTERING_METHOD_KEY", "LAST_PREFS_TAB_SELECTED", "CLOSE_HANDLING_POLICY", "MERGE_HANDLING_POLICY", "STATUS_ITEM_REFRESH_COUNT", "LABEL_REFRESH_COUNT", "UPDATE_CHECK_INTERVAL_KEY",
			"STATUS_FILTERING_TERMS_KEY", "COMMENT_AUTHOR_BLACKLIST", "HOTKEY_LETTER", "REFRESH_PERIOD_KEY", "IOS_BACKGROUND_REFRESH_PERIOD_KEY", "NEW_REPO_CHECK_PERIOD", "LAST_SUCCESSFUL_REFRESH",
			"LAST_RUN_VERSION_KEY", "UPDATE_CHECK_AUTO_KEY", "HIDE_UNCOMMENTED_PRS_KEY", "SHOW_COMMENTS_EVERYWHERE_KEY", "SORT_ORDER_KEY", "SHOW_UPDATED_KEY", "DONT_KEEP_MY_PRS_KEY", "HIDE_AVATARS_KEY",
			"AUTO_PARTICIPATE_IN_MENTIONS_KEY", "DONT_ASK_BEFORE_WIPING_MERGED", "DONT_ASK_BEFORE_WIPING_CLOSED", "HIDE_NEW_REPOS_KEY", "GROUP_BY_REPO", "HIDE_ALL_SECTION", "SHOW_LABELS", "SHOW_STATUS_ITEMS",
			"MAKE_STATUS_ITEMS_SELECTABLE", "MOVE_ASSIGNED_PRS_TO_MY_SECTION", "MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY", "COUNT_ONLY_LISTED_PRS", "OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY", "LOG_ACTIVITY_TO_CONSOLE_KEY",
			"HOTKEY_ENABLE", "HOTKEY_CONTROL_MODIFIER", "USE_VIBRANCY_UI", "DISABLE_ALL_COMMENT_NOTIFICATIONS", "NOTIFY_ON_STATUS_UPDATES", "NOTIFY_ON_STATUS_UPDATES_ALL", "SHOW_REPOS_IN_NAME", "INCLUDE_REPOS_IN_FILTER",
			"INCLUDE_LABELS_IN_FILTER", "INCLUDE_STATUSES_IN_FILTER", "HOTKEY_COMMAND_MODIFIER", "HOTKEY_OPTION_MODIFIER", "HOTKEY_SHIFT_MODIFIER", "GRAY_OUT_WHEN_REFRESHING", "SHOW_ISSUES_MENU",
			"AUTO_PARTICIPATE_ON_TEAM_MENTIONS", "SHOW_ISSUES_IN_WATCH_GLANCE", "ASSIGNED_PR_HANDLING_POLICY", "HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW", "AUTO_REPEAT_SETTINGS_EXPORT", "DONT_CONFIRM_SETTINGS_IMPORT",
			"LAST_EXPORT_URL", "LAST_EXPORT_TIME", "CLOSE_HANDLING_POLICY_2", "MERGE_HANDLING_POLICY_2", "LAST_PREFS_TAB_SELECTED_OSX", "NEW_PR_DISPLAY_POLICY_INDEX", "NEW_ISSUE_DISPLAY_POLICY_INDEX",
            "INCLUDE_SERVERS_IN_FILTER", "INCLUDE_USERS_IN_FILTER", "INCLUDE_TITLES_IN_FILTER", "INCLUDE_NUMBERS_IN_FILTER", "DUMP_API_RESPONSES_IN_CONSOLE", "OPEN_ITEMS_DIRECTLY_IN_SAFARI", "HIDE_PRS_THAT_ARENT_PASSING"]
	}

    class func checkMigration() {

        let d = NSUserDefaults.standardUserDefaults()
        if d.objectForKey("LAST_RUN_VERSION_KEY") != nil {
            for k in allFields() {
                if let v: AnyObject = d.objectForKey(k) {
                    _settings_shared.setObject(v, forKey: k)
                    DLog("Migrating setting '%@'", k)
                    d.removeObjectForKey(k)
                }
            }
            _settings_shared.synchronize()
            DLog("Settings migrated to shared container")
        } else {
            DLog("No need to migrate settings into shared container")
        }

		if let moveAssignedPrs = _settings_shared.objectForKey("MOVE_ASSIGNED_PRS_TO_MY_SECTION") as? Bool {
			_settings_shared.setObject(moveAssignedPrs ? PRAssignmentPolicy.MoveToMine.rawValue : PRAssignmentPolicy.DoNothing.rawValue, forKey: "ASSIGNED_PR_HANDLING_POLICY")
			_settings_shared.removeObjectForKey("MOVE_ASSIGNED_PRS_TO_MY_SECTION")
		}

		if let mergeHandlingPolicyLegacy = _settings_shared.objectForKey("MERGE_HANDLING_POLICY") as? Int {
			_settings_shared.setObject(mergeHandlingPolicyLegacy + (mergeHandlingPolicyLegacy > 0 ? 1 : 0), forKey: "MERGE_HANDLING_POLICY_2")
			_settings_shared.removeObjectForKey("MERGE_HANDLING_POLICY")
		}

		if let closeHandlingPolicyLegacy = _settings_shared.objectForKey("CLOSE_HANDLING_POLICY") as? Int {
			_settings_shared.setObject(closeHandlingPolicyLegacy + (closeHandlingPolicyLegacy > 0 ? 1 : 0), forKey: "CLOSE_HANDLING_POLICY_2")
			_settings_shared.removeObjectForKey("CLOSE_HANDLING_POLICY")
		}

		DataManager.postMigrationRepoPrPolicy = RepoDisplayPolicy.All
		DataManager.postMigrationRepoIssuePolicy = RepoDisplayPolicy.Hide

		if let showIssues = _settings_shared.objectForKey("SHOW_ISSUES_MENU") as? Bool {
			_settings_shared.setObject(showIssues ? RepoDisplayPolicy.All.rawValue : RepoDisplayPolicy.Hide.rawValue, forKey: "NEW_ISSUE_DISPLAY_POLICY_INDEX")
			DataManager.postMigrationRepoIssuePolicy = showIssues ? RepoDisplayPolicy.All : RepoDisplayPolicy.Hide
			_settings_shared.removeObjectForKey("SHOW_ISSUES_MENU")
		}

		if let hideNewRepositories = _settings_shared.objectForKey("HIDE_NEW_REPOS_KEY") as? Bool {
			_settings_shared.setObject(hideNewRepositories ? RepoDisplayPolicy.Hide.rawValue : RepoDisplayPolicy.All.rawValue, forKey: "NEW_PR_DISPLAY_POLICY_INDEX")
			_settings_shared.setObject(hideNewRepositories ? RepoDisplayPolicy.Hide.rawValue : RepoDisplayPolicy.All.rawValue, forKey: "NEW_ISSUE_DISPLAY_POLICY_INDEX")
			_settings_shared.removeObjectForKey("HIDE_NEW_REPOS_KEY")
		}

		if let hideAllSection = _settings_shared.objectForKey("HIDE_ALL_SECTION") as? Bool {
			if hideAllSection {
				if DataManager.postMigrationRepoPrPolicy == RepoDisplayPolicy.All {
					DataManager.postMigrationRepoPrPolicy = RepoDisplayPolicy.MineAndPaticipated
				}
				if DataManager.postMigrationRepoIssuePolicy == RepoDisplayPolicy.All {
					DataManager.postMigrationRepoIssuePolicy = RepoDisplayPolicy.MineAndPaticipated
				}

				let newPrPolicy = _settings_shared.objectForKey("NEW_PR_DISPLAY_POLICY_INDEX") as? Int ?? RepoDisplayPolicy.All.rawValue
				if newPrPolicy == RepoDisplayPolicy.All.rawValue {
					_settings_shared.setObject(RepoDisplayPolicy.MineAndPaticipated.rawValue, forKey: "NEW_PR_DISPLAY_POLICY_INDEX")
				}
				let newIssuePolicy = _settings_shared.objectForKey("NEW_ISSUE_DISPLAY_POLICY_INDEX") as? Int ?? RepoDisplayPolicy.All.rawValue
				if newIssuePolicy == RepoDisplayPolicy.All.rawValue {
					_settings_shared.setObject(RepoDisplayPolicy.MineAndPaticipated.rawValue, forKey: "NEW_ISSUE_DISPLAY_POLICY_INDEX")
				}
			}
			_settings_shared.removeObjectForKey("HIDE_ALL_SECTION")
		}

		_settings_shared.synchronize()
	}

	static var saveTimer: PopTimer?

	private class func set(key: String, _ value: NSObject?) {

		let previousValue = _settings_shared.objectForKey(key) as? NSObject

		if let v = value {
			if let p = previousValue where p.isEqual(v) {
				DLog("Setting %@ to identical value (%@), skipping", key, value)
				return
			} else {
				_settings_shared.setObject(v, forKey: key)
			}
		} else {
			if previousValue == nil {
				DLog("Setting %@ to identical value (nil), skipping", key)
				return
			} else {
				_settings_shared.removeObjectForKey(key)
			}
		}
		_settings_valuesCache[key] = value
		_settings_shared.synchronize()

		DLog("Setting %@ to %@", key, value)

		possibleExport(key)
	}

	class func possibleExport(key: String?) {
		#if os(OSX)
		var keyIsGood: Bool
		if let k = key {
			keyIsGood = !["LAST_SUCCESSFUL_REFRESH", "LAST_EXPORT_URL", "LAST_EXPORT_TIME"].contains(k)
		} else {
			keyIsGood = true
		}
		if Settings.autoRepeatSettingsExport && keyIsGood && Settings.lastExportUrl != nil {
			if saveTimer == nil {
				saveTimer = PopTimer(timeInterval: 2.0) {
					Settings.writeToURL(Settings.lastExportUrl!)
				}
			}
			saveTimer?.push()
		}
		#endif
	}

	private class func get(key: String) -> AnyObject? {
		if let v: AnyObject = _settings_valuesCache[key] {
			return v
		} else if let v: AnyObject = _settings_shared.objectForKey(key) {
			_settings_valuesCache[key] = v
			return v
		} else {
			return nil
		}
	}

	/////////////////////////////////

	class func clearCache() {
		_settings_valuesCache.removeAll(keepCapacity: false)
	}

	class func writeToURL(url: NSURL) -> Bool {

		if let s = saveTimer {
			s.invalidate()
		}

		Settings.lastExportUrl = url
		Settings.lastExportDate = NSDate()
		let settings = NSMutableDictionary()
		for k in allFields() {
			if let v: AnyObject = _settings_shared.objectForKey(k) where k != "AUTO_REPEAT_SETTINGS_EXPORT" {
				settings[k] = v
			}
		}
		settings["DB_CONFIG_OBJECTS"] = ApiServer.archiveApiServers()
		if !settings.writeToURL(url, atomically: true) {
			DLog("Warning, exporting settings failed")
			return false
		}
		NSNotificationCenter.defaultCenter().postNotificationName(SETTINGS_EXPORTED, object: nil)
		DLog("Written settings to %@", url.absoluteString)
		return true
	}

	class func readFromURL(url: NSURL) -> Bool {
		if let settings = NSDictionary(contentsOfURL: url) {
			DLog("Reading settings from %@", url.absoluteString)
			resetAllSettings()
			for k in allFields() {
				if let v: AnyObject = settings[k] {
					_settings_shared.setObject(v, forKey: k)
				}
			}
			_settings_shared.synchronize()
			clearCache()
			return ApiServer.configureFromArchive(settings["DB_CONFIG_OBJECTS"] as! [String : [String : NSObject]])
		}
		return false
	}

	class func resetAllSettings() {
		for k in allFields() {
			_settings_shared.removeObjectForKey(k);
		}
		_settings_shared.synchronize()
		clearCache()
	}

	///////////////////////////////// NUMBERS

	static let sortMethodHelp = "The criterion to use when sorting items."
	class var sortMethod: Int {
		get { return get("SORT_METHOD_KEY") as? Int ?? 0 }
		set { set("SORT_METHOD_KEY", newValue) }
	}

	class var statusFilteringMode: Int {
		get { return get("STATUS_FILTERING_METHOD_KEY") as? Int ?? 0 }
		set { set("STATUS_FILTERING_METHOD_KEY", newValue) }
	}

	class var lastPreferencesTabSelected: Int {
		get { return get("LAST_PREFS_TAB_SELECTED") as? Int ?? 0 }
		set { set("LAST_PREFS_TAB_SELECTED", newValue) }
	}

	class var lastPreferencesTabSelectedOSX: Int {
		get { return get("LAST_PREFS_TAB_SELECTED_OSX") as? Int ?? 0 }
		set { set("LAST_PREFS_TAB_SELECTED_OSX", newValue) }
	}

	static let closeHandlingPolicyHelp = "How to handle an item when it is believed to be closed (or has disappeared)."
	class var closeHandlingPolicy: Int {
		get { return get("CLOSE_HANDLING_POLICY_2") as? Int ?? PRHandlingPolicy.KeepMine.rawValue }
		set { set("CLOSE_HANDLING_POLICY_2", newValue) }
	}

	static let mergeHandlingPolicyHelp = "How to handle an item when it is detected as merged."
	class var mergeHandlingPolicy: Int {
		get { return get("MERGE_HANDLING_POLICY_2") as? Int ?? PRHandlingPolicy.KeepMine.rawValue }
		set { set("MERGE_HANDLING_POLICY_2", newValue) }
	}

	static let statusItemRefreshIntervalHelp = "Because querying statuses can be bandwidth-intensive, if you have alot of items in your lists, you may want to raise this to a higher value. You can always see how much API usage you have left per-hour from the 'Servers' tab."
	class var statusItemRefreshInterval: Int {
		get { if let n = get("STATUS_ITEM_REFRESH_COUNT") as? Int { return n>0 ? n : 10 } else { return 10 } }
		set { set("STATUS_ITEM_REFRESH_COUNT", newValue) }
	}

	static let labelRefreshIntervalHelp = "Querying labels can be moderately bandwidth-intensive, but it does involve making some extra API calls. Since labels don't change often, you may want to raise this to a higher value if you have alot of items on your lists. You can always see how much API usage you have left per-hour from the 'Servers' tab."
	class var labelRefreshInterval: Int {
		get { if let n = get("LABEL_REFRESH_COUNT") as? Int { return n>0 ? n : 4 } else { return 4 } }
		set { set("LABEL_REFRESH_COUNT", newValue) }
	}

	class var checkForUpdatesInterval: Int {
		get { return get("UPDATE_CHECK_INTERVAL_KEY") as? Int ?? 8 }
		set { set("UPDATE_CHECK_INTERVAL_KEY", newValue) }
	}

	static let assignedPrHandlingPolicyHelp = "If an item is assigned to you, Trailer can move it to a specific section or leave it as-is."
	class var assignedPrHandlingPolicy: Int {
		get { return get("ASSIGNED_PR_HANDLING_POLICY") as? Int ?? 1 }
		set { set("ASSIGNED_PR_HANDLING_POLICY", newValue) }
	}

	static let displayPolicyForNewPrsHelp = "When a new repository is detected in your watchlist, this display policy will be applied by default to pull requests that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."
	class var displayPolicyForNewPrs: Int {
		get { return get("NEW_PR_DISPLAY_POLICY_INDEX") as? Int ?? RepoDisplayPolicy.All.rawValue }
		set { set("NEW_PR_DISPLAY_POLICY_INDEX", newValue) }
	}

	static let displayPolicyForNewIssuesHelp = "When a new repository is detected in your watchlist, this display policy will be applied by default to issues that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."
	class var displayPolicyForNewIssues: Int {
		get { return get("NEW_ISSUE_DISPLAY_POLICY_INDEX") as? Int ?? RepoDisplayPolicy.Hide.rawValue }
		set { set("NEW_ISSUE_DISPLAY_POLICY_INDEX", newValue) }
	}

	/////////////////////////// STRINGS

	static let statusFilteringTermsHelp = "You can specify specific terms which can then be matched against status items, in order to hide or show them."
	class var statusFilteringTerms: [String] {
		get { return get("STATUS_FILTERING_TERMS_KEY") as? [String] ?? [] }
		set { set("STATUS_FILTERING_TERMS_KEY", newValue) }
	}

	class var commentAuthorBlacklist: [String] {
		get { return get("COMMENT_AUTHOR_BLACKLIST") as? [String] ?? [] }
		set { set("COMMENT_AUTHOR_BLACKLIST", newValue) }
	}

	class var hotkeyLetter: String {
		get { return get("HOTKEY_LETTER") as? String ?? "T" }
		set { set("HOTKEY_LETTER", newValue) }
	}

	class var lastRunVersion: String {
		get { return get("LAST_RUN_VERSION_KEY") as? String ?? "" }
		set { set("LAST_RUN_VERSION_KEY", newValue) }
	}

	/////////////////////////// FLOATS

	static let refreshPeriodHelp = "How often to refresh items when the app is active and in the foreground."
	class var refreshPeriod: Float {
		get { if let n = get("REFRESH_PERIOD_KEY") as? Float { return n < 60 ? 120 : n } else { return 120 } }
		set { set("REFRESH_PERIOD_KEY", newValue) }
	}

	static let backgroundRefreshPeriodHelp = "The minimum amount of time to wait before requesting an update when the app is in the background. Even though this is quite efficient, it's still a good idea to keep this to a high value in order to keep battery and bandwidth use low. The default of half an hour is generally a good number. Please note that iOS may ignore this value and perform background refreshes at longer intervals depending on battery level and other reasons."
	class var backgroundRefreshPeriod: Float {
		get { if let n = get("IOS_BACKGROUND_REFRESH_PERIOD_KEY") as? Float { return n > 0 ? n : 1800 } else { return 1800 } }
		set {
			set("IOS_BACKGROUND_REFRESH_PERIOD_KEY", newValue)
			#if os(iOS)
            app.setMinimumBackgroundFetchInterval(NSTimeInterval(newValue))
			#endif
		}
	}

	static let newRepoCheckPeriodHelp = "How long before reloading your team list and watched repositories from a server. Since this doesn't change often, it's good to keep this as high as possible in order to keep bandwidth use as low as possible during refreshes. Set this to a lower value if you often update your watched repositories or teams."
	class var newRepoCheckPeriod: Float {
		get { if let n = get("NEW_REPO_CHECK_PERIOD") as? Float { return max(n, 2) } else { return 2 } }
		set { set("NEW_REPO_CHECK_PERIOD", newValue) }
	}

	/////////////////////////// DATES

    class var lastSuccessfulRefresh: NSDate? {
        get { return get("LAST_SUCCESSFUL_REFRESH") as? NSDate }
        set { set("LAST_SUCCESSFUL_REFRESH", newValue) }
    }

	class var lastExportDate: NSDate? {
		get { return get("LAST_EXPORT_TIME") as? NSDate }
		set { set("LAST_EXPORT_TIME", newValue) }
	}

	/////////////////////////// URLs

	class var lastExportUrl: NSURL? {
		get {
			if let s = get("LAST_EXPORT_URL") as? String {
				return NSURL(string: s)
			} else {
				return nil
			}
		}
		set { set("LAST_EXPORT_URL", newValue?.absoluteString) }
	}

    /////////////////////////// DEFAULT FALSE

	static let hideUncommentedItemsHelp = "Hide all items except items which have unread comments (items with a red number badge)."
	class var hideUncommentedItems: Bool {
		get { return get("HIDE_UNCOMMENTED_PRS_KEY") as? Bool ?? false }
		set { set("HIDE_UNCOMMENTED_PRS_KEY", newValue) }
	}

	static let showCommentsEverywhereHelp = "Badge and send notificatons for items in the 'all' sections as well as your own and participated ones."
	class var showCommentsEverywhere: Bool {
		get { return get("SHOW_COMMENTS_EVERYWHERE_KEY") as? Bool ?? false }
		set { set("SHOW_COMMENTS_EVERYWHERE_KEY", newValue) }
	}

	static let sortDescendingHelp = "The direction to sort items based on the criterion below. Toggling this option will change the set of options available in the option below to better reflect what that will do."
	class var sortDescending: Bool {
		get { return get("SORT_ORDER_KEY") as? Bool ?? false }
		set { set("SORT_ORDER_KEY", newValue) }
	}

	static let showCreatedInsteadOfUpdatedHelp = "Trailer will usually display the time of the most recent activity in an item, such as comments. This setting replaces that with the orignal creation time of the item. Together with the sorting options, this is useful for helping prioritise items based on how old, or new, they are.";
	class var showCreatedInsteadOfUpdated: Bool {
		get { return get("SHOW_UPDATED_KEY") as? Bool ?? false }
		set { set("SHOW_UPDATED_KEY", newValue) }
	}

	static let dontKeepPrsMergedByMeHelp = "If a PR is detected as merged by you, remove it immediately from the list of merged items"
	class var dontKeepPrsMergedByMe: Bool {
		get { return get("DONT_KEEP_MY_PRS_KEY") as? Bool ?? false }
		set { set("DONT_KEEP_MY_PRS_KEY", newValue) }
	}

	static let hideAvatarsHelp = "Hide the image of the author's avatar which is usually shown on the left of listed items"
	class var hideAvatars: Bool {
		get { return get("HIDE_AVATARS_KEY") as? Bool ?? false }
		set { set("HIDE_AVATARS_KEY", newValue) }
	}

	static let autoParticipateInMentionsHelp = "If your username is mentioned in an item's description or a comment posted inside it, move the item to your 'Participated' section."
	class var autoParticipateInMentions: Bool {
		get { return get("AUTO_PARTICIPATE_IN_MENTIONS_KEY") as? Bool ?? false }
		set { set("AUTO_PARTICIPATE_IN_MENTIONS_KEY", newValue) }
	}

	static let dontAskBeforeWipingMergedHelp = "Don't ask for confirmation when you select 'Remove all merged items'. Please note there is no confirmation when selecting this from the Apple Watch, irrespective of this setting."
	class var dontAskBeforeWipingMerged: Bool {
		get { return get("DONT_ASK_BEFORE_WIPING_MERGED") as? Bool ?? false }
		set { set("DONT_ASK_BEFORE_WIPING_MERGED", newValue) }
	}

	static let dontAskBeforeWipingClosedHelp = "Don't ask for confirmation when you select 'Remove all closed items'. Please note there is no confirmation when selecting this from the Apple Watch, irrespective of this setting."
	class var dontAskBeforeWipingClosed: Bool {
		get { return get("DONT_ASK_BEFORE_WIPING_CLOSED") as? Bool ?? false }
		set { set("DONT_ASK_BEFORE_WIPING_CLOSED", newValue) }
	}

	static let groupByRepoHelp = "Sort and gather items from the same repository next to each other, before applying the criterion specified above."
	class var groupByRepo: Bool {
		get { return get("GROUP_BY_REPO") as? Bool ?? false }
		set { set("GROUP_BY_REPO", newValue) }
	}

	static let showLabelsHelp = "Show labels associated with items, usually a good idea"
	class var showLabels: Bool {
		get { return get("SHOW_LABELS") as? Bool ?? false }
		set { set("SHOW_LABELS", newValue) }
	}

	static let showStatusItemsHelp = "Show status items, such as CI results or messages from code review services, that are attached to items on the server."
	class var showStatusItems: Bool {
		get { return get("SHOW_STATUS_ITEMS") as? Bool ?? false }
		set { set("SHOW_STATUS_ITEMS", newValue) }
	}

	static let makeStatusItemsSelectableHelp = "Normally you have to Cmd-click on status items to visit their relayed links, this option makes them always selectable, but it makes it easier to accidentally end up opening a status item page instead of an item's page."
	class var makeStatusItemsSelectable: Bool {
		get { return get("MAKE_STATUS_ITEMS_SELECTABLE") as? Bool ?? false }
		set { set("MAKE_STATUS_ITEMS_SELECTABLE", newValue) }
	}

	static let markUnmergeableOnUserSectionsOnlyHelp = "If the server reports a PR as un-mergeable, don't tag this on items in the 'all items' section."
	class var markUnmergeableOnUserSectionsOnly: Bool {
		get { return get("MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY") as? Bool ?? false }
		set { set("MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY", newValue) }
	}

	static let openPrAtFirstUnreadCommentHelp = "When opening the web view for an item, skip directly down to the first comment that has not been read, rather than starting from the top of the item's web page."
	class var openPrAtFirstUnreadComment: Bool {
		get { return get("OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY") as? Bool ?? false }
		set { set("OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY", newValue) }
	}

	static let logActivityToConsoleHelp = "This is meant for troubleshooting and should be turned off usually, as it is a performance and security concern when activated. It will output detailed messages about the app's behaviour in the device console."
	class var logActivityToConsole: Bool {
		get {
        #if DEBUG
            return true
        #else
            return get("LOG_ACTIVITY_TO_CONSOLE_KEY") as? Bool ?? false
        #endif
        }
		set { set("LOG_ACTIVITY_TO_CONSOLE_KEY", newValue) }
	}

	class var hotkeyEnable: Bool {
		get { return get("HOTKEY_ENABLE") as? Bool ?? false }
		set { set("HOTKEY_ENABLE", newValue) }
	}

	class var hotkeyControlModifier: Bool {
		get { return get("HOTKEY_CONTROL_MODIFIER") as? Bool ?? false }
		set { set("HOTKEY_CONTROL_MODIFIER", newValue) }
	}

	static let disableAllCommentNotificationsHelp = "Do not get notified about any comments at all."
    class var disableAllCommentNotifications: Bool {
        get { return get("DISABLE_ALL_COMMENT_NOTIFICATIONS") as? Bool ?? false }
        set { set("DISABLE_ALL_COMMENT_NOTIFICATIONS", newValue) }
    }

	static let notifyOnStatusUpdatesHelp = "Post notifications when status items change. Useful for tracking the CI build state of your own items, for instance."
    class var notifyOnStatusUpdates: Bool {
        get { return get("NOTIFY_ON_STATUS_UPDATES") as? Bool ?? false }
        set { set("NOTIFY_ON_STATUS_UPDATES", newValue) }
    }

	static let notifyOnStatusUpdatesForAllPrsHelp = "Notificaitons for status items are sent only for your own and particiapted items by default. Select this to receive status update notifications for the items in the 'all' section too."
    class var notifyOnStatusUpdatesForAllPrs: Bool {
        get { return get("NOTIFY_ON_STATUS_UPDATES_ALL") as? Bool ?? false }
        set { set("NOTIFY_ON_STATUS_UPDATES_ALL", newValue) }
    }

	static let autoParticipateOnTeamMentionsHelp = "If the name of one of the teams you belong to is mentioned in an item's description or a comment posted inside it, move the item to your 'Participated' section."
	class var autoParticipateOnTeamMentions: Bool {
		get { return get("AUTO_PARTICIPATE_ON_TEAM_MENTIONS") as? Bool ?? false }
		set { set("AUTO_PARTICIPATE_ON_TEAM_MENTIONS", newValue) }
	}

	static let preferIssuesInWatchHelp = "In the Apple Watch glance, or when there is only enough space to display one count or set of statistics in complications, prefer the ones for issues rather than the ones for PRs."
	class var preferIssuesInWatch: Bool {
		get { return get("SHOW_ISSUES_IN_WATCH_GLANCE") as? Bool ?? false }
		set { set("SHOW_ISSUES_IN_WATCH_GLANCE", newValue) }
	}

	static let hideDescriptionInWatchDetailHelp = "When showing the full detail view of items on the Apple Watch, skip showing the description of the item, instead showing only status and comments for it."
	class var hideDescriptionInWatchDetail: Bool {
		get { return get("HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW") as? Bool ?? false }
		set { set("HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW", newValue) }
	}

	class var autoRepeatSettingsExport: Bool {
		get { return get("AUTO_REPEAT_SETTINGS_EXPORT") as? Bool ?? false }
		set { set("AUTO_REPEAT_SETTINGS_EXPORT", newValue) }
	}

	class var dontConfirmSettingsImport: Bool {
		get { return get("DONT_CONFIRM_SETTINGS_IMPORT") as? Bool ?? false }
		set { set("DONT_CONFIRM_SETTINGS_IMPORT", newValue) }
	}

	static let includeServersInFilterHelp = "Check the name of the server an item came from when selecting it for inclusion in filtered results. You can also prefix a search with 'server:' to specifically search for this."
    class var includeServersInFilter: Bool {
        get { return get("INCLUDE_SERVERS_IN_FILTER") as? Bool ?? false }
        set { set("INCLUDE_SERVERS_IN_FILTER", newValue) }
    }

	static let dumpAPIResponsesInConsoleHelp = "This is meant for troubleshooting and should be turned off usually, as it is a performance and security concern when activated. It will output the full request and responses to and from API servers in the device console."
	class var dumpAPIResponsesInConsole: Bool {
		get { return get("DUMP_API_RESPONSES_IN_CONSOLE") as? Bool ?? false }
		set { set("DUMP_API_RESPONSES_IN_CONSOLE", newValue) }
	}

	static let openItemsDirectlyInSafariHelp = "Directly open items in the Safari browser rather than the internal web view. Especially useful on iPad when using split-screen view, where you can pull in PocktetTrailer from the side but stay in Safari, or on iPhone where you can use the status-bar button as a back button. If the detail view is already visible (for instance when runing in full-screen mode on iPad) the internal view will still get used, even if this option is turned on."
	class var openItemsDirectlyInSafari: Bool {
		get { return get("OPEN_ITEMS_DIRECTLY_IN_SAFARI") as? Bool ?? false }
		set { set("OPEN_ITEMS_DIRECTLY_IN_SAFARI", newValue) }
	}

	static let hidePrsThatArentPassingHelp = "Hide PR items which have status items, but are not all green. Useful for hiding PRs which are not ready to review or those who have not passed certain checks yet."
	class var hidePrsThatArentPassing: Bool {
		get { return get("HIDE_PRS_THAT_ARENT_PASSING") as? Bool ?? false }
		set { set("HIDE_PRS_THAT_ARENT_PASSING", newValue) }
	}

	////////////////////////////// DEFAULT TRUE

	static let useVibrancyHelp = "Use Mac OS X Vibrancy to display the Trailer drop-down menu, if available on the current OS version. If the OS doesn't support this, this setting has no effect."
	class var useVibrancy: Bool {
		get { return get("USE_VIBRANCY_UI") as? Bool ?? true }
		set { set("USE_VIBRANCY_UI", newValue) }
	}

	static let countOnlyListedItemsHelp = "Show the number of items currently visible in Trailer in the menu bar. If this is unselected, the menubar will display the count of all open items in the current watchlist, irrespective of filters or visibility settings. It's recommended you keep this on."
    class var countOnlyListedItems: Bool {
        get { return get("COUNT_ONLY_LISTED_PRS") as? Bool ?? true }
        set { set("COUNT_ONLY_LISTED_PRS", newValue) }
    }

	static let checkForUpdatesAutomaticallyHelp = "Check for updates to Trailer automatically. It is generally a very good idea to keep this selected, unless you are using an external package manager to manage the updates."
	class var checkForUpdatesAutomatically: Bool {
		get { return get("UPDATE_CHECK_AUTO_KEY") as? Bool ?? true }
		set { set("UPDATE_CHECK_AUTO_KEY", newValue) }
	}

	static let showReposInNameHelp = "Show the name of the repository each item comes from."
	class var showReposInName: Bool {
		get { return get("SHOW_REPOS_IN_NAME") as? Bool ?? true }
		set { set("SHOW_REPOS_IN_NAME", newValue) }
	}

	static let includeTitlesInFilterHelp = "Check item titles when selecting items for inclusion in filtered results. You can also prefix a search with 'title:' to specifically search for this."
	class var includeTitlesInFilter: Bool {
		get { return get("INCLUDE_TITLES_IN_FILTER") as? Bool ?? true }
		set { set("INCLUDE_TITLES_IN_FILTER", newValue) }
	}

	static let includeNumbersInFilterHelp = "Check the PR/Issue number of the item when selecting it for inclusion in filtered results. You can also prefix a search with 'number:' to specifically search for this."
	class var includeNumbersInFilter: Bool {
		get { return get("INCLUDE_NUMBERS_IN_FILTER") as? Bool ?? false }
		set { set("INCLUDE_NUMBERS_IN_FILTER", newValue) }
	}

	static let includeReposInFilterHelp = "Check repository names when selecting items for inclusion in filtered results. You can also prefix a search with 'repo:' to specifically search for this."
	class var includeReposInFilter: Bool {
		get { return get("INCLUDE_REPOS_IN_FILTER") as? Bool ?? true }
		set { set("INCLUDE_REPOS_IN_FILTER", newValue) }
	}

	static let includeLabelsInFilterHelp = "Check labels of items when selecting items for inclusion in filtered results. You can also prefix a search with 'label:' to specifically search for this."
	class var includeLabelsInFilter: Bool {
		get { return get("INCLUDE_LABELS_IN_FILTER") as? Bool ?? true }
		set { set("INCLUDE_LABELS_IN_FILTER", newValue) }
	}

	static let includeUsersInFilterHelp = "Check the name of the author of an item when selecting it for inclusion in filtered results. You can also prefix a search with 'user:' to specifically search for this."
    class var includeUsersInFilter: Bool {
        get { return get("INCLUDE_USERS_IN_FILTER") as? Bool ?? true }
        set { set("INCLUDE_USERS_IN_FILTER", newValue) }
    }

	static let includeStatusesInFilterHelp = "Check status lines of items when selecting items for inclusion in filtered results. You can also prefix a search with 'status:' to specifically search for this."
	class var includeStatusesInFilter: Bool {
		get { return get("INCLUDE_STATUSES_IN_FILTER") as? Bool ?? true }
		set { set("INCLUDE_STATUSES_IN_FILTER", newValue) }
	}

	class var hotkeyCommandModifier: Bool {
		get { return get("HOTKEY_COMMAND_MODIFIER") as? Bool ?? true }
		set { set("HOTKEY_COMMAND_MODIFIER", newValue) }
	}

	class var hotkeyOptionModifier: Bool {
		get { return get("HOTKEY_OPTION_MODIFIER") as? Bool ?? true }
		set { set("HOTKEY_OPTION_MODIFIER", newValue) }
	}

	class var hotkeyShiftModifier: Bool {
		get { return get("HOTKEY_SHIFT_MODIFIER") as? Bool ?? true }
		set { set("HOTKEY_SHIFT_MODIFIER", newValue) }
	}

	static let grayOutWhenRefreshingHelp = "Gray out the menubar icon when refreshing data from the configured servers. You may want to turn this off if you find that distracting or use a menu bar management tool that automatically highlights menubar items which get updated"
    class var grayOutWhenRefreshing: Bool {
		get { return get("GRAY_OUT_WHEN_REFRESHING") as? Bool ?? true }
		set { set("GRAY_OUT_WHEN_REFRESHING", newValue) }
    }

}
