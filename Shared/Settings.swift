
let _settings_defaults = NSUserDefaults.standardUserDefaults()
var _settings_valuesCache = Dictionary<String, NSObject>()

class Settings: NSObject {

	private class func set(key: String, _ value: NSObject?) {
		if let v = value {
			_settings_defaults.setObject(v, forKey: key)
			DLog("Set %@: %@", key, v)
		} else {
			_settings_defaults.removeObjectForKey(key)
			DLog("Cleared %@", key)
		}
		_settings_valuesCache[key] = value
		_settings_defaults.synchronize()
	}

	private class func get(key: String) -> NSObject? {
		if let v = _settings_valuesCache[key] {
			return v
		} else {
			if let vv = _settings_defaults.objectForKey(key) as? NSObject {
				_settings_valuesCache[key] = vv
				return vv
			} else {
				return nil
			}
		}
	}

	/////////////////////////////////

	class var sortMethod: Int {
		get { if let n = get("SORT_METHOD_KEY") as Int? { return n } else { return 0 } }
		set { set("SORT_METHOD_KEY", newValue) }
	}

	class var statusFilteringMode: Int {
		get { if let n = get("STATUS_FILTERING_METHOD_KEY") as Int? { return n } else { return 0 } }
		set { set("STATUS_FILTERING_METHOD_KEY", newValue) }
	}

	class var lastPreferencesTabSelected: Int {
		get { if let n = get("LAST_PREFS_TAB_SELECTED") as Int? { return n } else { return 0 } }
		set { set("LAST_PREFS_TAB_SELECTED", newValue) }
	}

	class var closeHandlingPolicy: Int {
		get { if let n = get("CLOSE_HANDLING_POLICY") as Int? { return n } else { return 0 } }
		set { set("CLOSE_HANDLING_POLICY", newValue) }
	}

	class var mergeHandlingPolicy: Int {
		get { if let n = get("MERGE_HANDLING_POLICY") as Int? { return n } else { return 0 } }
		set { set("MERGE_HANDLING_POLICY", newValue) }
	}

	class var statusItemRefreshInterval: Int {
		get { if let n = get("STATUS_ITEM_REFRESH_COUNT") as Int? { return n>0 ? n : 10 } else { return 10 } }
		set { set("STATUS_ITEM_REFRESH_COUNT", newValue) }
	}

	class var labelRefreshInterval: Int {
		get { if let n = get("LABEL_REFRESH_COUNT") as Int? { return n>0 ? n : 4 } else { return 4 } }
		set { set("LABEL_REFRESH_COUNT", newValue) }
	}

	class var checkForUpdatesInterval: Int {
		get { if let n = get("UPDATE_CHECK_INTERVAL_KEY") as Int? { return n } else { return 8 } }
		set { set("UPDATE_CHECK_INTERVAL_KEY", newValue) }
	}

	///////////////////////////

	class var statusFilteringTerms: [String] {
		get { if let s = get("STATUS_FILTERING_TERMS_KEY") as [String]? { return s } else { return [] } }
		set { set("STATUS_FILTERING_TERMS_KEY", newValue) }
	}

	class var commentAuthorBlacklist: [String] {
		get { if let s = get("COMMENT_AUTHOR_BLACKLIST") as [String]? { return s } else { return [] } }
		set { set("COMMENT_AUTHOR_BLACKLIST", newValue) }
	}

	class var hotkeyLetter: String {
		get { if let s = get("HOTKEY_LETTER") as String? { return s } else { return "T" } }
		set { set("HOTKEY_LETTER", newValue) }
	}

	///////////////////////////

	class var refreshPeriod: Float {
		get { if let n = get("REFRESH_PERIOD_KEY") as Float? { return n < 60 ? 120 : n } else { return 120 } }
		set { set("REFRESH_PERIOD_KEY", newValue) }
	}

	class var backgroundRefreshPeriod: Float {
		get { if let n = get("REFRESH_PERIOD_KEY") as Float? { return n > 0 ? n : 1800 } else { return 1800 } }
		set {
			set("REFRESH_PERIOD_KEY", newValue)
			#if os(iOS)
			UIApplication.sharedApplication().setMinimumBackgroundFetchInterval(NSTimeInterval(newValue))
			#endif
		}
	}

	class var newRepoCheckPeriod: Float {
		get { if let n = get("NEW_REPO_CHECK_PERIOD") as Float? { return max(n, 2) } else { return 2 } }
		set { set("NEW_REPO_CHECK_PERIOD", newValue) }
	}

	///////////////////////////

	class var checkForUpdatesAutomatically: Bool {
		get { if let b = get("UPDATE_CHECK_AUTO_KEY") as Bool? { return b } else { return true } }
		set { set("UPDATE_CHECK_AUTO_KEY", newValue) }
	}

	class var shouldHideUncommentedRequests: Bool {
		get { if let b = get("HIDE_UNCOMMENTED_PRS_KEY") as Bool? { return b } else { return false } }
		set { set("HIDE_UNCOMMENTED_PRS_KEY", newValue) }
	}

	class var showCommentsEverywhere: Bool {
		get { if let b = get("SHOW_COMMENTS_EVERYWHERE_KEY") as Bool? { return b } else { return false } }
		set { set("SHOW_COMMENTS_EVERYWHERE_KEY", newValue) }
	}

	class var sortDescending: Bool {
		get { if let b = get("SORT_ORDER_KEY") as Bool? { return b } else { return false } }
		set { set("SORT_ORDER_KEY", newValue) }
	}

	class var showCreatedInsteadOfUpdated: Bool {
		get { if let b = get("SHOW_UPDATED_KEY") as Bool? { return b } else { return false } }
		set { set("SHOW_UPDATED_KEY", newValue) }
	}

	class var dontKeepPrsMergedByMe: Bool {
		get { if let b = get("DONT_KEEP_MY_PRS_KEY") as Bool? { return b } else { return false } }
		set { set("DONT_KEEP_MY_PRS_KEY", newValue) }
	}

	class var hideAvatars: Bool {
		get { if let b = get("HIDE_AVATARS_KEY") as Bool? { return b } else { return false } }
		set { set("HIDE_AVATARS_KEY", newValue) }
	}

	class var autoParticipateInMentions: Bool {
		get { if let b = get("AUTO_PARTICIPATE_IN_MENTIONS_KEY") as Bool? { return b } else { return false } }
		set { set("AUTO_PARTICIPATE_IN_MENTIONS_KEY", newValue) }
	}

	class var dontAskBeforeWipingMerged: Bool {
		get { if let b = get("DONT_ASK_BEFORE_WIPING_MERGED") as Bool? { return b } else { return false } }
		set { set("DONT_ASK_BEFORE_WIPING_MERGED", newValue) }
	}

	class var dontAskBeforeWipingClosed: Bool {
		get { if let b = get("DONT_ASK_BEFORE_WIPING_CLOSED") as Bool? { return b } else { return false } }
		set { set("DONT_ASK_BEFORE_WIPING_CLOSED", newValue) }
	}

	class var includeReposInFilter: Bool {
		get { if let b = get("INCLUDE_REPOS_IN_FILTER") as Bool? { return b } else { return false } }
		set { set("INCLUDE_REPOS_IN_FILTER", newValue) }
	}

	class var showReposInName: Bool {
		get { if let b = get("SHOW_REPOS_IN_NAME") as Bool? { return b } else { return false } }
		set { set("SHOW_REPOS_IN_NAME", newValue) }
	}

	class var hideNewRepositories: Bool {
		get { if let b = get("HIDE_NEW_REPOS_KEY") as Bool? { return b } else { return false } }
		set { set("HIDE_NEW_REPOS_KEY", newValue) }
	}

	class var groupByRepo: Bool {
		get { if let b = get("GROUP_BY_REPO") as Bool? { return b } else { return false } }
		set { set("GROUP_BY_REPO", newValue) }
	}

	class var hideAllPrsSection: Bool {
		get { if let b = get("HIDE_ALL_SECTION") as Bool? { return b } else { return false } }
		set { set("HIDE_ALL_SECTION", newValue) }
	}

	class var showLabels: Bool {
		get { if let b = get("SHOW_LABELS") as Bool? { return b } else { return false } }
		set { set("SHOW_LABELS", newValue) }
	}

	class var showStatusItems: Bool {
		get { if let b = get("SHOW_STATUS_ITEMS") as Bool? { return b } else { return false } }
		set { set("SHOW_STATUS_ITEMS", newValue) }
	}

	class var makeStatusItemsSelectable: Bool {
		get { if let b = get("MAKE_STATUS_ITEMS_SELECTABLE") as Bool? { return b } else { return false } }
		set { set("MAKE_STATUS_ITEMS_SELECTABLE", newValue) }
	}

	class var moveAssignedPrsToMySection: Bool {
		get { if let b = get("MOVE_ASSIGNED_PRS_TO_MY_SECTION") as Bool? { return b } else { return false } }
		set { set("MOVE_ASSIGNED_PRS_TO_MY_SECTION", newValue) }
	}

	class var markUnmergeableOnUserSectionsOnly: Bool {
		get { if let b = get("MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY") as Bool? { return b } else { return false } }
		set { set("MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY", newValue) }
	}

	class var countOnlyListedPrs: Bool {
		get { if let b = get("COUNT_ONLY_LISTED_PRS") as Bool? { return b } else { return false } }
		set { set("COUNT_ONLY_LISTED_PRS", newValue) }
	}

	class var openPrAtFirstUnreadComment: Bool {
		get { if let b = get("OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY") as Bool? { return b } else { return false } }
		set { set("OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY", newValue) }
	}

	class var logActivityToConsole: Bool {
		get { if let b = get("LOG_ACTIVITY_TO_CONSOLE_KEY") as Bool? { return b } else { return false } }
		set { set("LOG_ACTIVITY_TO_CONSOLE_KEY", newValue) }
	}

	class var hotkeyEnable: Bool {
		get { if let b = get("HOTKEY_ENABLE") as Bool? { return b } else { return false } }
		set { set("HOTKEY_ENABLE", newValue) }
	}

	class var hotkeyControlModifier: Bool {
		get { if let b = get("HOTKEY_CONTROL_MODIFIER") as Bool? { return b } else { return false } }
		set { set("HOTKEY_CONTROL_MODIFIER", newValue) }
	}

	class var useVibrancy: Bool {
		get { if let b = get("USE_VIBRANCY_UI") as Bool? { return b } else { return false } }
		set { set("USE_VIBRANCY_UI", newValue) }
	}

	class var hotkeyCommandModifier: Bool {
		get { if let b = get("HOTKEY_COMMAND_MODIFIER") as Bool? { return b } else { return true } }
		set { set("HOTKEY_COMMAND_MODIFIER", newValue) }
	}

	class var hotkeyOptionModifier: Bool {
		get { if let b = get("HOTKEY_OPTION_MODIFIER") as Bool? { return b } else { return true } }
		set { set("HOTKEY_OPTION_MODIFIER", newValue) }
	}

	class var hotkeyShiftModifier: Bool {
		get { if let b = get("HOTKEY_SHIFT_MODIFIER") as Bool? { return b } else { return true } }
		set { set("HOTKEY_SHIFT_MODIFIER", newValue) }
	}
}
