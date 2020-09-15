
#if os(iOS)
	import UIKit
#else
    import ServiceManagement
#endif

struct Settings {

	private static let sharedDefaults = UserDefaults(suiteName: "group.Trailer")!

	private static var allFields: [String] {
		return [
			"SORT_METHOD_KEY", "STATUS_FILTERING_METHOD_KEY", "LAST_PREFS_TAB_SELECTED", "STATUS_ITEM_REFRESH_BATCH", "UPDATE_CHECK_INTERVAL_KEY", "ASSIGNED_REVIEW_HANDLING_POLICY", "NOTIFY_ON_REVIEW_CHANGE_REQUESTS", "NOTIFY_ON_ALL_REVIEW_CHANGE_REQUESTS",
			"STATUS_FILTERING_TERMS_KEY", "COMMENT_AUTHOR_BLACKLIST", "HOTKEY_LETTER", "REFRESH_PERIOD_KEY", "IOS_BACKGROUND_REFRESH_PERIOD_KEY", "NEW_REPO_CHECK_PERIOD", "LAST_SUCCESSFUL_REFRESH",
			"LAST_RUN_VERSION_KEY", "UPDATE_CHECK_AUTO_KEY", "HIDE_UNCOMMENTED_PRS_KEY", "SHOW_COMMENTS_EVERYWHERE_KEY", "SORT_ORDER_KEY", "SHOW_UPDATED_KEY", "DONT_KEEP_MY_PRS_KEY", "HIDE_AVATARS_KEY",
			"DONT_ASK_BEFORE_WIPING_MERGED", "DONT_ASK_BEFORE_WIPING_CLOSED", "HIDE_NEW_REPOS_KEY", "GROUP_BY_REPO", "HIDE_ALL_SECTION", "SHOW_STATUS_ITEMS", "NOTIFY_ON_REVIEW_ACCEPTANCES", "NOTIFY_ON_ALL_REVIEW_ACCEPTANCES", "NOTIFY_ON_REVIEW_ASSIGNMENTS",
			"MAKE_STATUS_ITEMS_SELECTABLE", "COUNT_ONLY_LISTED_PRS", "OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY", "LOG_ACTIVITY_TO_CONSOLE_KEY", "NOTIFY_ON_REVIEW_DISMISSALS", "NOTIFY_ON_ALL_REVIEW_DISMISSALS",
			"HOTKEY_ENABLE", "HOTKEY_CONTROL_MODIFIER", "DISABLE_ALL_COMMENT_NOTIFICATIONS", "NOTIFY_ON_STATUS_UPDATES", "NOTIFY_ON_STATUS_UPDATES_ALL", "SHOW_REPOS_IN_NAME", "INCLUDE_REPOS_IN_FILTER", "SHOW_STATUSES_EVERYWHERE",
			"INCLUDE_LABELS_IN_FILTER", "INCLUDE_STATUSES_IN_FILTER", "HOTKEY_COMMAND_MODIFIER", "HOTKEY_OPTION_MODIFIER", "HOTKEY_SHIFT_MODIFIER", "GRAY_OUT_WHEN_REFRESHING", "SHOW_ISSUES_MENU", "NOTIFY_ON_ITEM_REACTIONS",
			"SHOW_ISSUES_IN_WATCH_GLANCE", "ASSIGNED_PR_HANDLING_POLICY", "HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW", "AUTO_REPEAT_SETTINGS_EXPORT", "DONT_CONFIRM_SETTINGS_IMPORT", "NOTIFY_ON_COMMENT_REACTIONS", "REACTION_SCANNING_BATCH",
			"LAST_EXPORT_URL", "LAST_EXPORT_TIME", "CLOSE_HANDLING_POLICY_2", "MERGE_HANDLING_POLICY_2", "LAST_PREFS_TAB_SELECTED_OSX", "NEW_PR_DISPLAY_POLICY_INDEX", "NEW_ISSUE_DISPLAY_POLICY_INDEX", "HIDE_PRS_THAT_ARENT_PASSING_ONLY_IN_ALL",
			"INCLUDE_SERVERS_IN_FILTER", "INCLUDE_USERS_IN_FILTER", "INCLUDE_TITLES_IN_FILTER", "INCLUDE_NUMBERS_IN_FILTER", "DUMP_API_RESPONSES_IN_CONSOLE", "OPEN_ITEMS_DIRECTLY_IN_SAFARI", "HIDE_PRS_THAT_ARENT_PASSING",
			"REMOVE_RELATED_NOTIFICATIONS_ON_ITEM_REMOVE", "HIDE_SNOOZED_ITEMS", "INCLUDE_MILESTONES_IN_FILTER", "INCLUDE_ASSIGNEE_NAMES_IN_FILTER", "API_SERVERS_IN_SEPARATE_MENUS", "ASSUME_READ_ITEM_IF_USER_HAS_NEWER_COMMENTS",
            "AUTO_SNOOZE_DAYS", "HIDE_MENUBAR_COUNTS", "AUTO_ADD_NEW_REPOS", "AUTO_REMOVE_DELETED_REPOS", "MARK_PRS_AS_UNREAD_ON_NEW_COMMITS", "SHOW_LABELS", "DISPLAY_REVIEW_CHANGE_REQUESTS", "SHOW_RELATIVE_DATES", "QUERY_AUTHORED_PRS", "QUERY_AUTHORED_ISSUES",
			"DISPLAY_MILESTONES", "DEFAULT_APP_FOR_OPENING_WEB", "DEFAULT_APP_FOR_OPENING_ITEMS", "HIDE_ARCHIVED_REPOS", "DRAFT_HANDLING_POLICY", "MARK_UNMERGEABLE_ITEMS", "SHOW_PR_LINES", "SCAN_CLOSED_AND_MERGED", "USE_V4_API", "REQUESTED_TEAM_REVIEWS"]
	}

    static func checkMigration() {

		if let snoozeWakeOnComment = sharedDefaults.object(forKey: "SNOOZE_WAKEUP_ON_COMMENT") as? Bool {
			DataManager.postMigrationSnoozeWakeOnComment = snoozeWakeOnComment
			sharedDefaults.removeObject(forKey: "SNOOZE_WAKEUP_ON_COMMENT")
		}
		if let snoozeWakeOnMention = sharedDefaults.object(forKey: "SNOOZE_WAKEUP_ON_MENTION") as? Bool {
			DataManager.postMigrationSnoozeWakeOnMention = snoozeWakeOnMention
			sharedDefaults.removeObject(forKey: "SNOOZE_WAKEUP_ON_MENTION")
		}
		if let snoozeWakeOnStatusUpdate = sharedDefaults.object(forKey: "SNOOZE_WAKEUP_ON_STATUS_UPDATE") as? Bool {
			DataManager.postMigrationSnoozeWakeOnStatusUpdate = snoozeWakeOnStatusUpdate
			sharedDefaults.removeObject(forKey: "SNOOZE_WAKEUP_ON_STATUS_UPDATE")
		}

		if
            sharedDefaults.object(forKey: "SHOW_STATUSES_EVERYWHERE") as? Bool == nil,
            let showStats = sharedDefaults.object(forKey: "SHOW_STATUS_ITEMS") as? Bool, showStats,
            let notifyAll = sharedDefaults.object(forKey: "NOTIFY_ON_STATUS_UPDATES_ALL") as? Bool, notifyAll {

            sharedDefaults.set(true, forKey: "SHOW_STATUSES_EVERYWHERE")
		}

		if let moveAssignedPrs = sharedDefaults.object(forKey: "MOVE_ASSIGNED_PRS_TO_MY_SECTION") as? Bool {
			sharedDefaults.set(moveAssignedPrs ? AssignmentPolicy.moveToMine.rawValue : AssignmentPolicy.doNothing.rawValue, forKey: "ASSIGNED_PR_HANDLING_POLICY")
			sharedDefaults.removeObject(forKey: "MOVE_ASSIGNED_PRS_TO_MY_SECTION")
		}

		if let mergeHandlingPolicyLegacy = sharedDefaults.object(forKey: "MERGE_HANDLING_POLICY") as? Int {
			sharedDefaults.set(mergeHandlingPolicyLegacy + (mergeHandlingPolicyLegacy > 0 ? 1 : 0), forKey: "MERGE_HANDLING_POLICY_2")
			sharedDefaults.removeObject(forKey: "MERGE_HANDLING_POLICY")
		}

		if let closeHandlingPolicyLegacy = sharedDefaults.object(forKey: "CLOSE_HANDLING_POLICY") as? Int {
			sharedDefaults.set(closeHandlingPolicyLegacy + (closeHandlingPolicyLegacy > 0 ? 1 : 0), forKey: "CLOSE_HANDLING_POLICY_2")
			sharedDefaults.removeObject(forKey: "CLOSE_HANDLING_POLICY")
		}

		if let mentionedUserMoveLegacy = sharedDefaults.object(forKey: "AUTO_PARTICIPATE_IN_MENTIONS_KEY") as? Bool {
			sharedDefaults.set(mentionedUserMoveLegacy ? Section.mentioned.intValue : Section.none.intValue, forKey: "NEW_MENTION_MOVE_POLICY")
			sharedDefaults.removeObject(forKey: "AUTO_PARTICIPATE_IN_MENTIONS_KEY")
		}

		if let mentionedTeamMoveLegacy = sharedDefaults.object(forKey: "AUTO_PARTICIPATE_ON_TEAM_MENTIONS") as? Bool {
			sharedDefaults.set(mentionedTeamMoveLegacy ? Section.mentioned.intValue : Section.none.intValue, forKey: "TEAM_MENTION_MOVE_POLICY")
			sharedDefaults.removeObject(forKey: "AUTO_PARTICIPATE_ON_TEAM_MENTIONS")
		}

		if let mentionedRepoMoveLegacy = sharedDefaults.object(forKey: "MOVE_NEW_ITEMS_IN_OWN_REPOS_TO_MENTIONED") as? Bool {
			sharedDefaults.set(mentionedRepoMoveLegacy ? Section.mentioned.intValue : Section.none.intValue, forKey: "NEW_ITEM_IN_OWNED_REPO_MOVE_POLICY")
			sharedDefaults.removeObject(forKey: "MOVE_NEW_ITEMS_IN_OWN_REPOS_TO_MENTIONED")
		}

		DataManager.postMigrationRepoPrPolicy = .all
		DataManager.postMigrationRepoIssuePolicy = .hide

		if let showIssues = sharedDefaults.object(forKey: "SHOW_ISSUES_MENU") as? Bool {
			sharedDefaults.set(showIssues ? RepoDisplayPolicy.all.intValue : RepoDisplayPolicy.hide.intValue, forKey: "NEW_ISSUE_DISPLAY_POLICY_INDEX")
			DataManager.postMigrationRepoIssuePolicy = showIssues ? RepoDisplayPolicy.all : RepoDisplayPolicy.hide
			sharedDefaults.removeObject(forKey: "SHOW_ISSUES_MENU")
		}

		if let hideNewRepositories = sharedDefaults.object(forKey: "HIDE_NEW_REPOS_KEY") as? Bool {
			sharedDefaults.set(hideNewRepositories ? RepoDisplayPolicy.hide.intValue : RepoDisplayPolicy.all.intValue, forKey: "NEW_PR_DISPLAY_POLICY_INDEX")
			sharedDefaults.set(hideNewRepositories ? RepoDisplayPolicy.hide.intValue : RepoDisplayPolicy.all.intValue, forKey: "NEW_ISSUE_DISPLAY_POLICY_INDEX")
			sharedDefaults.removeObject(forKey: "HIDE_NEW_REPOS_KEY")
		}

		if let hideAllSection = sharedDefaults.object(forKey: "HIDE_ALL_SECTION") as? Bool {
			if hideAllSection {
				if DataManager.postMigrationRepoPrPolicy == .all {
					DataManager.postMigrationRepoPrPolicy = .mineAndPaticipated
				}
				if DataManager.postMigrationRepoIssuePolicy == .all {
					DataManager.postMigrationRepoIssuePolicy = .mineAndPaticipated
				}

				let newPrPolicy = sharedDefaults.object(forKey: "NEW_PR_DISPLAY_POLICY_INDEX") as? Int64 ?? RepoDisplayPolicy.all.rawValue
				if newPrPolicy == RepoDisplayPolicy.all.rawValue {
					sharedDefaults.set(RepoDisplayPolicy.mineAndPaticipated.intValue, forKey: "NEW_PR_DISPLAY_POLICY_INDEX")
				}
				let newIssuePolicy = sharedDefaults.object(forKey: "NEW_ISSUE_DISPLAY_POLICY_INDEX") as? Int64 ?? RepoDisplayPolicy.all.rawValue
				if newIssuePolicy == RepoDisplayPolicy.all.rawValue {
					sharedDefaults.set(RepoDisplayPolicy.mineAndPaticipated.intValue, forKey: "NEW_ISSUE_DISPLAY_POLICY_INDEX")
				}
			}
			sharedDefaults.removeObject(forKey: "HIDE_ALL_SECTION")
		}

		for repo in Repo.allItems(of: Repo.self, in: DataManager.main) where repo.value(forKey: "archived") == nil {
			repo.archived = false
			repo.updatedAt = .distantPast
		}
        
        for server in ApiServer.allApiServers(in: DataManager.main) where server.isGitHub && S(server.graphQLPath).isEmpty {
            server.graphQLPath = "https://api.github.com/graphql"
        }
                
        #if os(macOS)
        if Settings.lastRunVersion != "" && sharedDefaults.object(forKey: "launchAtLogin") == nil {
            DLog("Migrated to the new startup mechanism, activating it by default")
            isAppLoginItem = true
        }
        #endif

		sharedDefaults.synchronize()
	}
    
    #if os(macOS)
    static var isAppLoginItem: Bool {
        get {
            return sharedDefaults.bool(forKey: "launchAtLogin")
        }
        set {
            sharedDefaults.set(newValue, forKey: "launchAtLogin")
            SMLoginItemSetEnabled(LauncherCommon.helperAppId as CFString, newValue)
        }
    }
    #endif
    
	private static func set(_ key: String, _ value: Any?) {

		let previousValue = sharedDefaults.object(forKey: key)

		if let v = value {
			let vString = String(describing: v)
			if let p = previousValue, String(describing : p) == vString {
				DLog("Setting %@ to identical value (%@), skipping", key, vString)
				return
			} else {
				sharedDefaults.set(v, forKey: key)
			}
		} else {
			if previousValue == nil {
				DLog("Setting %@ to identical value (nil), skipping", key)
				return
			} else {
				sharedDefaults.removeObject(forKey: key)
			}
		}

		if let v = value {
			DLog("Setting %@ to %@", key, String(describing: v))
		} else {
			DLog("Clearing option %@", key)
		}

		possibleExport(key)
	}

	private static let saveTimer = PopTimer(timeInterval: 2) {
		if let e = Settings.lastExportUrl {
			Settings.writeToURL(e)
		}
	}

	static func possibleExport(_ key: String?) {
		#if os(OSX)
        if !Settings.autoRepeatSettingsExport {
            return
        }
        
		let keyIsGood: Bool
		if let k = key {
			keyIsGood = !["LAST_SUCCESSFUL_REFRESH", "LAST_EXPORT_URL", "LAST_EXPORT_TIME"].contains(k)
		} else {
			keyIsGood = true
		}
		if keyIsGood && Settings.lastExportUrl != nil {
			saveTimer.push()
		}
		#endif
	}

	private static func get(_ key: String) -> Any? {
		return sharedDefaults.object(forKey: key)
	}

	///////////////////////////////// IMPORT / EXPORT

	@discardableResult
	static func writeToURL(_ url: URL) -> Bool {

		saveTimer.abort()

		Settings.lastExportUrl = url
		Settings.lastExportDate = Date()
		let settings = NSMutableDictionary()
		for k in allFields {
			if let v = sharedDefaults.object(forKey: k), k != "AUTO_REPEAT_SETTINGS_EXPORT" {
				settings[k] = v
			}
		}
		settings["DB_CONFIG_OBJECTS"] = ApiServer.archivedApiServers
		settings["DB_SNOOZE_OBJECTS"] = SnoozePreset.archivedPresets
		if !settings.write(to: url, atomically: true) {
			DLog("Warning, exporting settings failed")
			return false
		}
        NotificationCenter.default.post(name: .SettingsExported, object: nil)
		DLog("Written settings to %@", url.absoluteString)
		return true
	}

	static func readFromURL(_ url: URL) -> Bool {
		if let settings = NSDictionary(contentsOf: url) {
			DLog("Reading settings from %@", url.absoluteString)
			resetAllSettings()
			for k in allFields {
				if let v = settings[k] {
					sharedDefaults.set(v, forKey: k)
				}
			}
			return ApiServer.configure(from: settings["DB_CONFIG_OBJECTS"] as! [String : [String : NSObject]])
			&& SnoozePreset.configure(from: settings["DB_SNOOZE_OBJECTS"] as! [[String : NSObject]])
		}
		return false
	}

	static func resetAllSettings() {
		for k in allFields {
			sharedDefaults.removeObject(forKey: k)
		}
	}

	///////////////////////////////// NUMBERS

	static let autoSnoozeDurationHelp = "How many days before an item is automatically snoozed. An item is auto-snoozed forever but will wake up on any comment, mention, or status update."
	static var autoSnoozeDuration: Int {
		get { return get("AUTO_SNOOZE_DAYS") as? Int ?? 0 }
		set { set("AUTO_SNOOZE_DAYS", newValue) }
	}

	static let sortMethodHelp = "The criterion to use when sorting items."
	static var sortMethod: Int {
		get { return get("SORT_METHOD_KEY") as? Int ?? 0 }
		set { set("SORT_METHOD_KEY", newValue) }
	}

	static var statusFilteringMode: Int {
		get { return get("STATUS_FILTERING_METHOD_KEY") as? Int ?? 0 }
		set { set("STATUS_FILTERING_METHOD_KEY", newValue) }
	}

	static var lastPreferencesTabSelected: Int {
		get { return get("LAST_PREFS_TAB_SELECTED") as? Int ?? 0 }
		set { set("LAST_PREFS_TAB_SELECTED", newValue) }
	}

	static var lastPreferencesTabSelectedOSX: Int {
		get { return get("LAST_PREFS_TAB_SELECTED_OSX") as? Int ?? 0 }
		set { set("LAST_PREFS_TAB_SELECTED_OSX", newValue) }
	}

	static let closeHandlingPolicyHelp = "How to handle an item when it is believed to be closed (or has disappeared)."
	static var closeHandlingPolicy: Int {
		get { return get("CLOSE_HANDLING_POLICY_2") as? Int ?? HandlingPolicy.keepMine.rawValue }
		set { set("CLOSE_HANDLING_POLICY_2", newValue) }
	}

	static let mergeHandlingPolicyHelp = "How to handle an item when it is detected as merged."
	static var mergeHandlingPolicy: Int {
		get { return get("MERGE_HANDLING_POLICY_2") as? Int ?? HandlingPolicy.keepMine.rawValue }
		set { set("MERGE_HANDLING_POLICY_2", newValue) }
	}

	static let statusItemRefreshBatchSizeHelp = "Because querying statuses can be bandwidth and time intensive, Trailer will scan for updates on items that haven't been scanned for the longest time, at every refresh, up to a maximum of this number of items. Higher values mean longer sync times and more API usage."
	static var statusItemRefreshBatchSize: Int {
		get { if let n = get("STATUS_ITEM_REFRESH_BATCH") as? Int { return n>0 ? n : 100 } else { return 100 } }
		set { set("STATUS_ITEM_REFRESH_BATCH", newValue) }
	}

	static var checkForUpdatesInterval: Int {
		get { return get("UPDATE_CHECK_INTERVAL_KEY") as? Int ?? 8 }
		set { set("UPDATE_CHECK_INTERVAL_KEY", newValue) }
	}

	static let assignedReviewHandlingPolicyHelp = "If an item is assigned for you to review, Trailer can move it to a specific section or leave it as-is."
	static var assignedReviewHandlingPolicy: Int {
		get { return get("ASSIGNED_REVIEW_HANDLING_POLICY") as? Int ?? 0 }
		set { set("ASSIGNED_REVIEW_HANDLING_POLICY", newValue) }
	}

	static let assignedPrHandlingPolicyHelp = "If an item is assigned to you, Trailer can move it to a specific section or leave it as-is."
	static var assignedPrHandlingPolicy: Int {
		get { return get("ASSIGNED_PR_HANDLING_POLICY") as? Int ?? 1 }
		set { set("ASSIGNED_PR_HANDLING_POLICY", newValue) }
	}

	static let displayPolicyForNewPrsHelp = "When a new repository is detected in your watchlist, this display policy will be applied by default to pull requests that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."
	static var displayPolicyForNewPrs: Int {
		get { return get("NEW_PR_DISPLAY_POLICY_INDEX") as? Int ?? RepoDisplayPolicy.hide.intValue }
		set { set("NEW_PR_DISPLAY_POLICY_INDEX", newValue) }
	}

	static let displayPolicyForNewIssuesHelp = "When a new repository is detected in your watchlist, this display policy will be applied by default to issues that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."
	static var displayPolicyForNewIssues: Int {
		get { return get("NEW_ISSUE_DISPLAY_POLICY_INDEX") as? Int ?? RepoDisplayPolicy.hide.intValue }
		set { set("NEW_ISSUE_DISPLAY_POLICY_INDEX", newValue) }
	}

	static let newMentionMovePolicyHelp = "If your username is mentioned in an item's description or a comment posted inside it, move the item to the specified section."
	static var newMentionMovePolicy: Int {
		get { return get("NEW_MENTION_MOVE_POLICY") as? Int ?? Section.mentioned.intValue }
		set { set("NEW_MENTION_MOVE_POLICY", newValue) }
	}

	static let teamMentionMovePolicyHelp = "If the name of one of the teams you belong to is mentioned in an item's description or a comment posted inside it, move the item to the specified section."
	static var teamMentionMovePolicy: Int {
		get { return get("TEAM_MENTION_MOVE_POLICY") as? Int ?? Section.mentioned.intValue }
		set { set("TEAM_MENTION_MOVE_POLICY", newValue) }
	}

	static let newItemInOwnedRepoMovePolicyHelp = "Automatically move an item to the specified section if it has been created in a repo which you own, even if there is no direct mention of you."
	static var newItemInOwnedRepoMovePolicy: Int {
		get { return get("NEW_ITEM_IN_OWNED_REPO_MOVE_POLICY") as? Int ?? Section.none.intValue }
		set { set("NEW_ITEM_IN_OWNED_REPO_MOVE_POLICY", newValue) }
	}

	/////////////////////////// STRINGS

	static var defaultAppForOpeningItems: String {
		get { return get("DEFAULT_APP_FOR_OPENING_ITEMS") as? String ?? "" }
		set { set("DEFAULT_APP_FOR_OPENING_ITEMS", newValue) }
	}

	static var defaultAppForOpeningWeb: String {
		get { return get("DEFAULT_APP_FOR_OPENING_WEB") as? String ?? "" }
		set { set("DEFAULT_APP_FOR_OPENING_WEB", newValue) }
	}

	static let statusFilteringTermsHelp = "You can specify specific terms which can then be matched against status items, in order to hide or show them."
	static var statusFilteringTerms: [String] {
		get { return get("STATUS_FILTERING_TERMS_KEY") as? [String] ?? [] }
		set { set("STATUS_FILTERING_TERMS_KEY", newValue) }
	}

	static var commentAuthorBlacklist: [String] {
		get { return get("COMMENT_AUTHOR_BLACKLIST") as? [String] ?? [] }
		set { set("COMMENT_AUTHOR_BLACKLIST", newValue) }
	}

	static var hotkeyLetter: String {
		get { return get("HOTKEY_LETTER") as? String ?? "T" }
		set { set("HOTKEY_LETTER", newValue) }
	}

	static var lastRunVersion: String {
		get { return S(get("LAST_RUN_VERSION_KEY") as? String) }
		set { set("LAST_RUN_VERSION_KEY", newValue) }
	}

	/////////////////////////// FLOATS

    #if os(iOS)
    static let backgroundRefreshPeriodHelp = "The minimum amount of time to wait before requesting an update when the app is in the background. Even though this is quite efficient, it's still a good idea to keep this to a high value in order to keep battery and bandwidth use low. The default of half an hour is generally a good number. Please note that iOS may ignore this value and perform background refreshes at longer intervals depending on battery level and other reasons."
    static var backgroundRefreshPeriod: TimeInterval {
        get { if let n = get("IOS_BACKGROUND_REFRESH_PERIOD_KEY") as? TimeInterval { return n > 0 ? n : 1800 } else { return 1800 } }
        set {
            set("IOS_BACKGROUND_REFRESH_PERIOD_KEY", newValue)
        }
    }
    #else
    static let refreshPeriodHelp = "How often to refresh items when the app is active and in the foreground."
    static var refreshPeriod: TimeInterval {
        get { if let n = get("REFRESH_PERIOD_KEY") as? TimeInterval { return n < 60 ? 120 : n } else { return 120 } }
        set { set("REFRESH_PERIOD_KEY", newValue) }
    }
    #endif

	static let newRepoCheckPeriodHelp = "How long before reloading your team list and watched repositories from a server. Since this doesn't change often, it's good to keep this as high as possible in order to keep bandwidth use as low as possible during refreshes. Set this to a lower value if you often update your watched repositories or teams."
	static var newRepoCheckPeriod: Float {
		get { if let n = get("NEW_REPO_CHECK_PERIOD") as? Float { return max(n, 2) } else { return 2 } }
		set { set("NEW_REPO_CHECK_PERIOD", newValue) }
	}

	/////////////////////////// DATES

    static var lastSuccessfulRefresh: Date? {
        get { return get("LAST_SUCCESSFUL_REFRESH") as? Date }
        set { set("LAST_SUCCESSFUL_REFRESH", newValue) }
    }

	static var lastExportDate: Date? {
		get { return get("LAST_EXPORT_TIME") as? Date }
		set { set("LAST_EXPORT_TIME", newValue) }
	}

	/////////////////////////// URLs

	static var lastExportUrl: URL? {
		get {
			if let s = get("LAST_EXPORT_URL") as? String {
				return URL(string: s)
			} else {
				return nil
			}
		}
		set { set("LAST_EXPORT_URL", newValue?.absoluteString) }
	}

    /////////////////////////// SWITCHES

	static let hideArchivedReposHelp = "Automatically hide repositories which have been marked as archived"
	static var hideArchivedRepos: Bool {
		get { return get("HIDE_ARCHIVED_REPOS") as? Bool ?? false }
		set { set("HIDE_ARCHIVED_REPOS", newValue) }
	}

	static let hideMenubarCountsHelp = "Hide the counts of items in each status item in the menubar"
	static var hideMenubarCounts: Bool {
		get { return get("HIDE_MENUBAR_COUNTS") as? Bool ?? false }
		set { set("HIDE_MENUBAR_COUNTS", newValue) }
	}

	static let hideSnoozedItemsHelp = "Hide the snoozed items section"
	static var hideSnoozedItems: Bool {
		get { return get("HIDE_SNOOZED_ITEMS") as? Bool ?? false }
		set { set("HIDE_SNOOZED_ITEMS", newValue) }
	}

	static let hideUncommentedItemsHelp = "Only show items which have red number badges."
	static var hideUncommentedItems: Bool {
		get { return get("HIDE_UNCOMMENTED_PRS_KEY") as? Bool ?? false }
		set { set("HIDE_UNCOMMENTED_PRS_KEY", newValue) }
	}

	static let showCommentsEverywhereHelp = "Badge and send notificatons for items in the 'all' sections as well as your own and participated ones."
	static var showCommentsEverywhere: Bool {
		get { return get("SHOW_COMMENTS_EVERYWHERE_KEY") as? Bool ?? false }
		set { set("SHOW_COMMENTS_EVERYWHERE_KEY", newValue) }
	}

	static let sortDescendingHelp = "The direction to sort items based on the criterion below. Toggling this option will change the set of options available in the option below to better reflect what that will do."
	static var sortDescending: Bool {
		get { return get("SORT_ORDER_KEY") as? Bool ?? false }
		set { set("SORT_ORDER_KEY", newValue) }
	}

	static let showCreatedInsteadOfUpdatedHelp = "Trailer will usually display the time of the most recent activity in an item, such as comments. This setting replaces that with the orignal creation time of the item. Together with the sorting options, this is useful for helping prioritise items based on how old, or new, they are."
	static var showCreatedInsteadOfUpdated: Bool {
		get { return get("SHOW_UPDATED_KEY") as? Bool ?? false }
		set { set("SHOW_UPDATED_KEY", newValue) }
	}

	static let dontKeepPrsMergedByMeHelp = "If a PR is detected as merged by you, remove it immediately from the list of merged items"
	static var dontKeepPrsMergedByMe: Bool {
		get { return get("DONT_KEEP_MY_PRS_KEY") as? Bool ?? false }
		set { set("DONT_KEEP_MY_PRS_KEY", newValue) }
	}

	static let hideAvatarsHelp = "Hide the image of the author's avatar which is usually shown on the left of listed items"
	static var hideAvatars: Bool {
		get { return get("HIDE_AVATARS_KEY") as? Bool ?? false }
		set { set("HIDE_AVATARS_KEY", newValue) }
	}

	static let dontAskBeforeWipingMergedHelp = "Don't ask for confirmation when you select 'Remove all merged items'. Please note there is no confirmation when selecting this from the Apple Watch, irrespective of this setting."
	static var dontAskBeforeWipingMerged: Bool {
		get { return get("DONT_ASK_BEFORE_WIPING_MERGED") as? Bool ?? false }
		set { set("DONT_ASK_BEFORE_WIPING_MERGED", newValue) }
	}

	static let dontAskBeforeWipingClosedHelp = "Don't ask for confirmation when you select 'Remove all closed items'. Please note there is no confirmation when selecting this from the Apple Watch, irrespective of this setting."
	static var dontAskBeforeWipingClosed: Bool {
		get { return get("DONT_ASK_BEFORE_WIPING_CLOSED") as? Bool ?? false }
		set { set("DONT_ASK_BEFORE_WIPING_CLOSED", newValue) }
	}

	static let groupByRepoHelp = "Sort and gather items from the same repository next to each other, before applying the criterion specified above."
	static var groupByRepo: Bool {
		get { return get("GROUP_BY_REPO") as? Bool ?? false }
		set { set("GROUP_BY_REPO", newValue) }
	}

	static let showLabelsHelp = "Show labels associated with items, usually a good idea"
	static var showLabels: Bool {
		get { return get("SHOW_LABELS") as? Bool ?? false }
		set { set("SHOW_LABELS", newValue) }
	}

	static let showStatusItemsHelp = "Show status items, such as CI results or messages from code review services, that are attached to items on the server."
	static var showStatusItems: Bool {
		get { return get("SHOW_STATUS_ITEMS") as? Bool ?? false }
		set { set("SHOW_STATUS_ITEMS", newValue) }
	}

	static let makeStatusItemsSelectableHelp = "Normally you have to Cmd-click on status items to visit their relayed links, this option makes them always selectable, but it makes it easier to accidentally end up opening a status item page instead of an item's page."
	static var makeStatusItemsSelectable: Bool {
		get { return get("MAKE_STATUS_ITEMS_SELECTABLE") as? Bool ?? false }
		set { set("MAKE_STATUS_ITEMS_SELECTABLE", newValue) }
	}

	static let openPrAtFirstUnreadCommentHelp = "When opening the web view for an item, skip directly down to the first comment that has not been read, rather than starting from the top of the item's web page."
	static var openPrAtFirstUnreadComment: Bool {
		get { return get("OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY") as? Bool ?? false }
		set { set("OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY", newValue) }
	}

	static let logActivityToConsoleHelp = "This is meant for troubleshooting and should be turned off usually, as it is a performance and security concern when activated. It will output detailed messages about the app's behaviour in the device console."
	static var logActivityToConsole: Bool {
		get {
        #if DEBUG
            return true
        #else
            return get("LOG_ACTIVITY_TO_CONSOLE_KEY") as? Bool ?? false
        #endif
        }
		set { set("LOG_ACTIVITY_TO_CONSOLE_KEY", newValue) }
	}

	static var hotkeyEnable: Bool {
		get { return get("HOTKEY_ENABLE") as? Bool ?? false }
		set { set("HOTKEY_ENABLE", newValue) }
	}

	static var hotkeyControlModifier: Bool {
		get { return get("HOTKEY_CONTROL_MODIFIER") as? Bool ?? false }
		set { set("HOTKEY_CONTROL_MODIFIER", newValue) }
	}

	static let disableAllCommentNotificationsHelp = "Do not get notified about any comments at all."
    static var disableAllCommentNotifications: Bool {
        get { return get("DISABLE_ALL_COMMENT_NOTIFICATIONS") as? Bool ?? false }
        set { set("DISABLE_ALL_COMMENT_NOTIFICATIONS", newValue) }
    }

	static let notifyOnStatusUpdatesHelp = "Post notifications when status items change. Useful for tracking the CI build state of your own items, for instance."
    static var notifyOnStatusUpdates: Bool {
        get { return get("NOTIFY_ON_STATUS_UPDATES") as? Bool ?? false }
        set { set("NOTIFY_ON_STATUS_UPDATES", newValue) }
    }

	static let notifyOnStatusUpdatesForAllPrsHelp = "Notificaitons for status items are sent only for your own and particiapted items by default. Select this to receive status update notifications for the items in the 'all' section too."
    static var notifyOnStatusUpdatesForAllPrs: Bool {
        get { return get("NOTIFY_ON_STATUS_UPDATES_ALL") as? Bool ?? false }
        set { set("NOTIFY_ON_STATUS_UPDATES_ALL", newValue) }
    }

	static let preferIssuesInWatchHelp = "If there is only enough space to display one count or set of statistics on the Apple Watch, prefer the ones for issues rather than the ones for PRs."
	static var preferIssuesInWatch: Bool {
		get { return get("SHOW_ISSUES_IN_WATCH_GLANCE") as? Bool ?? false }
		set { set("SHOW_ISSUES_IN_WATCH_GLANCE", newValue) }
	}

	static let hideDescriptionInWatchDetailHelp = "When showing the full detail view of items on the Apple Watch, skip showing the description of the item, instead showing only status and comments for it."
	static var hideDescriptionInWatchDetail: Bool {
		get { return get("HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW") as? Bool ?? false }
		set { set("HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW", newValue) }
	}

	static var autoRepeatSettingsExport: Bool {
		get { return get("AUTO_REPEAT_SETTINGS_EXPORT") as? Bool ?? false }
		set { set("AUTO_REPEAT_SETTINGS_EXPORT", newValue) }
	}

	static var dontConfirmSettingsImport: Bool {
		get { return get("DONT_CONFIRM_SETTINGS_IMPORT") as? Bool ?? false }
		set { set("DONT_CONFIRM_SETTINGS_IMPORT", newValue) }
	}

	static let removeNotificationsWhenItemIsRemovedHelp = "When an item is removed, whether through user action or automatically due to settings, also remove any notifications in the Notification Center that are related to this item."
	static var removeNotificationsWhenItemIsRemoved: Bool {
		get { return get("REMOVE_RELATED_NOTIFICATIONS_ON_ITEM_REMOVE") as? Bool ?? true }
		set { set("REMOVE_RELATED_NOTIFICATIONS_ON_ITEM_REMOVE", newValue) }
	}

	static let includeServersInFilterHelp = "Check the name of the server an item came from when selecting it for inclusion in filtered results. You can also prefix a search with 'server:' to specifically search for this."
    static var includeServersInFilter: Bool {
        get { return get("INCLUDE_SERVERS_IN_FILTER") as? Bool ?? false }
        set { set("INCLUDE_SERVERS_IN_FILTER", newValue) }
    }

	static let dumpAPIResponsesInConsoleHelp = "This is meant for troubleshooting and should be turned off usually, as it is a performance and security concern when activated. It will output the full request and responses to and from API servers in the device console."
	static var dumpAPIResponsesInConsole: Bool {
		get { return get("DUMP_API_RESPONSES_IN_CONSOLE") as? Bool ?? false }
		set { set("DUMP_API_RESPONSES_IN_CONSOLE", newValue) }
	}

	static let hidePrsThatArentPassingHelp = "Hide PR items which have status items, but are not all green. Useful for hiding PRs which are not ready to review or those who have not passed certain checks yet."
	static var hidePrsThatArentPassing: Bool {
		get { return get("HIDE_PRS_THAT_ARENT_PASSING") as? Bool ?? false }
		set { set("HIDE_PRS_THAT_ARENT_PASSING", newValue) }
	}

	static let hidePrsThatDontPassOnlyInAllHelp = "Normally hiding red PRs will happen on every section. Selecting this will limit that filter to the 'All' section only, so red PRs which are yours or you have participated in will still show up."
	static var hidePrsThatDontPassOnlyInAll: Bool {
		get { return get("HIDE_PRS_THAT_ARENT_PASSING_ONLY_IN_ALL") as? Bool ?? false }
		set { set("HIDE_PRS_THAT_ARENT_PASSING_ONLY_IN_ALL", newValue) }
	}

	static let snoozeWakeOnCommentHelp = "Wake up snoozing items if a new comment is made"
	static let snoozeWakeOnMentionHelp = "Wake up snoozing items in you are mentioned in a new comment"
	static let snoozeWakeOnStatusUpdateHelp = "Wake up snoozing items if there is a status or CI update"

	static let showMilestonesHelp = "Include milestone information, if any, on current items."
	static var showMilestones: Bool {
		get { return get("DISPLAY_MILESTONES") as? Bool ?? false }
		set { set("DISPLAY_MILESTONES", newValue) }
	}

	static let showRelativeDatesHelp = "Show relative dates to now, e.g. '6d, 4h ago' instead of '12 May 2017, 11:00"
	static var showRelativeDates: Bool {
		get { return get("SHOW_RELATIVE_DATES") as? Bool ?? false }
		set { set("SHOW_RELATIVE_DATES", newValue) }
	}

	static let notifyOnReviewChangeRequestsHelp = "Issue a notification when someone creates a review in a PR that requires changes."
	static var notifyOnReviewChangeRequests: Bool {
		get { return get("NOTIFY_ON_REVIEW_CHANGE_REQUESTS") as? Bool ?? false }
		set { set("NOTIFY_ON_REVIEW_CHANGE_REQUESTS", newValue) }
	}

	static let notifyOnReviewAcceptancesHelp = "Issue a notification when someone accepts the changes related to a review in a PR that required changes."
	static var notifyOnReviewAcceptances: Bool {
		get { return get("NOTIFY_ON_REVIEW_ACCEPTANCES") as? Bool ?? false }
		set { set("NOTIFY_ON_REVIEW_ACCEPTANCES", newValue) }
	}

	static let notifyOnReviewDismissalsHelp = "Issue a notification when someone dismissed a review in a PR that required changes."
	static var notifyOnReviewDismissals: Bool {
		get { return get("NOTIFY_ON_REVIEW_DISMISSALS") as? Bool ?? false }
		set { set("NOTIFY_ON_REVIEW_DISMISSALS", newValue) }
	}

	static let notifyOnAllReviewChangeRequestsHelp = "Do this for all items, not just those created by me."
	static var notifyOnAllReviewChangeRequests: Bool {
		get { return get("NOTIFY_ON_ALL_REVIEW_CHANGE_REQUESTS") as? Bool ?? false }
		set { set("NOTIFY_ON_ALL_REVIEW_CHANGE_REQUESTS", newValue) }
	}

	static let notifyOnAllReviewAcceptancesHelp = "Do this for all items, not just those created by me."
	static var notifyOnAllReviewAcceptances: Bool {
		get { return get("NOTIFY_ON_ALL_REVIEW_ACCEPTANCES") as? Bool ?? false }
		set { set("NOTIFY_ON_ALL_REVIEW_ACCEPTANCES", newValue) }
	}

	static let notifyOnAllReviewDismissalsHelp = "Do this for all items, not just those created by me."
	static var notifyOnAllReviewDismissals: Bool {
		get { return get("NOTIFY_ON_ALL_REVIEW_DISMISSALS") as? Bool ?? false }
		set { set("NOTIFY_ON_ALL_REVIEW_DISMISSALS", newValue) }
	}

	static let notifyOnReviewAssignmentsHelp = "Issue a notification when someone assigns me a PR to review."
	static var notifyOnReviewAssignments: Bool {
		get { return get("NOTIFY_ON_REVIEW_ASSIGNMENTS") as? Bool ?? false }
		set { set("NOTIFY_ON_REVIEW_ASSIGNMENTS", newValue) }
	}

	static let showStatusesOnAllItemsHelp = "Show statuses in the 'all' section too."
	static var showStatusesOnAllItems: Bool {
		get { return get("SHOW_STATUSES_EVERYWHERE") as? Bool ?? false }
		set { set("SHOW_STATUSES_EVERYWHERE", newValue) }
	}


	static let checkForUpdatesAutomaticallyHelp = "Check for updates to Trailer automatically. It is generally a very good idea to keep this selected, unless you are using an external package manager to manage the updates."
	static var checkForUpdatesAutomatically: Bool {
		get { return get("UPDATE_CHECK_AUTO_KEY") as? Bool ?? true }
		set { set("UPDATE_CHECK_AUTO_KEY", newValue) }
	}

	static let showReposInNameHelp = "Show the name of the repository each item comes from."
	static var showReposInName: Bool {
		get { return get("SHOW_REPOS_IN_NAME") as? Bool ?? true }
		set { set("SHOW_REPOS_IN_NAME", newValue) }
	}

	static let includeTitlesInFilterHelp = "Check item titles when selecting items for inclusion in filtered results. You can also prefix a search with 'title:' to specifically search for this."
	static var includeTitlesInFilter: Bool {
		get { return get("INCLUDE_TITLES_IN_FILTER") as? Bool ?? true }
		set { set("INCLUDE_TITLES_IN_FILTER", newValue) }
	}

	static let markPrsAsUnreadOnNewCommitsHelp = "Mark a PR with an exclamation mark even if they it may not have unread comments, in case there have been new commits from other users."
	static var markPrsAsUnreadOnNewCommits: Bool {
		get { return get("MARK_PRS_AS_UNREAD_ON_NEW_COMMITS") as? Bool ?? false }
		set { set("MARK_PRS_AS_UNREAD_ON_NEW_COMMITS", newValue) }
	}

	static let includeMilestonesInFilterHelp = "Check item milestone names for inclusion in filtered results. You can also prefix a search with 'milestone:' to specifically search for this."
	static var includeMilestonesInFilter: Bool {
		get { return get("INCLUDE_MILESTONES_IN_FILTER") as? Bool ?? false }
		set { set("INCLUDE_MILESTONES_IN_FILTER", newValue) }
	}

	static let includeAssigneeInFilterHelp = "Check item assignee names for inclusion in filtered results. You can also prefix a search with 'assignee:' to specifically search for this."
	static var includeAssigneeNamesInFilter: Bool {
		get { return get("INCLUDE_ASSIGNEE_NAMES_IN_FILTER") as? Bool ?? false }
		set { set("INCLUDE_ASSIGNEE_NAMES_IN_FILTER", newValue) }
	}

	static let includeNumbersInFilterHelp = "Check the PR/Issue number of the item when selecting it for inclusion in filtered results. You can also prefix a search with 'number:' to specifically search for this."
	static var includeNumbersInFilter: Bool {
		get { return get("INCLUDE_NUMBERS_IN_FILTER") as? Bool ?? false }
		set { set("INCLUDE_NUMBERS_IN_FILTER", newValue) }
	}

	static let includeReposInFilterHelp = "Check repository names when selecting items for inclusion in filtered results. You can also prefix a search with 'repo:' to specifically search for this."
	static var includeReposInFilter: Bool {
		get { return get("INCLUDE_REPOS_IN_FILTER") as? Bool ?? true }
		set { set("INCLUDE_REPOS_IN_FILTER", newValue) }
	}

	static let includeLabelsInFilterHelp = "Check labels of items when selecting items for inclusion in filtered results. You can also prefix a search with 'label:' to specifically search for this."
	static var includeLabelsInFilter: Bool {
		get { return get("INCLUDE_LABELS_IN_FILTER") as? Bool ?? true }
		set { set("INCLUDE_LABELS_IN_FILTER", newValue) }
	}

	static let automaticallyAddNewReposFromWatchlistHelp = "Automatically add to Trailer any repos are added to your remote watchlist"
	static var automaticallyAddNewReposFromWatchlist: Bool {
		get { return get("AUTO_ADD_NEW_REPOS") as? Bool ?? true }
		set { set("AUTO_ADD_NEW_REPOS", newValue) }
	}

	static let automaticallyRemoveDeletedReposFromWatchlistHelp = "Automatically remove from Trailer any (previously automatically added) repos if they are no longer on your remote watchlist"
	static var automaticallyRemoveDeletedReposFromWatchlist: Bool {
		get { return get("AUTO_REMOVE_DELETED_REPOS") as? Bool ?? true }
		set { set("AUTO_REMOVE_DELETED_REPOS", newValue) }
	}

	static let includeUsersInFilterHelp = "Check the name of the author of an item when selecting it for inclusion in filtered results. You can also prefix a search with 'user:' to specifically search for this."
    static var includeUsersInFilter: Bool {
        get { return get("INCLUDE_USERS_IN_FILTER") as? Bool ?? true }
        set { set("INCLUDE_USERS_IN_FILTER", newValue) }
    }

	static let includeStatusesInFilterHelp = "Check status lines of items when selecting items for inclusion in filtered results. You can also prefix a search with 'status:' to specifically search for this."
	static var includeStatusesInFilter: Bool {
		get { return get("INCLUDE_STATUSES_IN_FILTER") as? Bool ?? true }
		set { set("INCLUDE_STATUSES_IN_FILTER", newValue) }
	}

	static var hotkeyCommandModifier: Bool {
		get { return get("HOTKEY_COMMAND_MODIFIER") as? Bool ?? true }
		set { set("HOTKEY_COMMAND_MODIFIER", newValue) }
	}

	static var hotkeyOptionModifier: Bool {
		get { return get("HOTKEY_OPTION_MODIFIER") as? Bool ?? true }
		set { set("HOTKEY_OPTION_MODIFIER", newValue) }
	}

	static var hotkeyShiftModifier: Bool {
		get { return get("HOTKEY_SHIFT_MODIFIER") as? Bool ?? true }
		set { set("HOTKEY_SHIFT_MODIFIER", newValue) }
	}

	static let grayOutWhenRefreshingHelp = "Gray out the menubar icon when refreshing data from the configured servers. You may want to turn this off if you find that distracting or use a menu bar management tool that automatically highlights menubar items which get updated"
    static var grayOutWhenRefreshing: Bool {
		get { return get("GRAY_OUT_WHEN_REFRESHING") as? Bool ?? true }
		set { set("GRAY_OUT_WHEN_REFRESHING", newValue) }
    }

	static let showSeparateApiServersInMenuHelp = "Show each API server as a separate item on the menu bar"
	static var showSeparateApiServersInMenu: Bool {
		get { return get("API_SERVERS_IN_SEPARATE_MENUS") as? Bool ?? false }
		set { set("API_SERVERS_IN_SEPARATE_MENUS", newValue) }
	}

    static let queryAuthoredPRsHelp = "Query all authored PRs for the current user, irrespective of repository visibility or if the repository is in the watchlist."
    static var queryAuthoredPRs: Bool {
        get { return get("QUERY_AUTHORED_PRS") as? Bool ?? false }
        set { set("QUERY_AUTHORED_PRS", newValue) }
    }

    static let queryAuthoredIssuesHelp = "Query all authored issues for the current user, irrespective of repository visibility or if the repository is in the watchlist."
    static var queryAuthoredIssues: Bool {
        get { return get("QUERY_AUTHORED_ISSUES") as? Bool ?? false }
        set { set("QUERY_AUTHORED_ISSUES", newValue) }
    }

	static let assumeReadItemIfUserHasNewerCommentsHelp = "Mark any comments posted by others before your own as read. Warning: Only turn this on if you are sure you can catch any comments that others may add while you are adding yours! (This is a very useful setting for *secondary* Trailer displays)"
	static var assumeReadItemIfUserHasNewerComments: Bool {
		get { return get("ASSUME_READ_ITEM_IF_USER_HAS_NEWER_COMMENTS") as? Bool ?? false }
		set { set("ASSUME_READ_ITEM_IF_USER_HAS_NEWER_COMMENTS", newValue) }
	}

	static let displayReviewsOnItemsHelp = "List requested, approving, and blocking reviews in the list of Pull Requests."
	static var displayReviewsOnItems: Bool {
		get { return get("DISPLAY_REVIEW_CHANGE_REQUESTS") as? Bool ?? false }
		set { set("DISPLAY_REVIEW_CHANGE_REQUESTS", newValue) }
	}

    static let reactionScanningBatchSizeHelp = "Because querying reactions can be bandwidth and time intensive, Trailer will scan for updates on items that haven't been scanned for the longest time, at every refresh, up to a maximum of this number of items. Higher values mean longer sync times and more API usage."
	static var reactionScanningBatchSize: Int {
		get { return get("REACTION_SCANNING_BATCH") as? Int ?? 100 }
		set { set("REACTION_SCANNING_BATCH", newValue) }
	}

	static let notifyOnItemReactionsHelp = "Count reactions to PRs and issues as comments. Increase the total count. Notify and badge an item as unread depending on the comment section settings."
	static var notifyOnItemReactions: Bool {
		get { return get("NOTIFY_ON_ITEM_REACTIONS") as? Bool ?? false }
		set { set("NOTIFY_ON_ITEM_REACTIONS", newValue) }
	}

	static let notifyOnCommentReactionsHelp = "Count reactions to comments themselves as comments. Increase the total count of the item that contains the comment being reacted to. Notify and badge it as unread depending on the comment section settings."
	static var notifyOnCommentReactions: Bool {
		get { return get("NOTIFY_ON_COMMENT_REACTIONS") as? Bool ?? false }
		set { set("NOTIFY_ON_COMMENT_REACTIONS", newValue) }
	}

	static let displayNumbersForItemsHelp = "Prefix titles of items with the number of the referenced PR or issue."
	static var displayNumbersForItems: Bool {
		get { return get("DISPLAY_NUMBERS_FOR_ITEMS") as? Bool ?? false }
		set { set("DISPLAY_NUMBERS_FOR_ITEMS", newValue) }
	}
    
    static let draftHandlingPolicyHelp = "How to deal with a PR if it is marked as a draft."
    static var draftHandlingPolicy: Int {
        get { return get("DRAFT_HANDLING_POLICY") as? Int ?? 0 }
        set { set("DRAFT_HANDLING_POLICY", newValue) }
    }

	static let countVisibleSnoozedItemsHelp = "Include visible snoozed items in menubar count."
	static var countVisibleSnoozedItems: Bool {
		get { return get("COUNT_VISIBLE_SNOOZED_ITEMS") as? Bool ?? true }
		set { set("COUNT_VISIBLE_SNOOZED_ITEMS", newValue) }
	}
    
    static let markUnmergeablePrsHelp = "Indicate PRs which cannot be merged. This option only works for items synced via the new v4 API."
    static var markUnmergeablePrs: Bool {
        get { return get("MARK_UNMERGEABLE_ITEMS") as? Bool ?? false }
        set { set("MARK_UNMERGEABLE_ITEMS", newValue) }
    }
    
    static let showPrLinesHelp = "Sync and show the number of lines added and/or removed on PRs. This option only works for items synced via the new v4 API."
    static var showPrLines: Bool {
        get { return get("SHOW_PR_LINES") as? Bool ?? false }
        set { set("SHOW_PR_LINES", newValue) }
    }

    static let scanClosedAndMergedItemsHelp = "Also highlight unread comments on closed and merged items. This option only works for items synced via the new v4 API."
    static var scanClosedAndMergedItems: Bool {
        get { return get("SCAN_CLOSED_AND_MERGED") as? Bool ?? false }
        set { set("SCAN_CLOSED_AND_MERGED", newValue) }
    }
    
    static let showRequestedTeamReviewsHelp = "Display the name(s) of teams which have been assigned as reviewers on PRs"
    static var showRequestedTeamReviews: Bool {
        get { return get("REQUESTED_TEAM_REVIEWS") as? Bool ?? false }
        set { set("REQUESTED_TEAM_REVIEWS", newValue) }
    }

    static let v4title = "Can't be turned on yet"
    static let v4DBMessage = "Your repo list seems to contain entries which have not yet been migrated in order to be able to use the new API.\n\nYou will have to perform a sync before being able to turn this setting on."
    static let v4DAPIessage = "One of your servers doesn't have a v4 API path defined. Please configure this before turning on v4 API support."
    static let useV4APIHelp = "In cases where the new v4 API is available, such as the public GitHub server, using it can result in significant efficiency and speed improvements when syncing."
    static var useV4API: Bool {
        get { return get("USE_V4_API") as? Bool ?? false }
        set { set("USE_V4_API", newValue) }
    }
    
    static let reloadAllDataHelp = "Chosing this option will remove all synced data and reload everything from scratch. This can take a while and use up a large amount of API quota, so only use it if things seem broken."
}
