
#if os(iOS)
	import UIKit
#endif

final class Settings {

	private static var valuesCache = [AnyHashable : Any]()
	private static let sharedDefaults = UserDefaults(suiteName: "group.Trailer")!

	private class var allFields: [String] {
		return [
			"SORT_METHOD_KEY", "STATUS_FILTERING_METHOD_KEY", "LAST_PREFS_TAB_SELECTED", "STATUS_ITEM_REFRESH_COUNT", "LABEL_REFRESH_COUNT", "UPDATE_CHECK_INTERVAL_KEY",
			"STATUS_FILTERING_TERMS_KEY", "COMMENT_AUTHOR_BLACKLIST", "HOTKEY_LETTER", "REFRESH_PERIOD_KEY", "IOS_BACKGROUND_REFRESH_PERIOD_KEY", "NEW_REPO_CHECK_PERIOD", "LAST_SUCCESSFUL_REFRESH",
			"LAST_RUN_VERSION_KEY", "UPDATE_CHECK_AUTO_KEY", "HIDE_UNCOMMENTED_PRS_KEY", "SHOW_COMMENTS_EVERYWHERE_KEY", "SORT_ORDER_KEY", "SHOW_UPDATED_KEY", "DONT_KEEP_MY_PRS_KEY", "HIDE_AVATARS_KEY",
			"DONT_ASK_BEFORE_WIPING_MERGED", "DONT_ASK_BEFORE_WIPING_CLOSED", "HIDE_NEW_REPOS_KEY", "GROUP_BY_REPO", "HIDE_ALL_SECTION", "SHOW_LABELS", "SHOW_STATUS_ITEMS",
			"MAKE_STATUS_ITEMS_SELECTABLE", "MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY", "COUNT_ONLY_LISTED_PRS", "OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY", "LOG_ACTIVITY_TO_CONSOLE_KEY",
			"HOTKEY_ENABLE", "HOTKEY_CONTROL_MODIFIER", "USE_VIBRANCY_UI", "DISABLE_ALL_COMMENT_NOTIFICATIONS", "NOTIFY_ON_STATUS_UPDATES", "NOTIFY_ON_STATUS_UPDATES_ALL", "SHOW_REPOS_IN_NAME", "INCLUDE_REPOS_IN_FILTER",
			"INCLUDE_LABELS_IN_FILTER", "INCLUDE_STATUSES_IN_FILTER", "HOTKEY_COMMAND_MODIFIER", "HOTKEY_OPTION_MODIFIER", "HOTKEY_SHIFT_MODIFIER", "GRAY_OUT_WHEN_REFRESHING", "SHOW_ISSUES_MENU",
			"SHOW_ISSUES_IN_WATCH_GLANCE", "ASSIGNED_PR_HANDLING_POLICY", "HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW", "AUTO_REPEAT_SETTINGS_EXPORT", "DONT_CONFIRM_SETTINGS_IMPORT",
			"LAST_EXPORT_URL", "LAST_EXPORT_TIME", "CLOSE_HANDLING_POLICY_2", "MERGE_HANDLING_POLICY_2", "LAST_PREFS_TAB_SELECTED_OSX", "NEW_PR_DISPLAY_POLICY_INDEX", "NEW_ISSUE_DISPLAY_POLICY_INDEX", "HIDE_PRS_THAT_ARENT_PASSING_ONLY_IN_ALL",
            "INCLUDE_SERVERS_IN_FILTER", "INCLUDE_USERS_IN_FILTER", "INCLUDE_TITLES_IN_FILTER", "INCLUDE_NUMBERS_IN_FILTER", "DUMP_API_RESPONSES_IN_CONSOLE", "OPEN_ITEMS_DIRECTLY_IN_SAFARI", "HIDE_PRS_THAT_ARENT_PASSING",
            "REMOVE_RELATED_NOTIFICATIONS_ON_ITEM_REMOVE", "HIDE_SNOOZED_ITEMS", "INCLUDE_MILESTONES_IN_FILTER", "INCLUDE_ASSIGNEE_NAMES_IN_FILTER", "API_SERVERS_IN_SEPARATE_MENUS", "ASSUME_READ_ITEM_IF_USER_HAS_NEWER_COMMENTS",
            "AUTO_SNOOZE_DAYS", "HIDE_MENUBAR_COUNTS", "AUTO_ADD_NEW_REPOS", "AUTO_REMOVE_DELETED_REPOS", "MARK_PRS_AS_UNREAD_ON_NEW_COMMITS"]
	}

    class func checkMigration() {

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

		sharedDefaults.synchronize()
	}

	private class func set(_ key: String, _ value: Any?) {

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
		valuesCache[key] = value
		sharedDefaults.synchronize()

		if let v = value {
			DLog("Setting %@ to %@", key, String(describing: v))
		} else {
			DLog("Clearing option %@", key)
		}

		possibleExport(key)
	}

	private static let saveTimer = { () -> PopTimer in
		return PopTimer(timeInterval: 2.0) {
			if let e = Settings.lastExportUrl {
				Settings.writeToURL(e)
			}
		}
	}()

	class func possibleExport(_ key: String?) {
		#if os(OSX)
		let keyIsGood: Bool
		if let k = key {
			keyIsGood = !["LAST_SUCCESSFUL_REFRESH", "LAST_EXPORT_URL", "LAST_EXPORT_TIME"].contains(k)
		} else {
			keyIsGood = true
		}
		if Settings.autoRepeatSettingsExport && keyIsGood && Settings.lastExportUrl != nil {
			saveTimer.push()
		}
		#endif
	}

	private class func get(_ key: String) -> Any? {
		if let v = valuesCache[key] {
			return v
		} else if let v = sharedDefaults.object(forKey: key) {
			valuesCache[key] = v
			return v
		} else {
			return nil
		}
	}

	///////////////////////////////// IMPORT / EXPORT

	@discardableResult
	class func writeToURL(_ url: URL) -> Bool {

		saveTimer.invalidate()

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
		NotificationCenter.default.post(name: SettingsExportedNotification, object: nil)
		DLog("Written settings to %@", url.absoluteString)
		return true
	}

	class func readFromURL(_ url: URL) -> Bool {
		if let settings = NSDictionary(contentsOf: url) {
			DLog("Reading settings from %@", url.absoluteString)
			resetAllSettings()
			for k in allFields {
				if let v = settings[k] {
					sharedDefaults.set(v, forKey: k)
				}
			}
			sharedDefaults.synchronize()
			valuesCache.removeAll(keepingCapacity: false)
			return ApiServer.configure(from: settings["DB_CONFIG_OBJECTS"] as! [String : [String : NSObject]])
			&& SnoozePreset.configure(from: settings["DB_SNOOZE_OBJECTS"] as! [[String : NSObject]])
		}
		return false
	}

	class func resetAllSettings() {
		for k in allFields {
			sharedDefaults.removeObject(forKey: k)
		}
		sharedDefaults.synchronize()
		valuesCache.removeAll(keepingCapacity: false)
	}

	///////////////////////////////// NUMBERS

	static let autoSnoozeDurationHelp = "How many days before an item is automatically snoozed. An item is auto-snoozed forever but will wake up on any comment, mention, or status update."
	class var autoSnoozeDuration: Int {
		get { return get("AUTO_SNOOZE_DAYS") as? Int ?? 0 }
		set { set("AUTO_SNOOZE_DAYS", newValue) }
	}

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
		get { return get("CLOSE_HANDLING_POLICY_2") as? Int ?? HandlingPolicy.keepMine.rawValue }
		set { set("CLOSE_HANDLING_POLICY_2", newValue) }
	}

	static let mergeHandlingPolicyHelp = "How to handle an item when it is detected as merged."
	class var mergeHandlingPolicy: Int {
		get { return get("MERGE_HANDLING_POLICY_2") as? Int ?? HandlingPolicy.keepMine.rawValue }
		set { set("MERGE_HANDLING_POLICY_2", newValue) }
	}

	static let statusItemRefreshIntervalHelp = "Because querying statuses can be bandwidth-intensive, if you have a lot of items in your lists, you may want to raise this to a higher value. You can always see how much API usage you have left per-hour from the 'Servers' tab."
	class var statusItemRefreshInterval: Int {
		get { if let n = get("STATUS_ITEM_REFRESH_COUNT") as? Int { return n>0 ? n : 10 } else { return 10 } }
		set { set("STATUS_ITEM_REFRESH_COUNT", newValue) }
	}

	static let labelRefreshIntervalHelp = "Querying labels can be moderately bandwidth-intensive, but it does involve making some extra API calls. Since labels don't change often, you may want to raise this to a higher value if you have a lot of items on your lists. You can always see how much API usage you have left per-hour from the 'Servers' tab."
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
		get { return get("NEW_PR_DISPLAY_POLICY_INDEX") as? Int ?? RepoDisplayPolicy.all.intValue }
		set { set("NEW_PR_DISPLAY_POLICY_INDEX", newValue) }
	}

	static let displayPolicyForNewIssuesHelp = "When a new repository is detected in your watchlist, this display policy will be applied by default to issues that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."
	class var displayPolicyForNewIssues: Int {
		get { return get("NEW_ISSUE_DISPLAY_POLICY_INDEX") as? Int ?? RepoDisplayPolicy.hide.intValue }
		set { set("NEW_ISSUE_DISPLAY_POLICY_INDEX", newValue) }
	}

	static let newMentionMovePolicyHelp = "If your username is mentioned in an item's description or a comment posted inside it, move the item to the specified section."
	class var newMentionMovePolicy: Int {
		get { return get("NEW_MENTION_MOVE_POLICY") as? Int ?? Section.mentioned.intValue }
		set { set("NEW_MENTION_MOVE_POLICY", newValue) }
	}

	static let teamMentionMovePolicyHelp = "If the name of one of the teams you belong to is mentioned in an item's description or a comment posted inside it, move the item to the specified section."
	class var teamMentionMovePolicy: Int {
		get { return get("TEAM_MENTION_MOVE_POLICY") as? Int ?? Section.mentioned.intValue }
		set { set("TEAM_MENTION_MOVE_POLICY", newValue) }
	}

	static let newItemInOwnedRepoMovePolicyHelp = "Automatically move an item to the specified section if it has been created in a repo which you own, even if there is no direct mention of you."
	class var newItemInOwnedRepoMovePolicy: Int {
		get { return get("NEW_ITEM_IN_OWNED_REPO_MOVE_POLICY") as? Int ?? Section.none.intValue }
		set { set("NEW_ITEM_IN_OWNED_REPO_MOVE_POLICY", newValue) }
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
		get { return S(get("LAST_RUN_VERSION_KEY") as? String) }
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
				UIApplication.shared.setMinimumBackgroundFetchInterval(TimeInterval(newValue))
			#endif
		}
	}

	static let newRepoCheckPeriodHelp = "How long before reloading your team list and watched repositories from a server. Since this doesn't change often, it's good to keep this as high as possible in order to keep bandwidth use as low as possible during refreshes. Set this to a lower value if you often update your watched repositories or teams."
	class var newRepoCheckPeriod: Float {
		get { if let n = get("NEW_REPO_CHECK_PERIOD") as? Float { return max(n, 2) } else { return 2 } }
		set { set("NEW_REPO_CHECK_PERIOD", newValue) }
	}

	/////////////////////////// DATES

    class var lastSuccessfulRefresh: Date? {
        get { return get("LAST_SUCCESSFUL_REFRESH") as? Date }
        set { set("LAST_SUCCESSFUL_REFRESH", newValue) }
    }

	class var lastExportDate: Date? {
		get { return get("LAST_EXPORT_TIME") as? Date }
		set { set("LAST_EXPORT_TIME", newValue) }
	}

	/////////////////////////// URLs

	class var lastExportUrl: URL? {
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

	static let hideMenubarCountsHelp = "Hide the counts of items in each status item in the menubar"
	class var hideMenubarCounts: Bool {
		get { return get("HIDE_MENUBAR_COUNTS") as? Bool ?? false }
		set { set("HIDE_MENUBAR_COUNTS", newValue) }
	}

	static let hideSnoozedItemsHelp = "Hide the snoozed items section"
	class var hideSnoozedItems: Bool {
		get { return get("HIDE_SNOOZED_ITEMS") as? Bool ?? false }
		set { set("HIDE_SNOOZED_ITEMS", newValue) }
	}

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

	static let showCreatedInsteadOfUpdatedHelp = "Trailer will usually display the time of the most recent activity in an item, such as comments. This setting replaces that with the orignal creation time of the item. Together with the sorting options, this is useful for helping prioritise items based on how old, or new, they are."
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

	static let preferIssuesInWatchHelp = "If there is only enough space to display one count or set of statistics on the Apple Watch, prefer the ones for issues rather than the ones for PRs."
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

	static let removeNotificationsWhenItemIsRemovedHelp = "When an item is removed, whether through user action or automatically due to settings, also remove any notifications in the Notification Center that are related to this item."
	class var removeNotificationsWhenItemIsRemoved: Bool {
		get { return get("REMOVE_RELATED_NOTIFICATIONS_ON_ITEM_REMOVE") as? Bool ?? true }
		set { set("REMOVE_RELATED_NOTIFICATIONS_ON_ITEM_REMOVE", newValue) }
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

	static let openItemsDirectlyInSafariHelp = "Directly open items in the Safari browser rather than the internal web view. Especially useful on iPad when using split-screen view,, you can pull in Trailer from the side but stay in Safari, or on iPhone, you can use the status-bar button as a back button. If the detail view is already visible (for instance when runing in full-screen mode on iPad) the internal view will still get used, even if this option is turned on."
	class var openItemsDirectlyInSafari: Bool {
		get { return get("OPEN_ITEMS_DIRECTLY_IN_SAFARI") as? Bool ?? false }
		set { set("OPEN_ITEMS_DIRECTLY_IN_SAFARI", newValue) }
	}

	static let hidePrsThatArentPassingHelp = "Hide PR items which have status items, but are not all green. Useful for hiding PRs which are not ready to review or those who have not passed certain checks yet."
	class var hidePrsThatArentPassing: Bool {
		get { return get("HIDE_PRS_THAT_ARENT_PASSING") as? Bool ?? false }
		set { set("HIDE_PRS_THAT_ARENT_PASSING", newValue) }
	}

	static let hidePrsThatDontPassOnlyInAllHelp = "Normally hiding red PRs will happen on every section. Selecting this will limit that filter to the 'All' section only, so red PRs which are yours or you have participated in will still show up."
	class var hidePrsThatDontPassOnlyInAll: Bool {
		get { return get("HIDE_PRS_THAT_ARENT_PASSING_ONLY_IN_ALL") as? Bool ?? false }
		set { set("HIDE_PRS_THAT_ARENT_PASSING_ONLY_IN_ALL", newValue) }
	}

	static let useVibrancyHelp = "Use macOS Vibrancy to display the Trailer drop-down menu, if available on the current OS version. If the OS doesn't support this, this setting has no effect."
	class var useVibrancy: Bool {
		get { return get("USE_VIBRANCY_UI") as? Bool ?? true }
		set { set("USE_VIBRANCY_UI", newValue) }
	}

	static let snoozeWakeOnCommentHelp = "Wake up snoozing items if a new comment is made"
	static let snoozeWakeOnMentionHelp = "Wake up snoozing items in you are mentioned in a new comment"
	static let snoozeWakeOnStatusUpdateHelp = "Wake up snoozing items if there is a status or CI update"

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

	static let markPrsAsUnreadOnNewCommitsHelp = "Mark a PR with an exclamation mark even if they it may not have unread comments, in case there have been new commits."
	class var markPrsAsUnreadOnNewCommits: Bool {
		get { return get("MARK_PRS_AS_UNREAD_ON_NEW_COMMITS") as? Bool ?? false }
		set { set("MARK_PRS_AS_UNREAD_ON_NEW_COMMITS", newValue) }
	}

	static let includeMilestonesInFilterHelp = "Check item milestone names for inclusion in filtered results. You can also prefix a search with 'milestone:' to specifically search for this."
	class var includeMilestonesInFilter: Bool {
		get { return get("INCLUDE_MILESTONES_IN_FILTER") as? Bool ?? false }
		set { set("INCLUDE_MILESTONES_IN_FILTER", newValue) }
	}

	static let includeAssigneeInFilterHelp = "Check item assignee names for inclusion in filtered results. You can also prefix a search with 'assignee:' to specifically search for this."
	class var includeAssigneeNamesInFilter: Bool {
		get { return get("INCLUDE_ASSIGNEE_NAMES_IN_FILTER") as? Bool ?? false }
		set { set("INCLUDE_ASSIGNEE_NAMES_IN_FILTER", newValue) }
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

	static let automaticallyAddNewReposFromWatchlistHelp = "Automatically add to Trailer any repos are added to your remote watchlist"
	class var automaticallyAddNewReposFromWatchlist: Bool {
		get { return get("AUTO_ADD_NEW_REPOS") as? Bool ?? true }
		set { set("AUTO_ADD_NEW_REPOS", newValue) }
	}

	static let automaticallyRemoveDeletedReposFromWatchlistHelp = "Automatically remove from Trailer any (previously automatically added) repos if they are no longer on your remote watchlist"
	class var automaticallyRemoveDeletedReposFromWatchlist: Bool {
		get { return get("AUTO_REMOVE_DELETED_REPOS") as? Bool ?? true }
		set { set("AUTO_REMOVE_DELETED_REPOS", newValue) }
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

	static let showSeparateApiServersInMenuHelp = "Show each API server as a separate item on the menu bar"
	class var showSeparateApiServersInMenu: Bool {
		get { return get("API_SERVERS_IN_SEPARATE_MENUS") as? Bool ?? false }
		set { set("API_SERVERS_IN_SEPARATE_MENUS", newValue) }
	}

	static let alwaysRequestDesktopSiteHelp = "Try to request the desktop version of GitHub pages from iPhone by pretending to be iPad"
	class var alwaysRequestDesktopSite: Bool {
		get { return get("FORCE_LOADING_IOS_DESKTOP_SITE") as? Bool ?? false }
		set { set("FORCE_LOADING_IOS_DESKTOP_SITE", newValue) }
	}

	static let assumeReadItemIfUserHasNewerCommentsHelp = "Mark any comments posted by others before your own as read. Warning: Only turn this on if you are sure you can catch any comments that others may add while you are adding yours! (This is a very useful setting for *secondary* Trailer displays)"
	class var assumeReadItemIfUserHasNewerComments: Bool {
		get { return get("ASSUME_READ_ITEM_IF_USER_HAS_NEWER_COMMENTS") as? Bool ?? false }
		set { set("ASSUME_READ_ITEM_IF_USER_HAS_NEWER_COMMENTS", newValue) }
	}
}
