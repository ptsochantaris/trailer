#if os(iOS)
    import UIKit
#else
    import Foundation
    import ServiceManagement
#endif
import PopTimer

enum MigrationStatus: Int {
    case pending, inProgress, done, failedPending, failedAnnounced

    var needed: Bool {
        switch self {
        case .inProgress, .pending:
            true
        case .done, .failedAnnounced, .failedPending:
            false
        }
    }

    var wantsNewIds: Bool {
        switch self {
        case .done, .inProgress:
            true
        case .failedAnnounced, .failedPending, .pending:
            false
        }
    }
}

enum InclusionSetting: Int {
    case excludeIfAny, includeIfAny, excludeIfAll, includeIfAll

    func shouldContributeToCount(isMine: Bool, userName: String?, createdAt: Date?, since: Date, settings: Settings.Cache) -> Bool {
        guard !isMine,
              let userName,
              let createdAt,
              createdAt > since
        else {
            return false
        }

        let list = settings.commentAuthorList
        if list.isEmpty { return true }

        let contains = list.contains(userName.comparableForm)
        switch self {
        case .includeIfAll, .includeIfAny:
            return contains
        case .excludeIfAll, .excludeIfAny:
            return !contains
        }
    }
}

enum Settings {
    @MainActor
    static var cache = Cache()

    final class Cache {
        let labelFilterList = Set(Settings.labelBlacklist.map(\.comparableForm))
        let labelsIncludionRule = Settings.labelsIncludionRule

        let authorFilterList = Set(Settings.itemAuthorBlacklist.map(\.comparableForm))
        let authorsIncludionRule = Settings.authorsIncludionRule

        let commentAuthorList = Set(Settings.commentAuthorBlacklist.map(\.comparableForm))
        let commenterInclusionRule = Settings.commenterInclusionRule

        let assumeReadItemIfUserHasNewerComments = Settings.assumeReadItemIfUserHasNewerComments
        let hideUncommentedItems = Settings.hideUncommentedItems
        let notifyOnItemReactions = Settings.notifyOnItemReactions
        let notifyOnCommentReactions = Settings.notifyOnCommentReactions
        let notifyOnStatusUpdates = Settings.notifyOnStatusUpdates
        let shouldHideDrafts = Settings.draftHandlingPolicy == .hide
        let autoRemoveClosedItems = Settings.autoRemoveClosedItems
        let autoRemoveMergedItems = Settings.autoRemoveMergedItems
        let notifyOnStatusUpdatesForAllPrs = Settings.notifyOnStatusUpdatesForAllPrs
        let hidePrsIfApproved = Settings.autoHidePrsIApproved
        let hidePrsIfRejected = Settings.autoHidePrsIRejected
        let preferredMovePolicySection = Settings.newMentionMovePolicy.preferredSection
        let preferredTeamMentionPolicy = Settings.teamMentionMovePolicy.preferredSection
        let newItemInOwnedRepoMovePolicy = Settings.newItemInOwnedRepoMovePolicy.preferredSection
        let assignedItemDirectHandlingPolicy = Settings.assignedItemDirectHandlingPolicy
        let assignedItemTeamHandlingPolicy = Settings.assignedItemTeamHandlingPolicy
        let notifyOnAllReviewChangeRequests = Settings.notifyOnAllReviewChangeRequests
        let notifyOnAllReviewAcceptances = Settings.notifyOnAllReviewAcceptances
        let notifyOnAllReviewDismissals = Settings.notifyOnAllReviewDismissals
        let notifyOnReviewChangeRequests = Settings.notifyOnReviewChangeRequests
        let notifyOnReviewAcceptances = Settings.notifyOnReviewAcceptances
        let notifyOnReviewDismissals = Settings.notifyOnReviewDismissals
        let autoSnoozeDuration = TimeInterval(Settings.autoSnoozeDuration)
        let hidePrsThatArentPassing = Settings.hidePrsThatArentPassing
        let hidePrsThatDontPassOnlyInAll = Settings.hidePrsThatDontPassOnlyInAll
        let notifyOnReviewAssignments = Settings.notifyOnReviewAssignments
        let queryAuthoredIssues = Settings.queryAuthoredIssues
        let showRequestedTeamReviews = Settings.showRequestedTeamReviews

        let showCommentsEverywhere = Settings.showCommentsEverywhere
        let scanClosedAndMergedItems = Settings.scanClosedAndMergedItems
        let showStatusesOnAllItems = Settings.showStatusesOnAllItems
        let showStatusItems = Settings.showStatusItems
        let syncProfile = Settings.syncProfile
        let hideSnoozedItems = Settings.hideSnoozedItems
        let displayNumbersForItems = Settings.displayNumbersForItems
        let showPrLines = Settings.showPrLines
        let markUnmergeablePrs = Settings.markUnmergeablePrs
        let draftHandlingPolicy = Settings.draftHandlingPolicy
        let showBaseAndHeadBranches = Settings.showBaseAndHeadBranches
        let showReposInName = Settings.showReposInName
        let showMilestones = Settings.showMilestones
        let showRelativeDates = Settings.showRelativeDates
        let showCreatedInsteadOfUpdated = Settings.showCreatedInsteadOfUpdated
        let showClosingInfo = Settings.showClosingInfo

        let statusRed = Settings.showStatusesRed
        let statusYellow = Settings.showStatusesYellow
        let statusGreen = Settings.showStatusesGreen
        let statusGray = Settings.showStatusesGray
        let statusMode = Settings.statusFilteringMode
        let statusTerms = Settings.statusFilteringTerms
        let markPrsAsUnreadOnNewCommits = Settings.markPrsAsUnreadOnNewCommits
        let removeNotificationsWhenItemIsRemoved = Settings.removeNotificationsWhenItemIsRemoved

        let includeTitlesInFilter = Settings.includeTitlesInFilter
        let includeReposInFilter = Settings.includeReposInFilter
        let includeServersInFilter = Settings.includeServersInFilter
        let includeUsersInFilter = Settings.includeUsersInFilter
        let includeNumbersInFilter = Settings.includeNumbersInFilter
        let includeMilestonesInFilter = Settings.includeMilestonesInFilter
        let includeAssigneeNamesInFilter = Settings.includeAssigneeNamesInFilter
        let includeLabelsInFilter = Settings.includeLabelsInFilter
        let includeStatusesInFilter = Settings.includeStatusesInFilter
        let sortDescending = Settings.sortDescending
        let sortField = Settings.sortMethod.field
        let groupByRepo = Settings.groupByRepo

        let makeStatusItemsSelectable = Settings.makeStatusItemsSelectable
        let hideAvatars = Settings.hideAvatars
        let showLabels = Settings.showLabels

        let requiresReviewApis: Bool
        let shouldSyncReactions: Bool
        let shouldSyncReviews: Bool
        let shouldSyncReviewAssignments: Bool

        init() {
            Logging.log("(Re)creating settings cache")

            shouldSyncReactions = notifyOnItemReactions || notifyOnCommentReactions

            shouldSyncReviews = displayReviewsOnItems
                || notifyOnReviewDismissals
                || notifyOnReviewAcceptances
                || notifyOnReviewChangeRequests
                || autoHidePrsIApproved
                || autoHidePrsIRejected

            shouldSyncReviewAssignments = displayReviewsOnItems
                || showRequestedTeamReviews
                || notifyOnReviewAssignments
                || (assignedDirectReviewHandlingPolicy.visible)
                || (assignedTeamReviewHandlingPolicy.visible)

            requiresReviewApis = shouldSyncReviews || shouldSyncReviewAssignments
        }
    }

    private static let sharedDefaults = UserDefaults(suiteName: "group.Trailer")!

    private static var allFields: [String] { [
        "SORT_METHOD_KEY", "STATUS_FILTERING_METHOD_KEY", "LAST_PREFS_TAB_SELECTED", "STATUS_ITEM_REFRESH_BATCH", "UPDATE_CHECK_INTERVAL_KEY", "ASSIGNED_REVIEW_HANDLING_POLICY", "NOTIFY_ON_REVIEW_CHANGE_REQUESTS", "NOTIFY_ON_ALL_REVIEW_CHANGE_REQUESTS",
        "STATUS_FILTERING_TERMS_KEY", "COMMENT_AUTHOR_BLACKLIST", "HOTKEY_LETTER", "REFRESH_PERIOD_KEY", "IOS_BACKGROUND_REFRESH_PERIOD_KEY", "NEW_REPO_CHECK_PERIOD", "LAST_SUCCESSFUL_REFRESH", "LABEL_BLACKLIST",
        "LAST_RUN_VERSION_KEY", "UPDATE_CHECK_AUTO_KEY", "HIDE_UNCOMMENTED_PRS_KEY", "SHOW_COMMENTS_EVERYWHERE_KEY", "SORT_ORDER_KEY", "SHOW_UPDATED_KEY", "DONT_KEEP_MY_PRS_KEY", "HIDE_AVATARS_KEY", "HIDE_NOTIFICATION_AVATARS_KEY",
        "DONT_ASK_BEFORE_WIPING_MERGED", "DONT_ASK_BEFORE_WIPING_CLOSED", "HIDE_NEW_REPOS_KEY", "GROUP_BY_REPO", "HIDE_ALL_SECTION", "SHOW_STATUS_ITEMS", "NOTIFY_ON_REVIEW_ACCEPTANCES", "NOTIFY_ON_ALL_REVIEW_ACCEPTANCES", "NOTIFY_ON_REVIEW_ASSIGNMENTS",
        "MAKE_STATUS_ITEMS_SELECTABLE", "COUNT_ONLY_LISTED_PRS", "OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY", "LOG_ACTIVITY_TO_CONSOLE_KEY", "NOTIFY_ON_REVIEW_DISMISSALS", "NOTIFY_ON_ALL_REVIEW_DISMISSALS",
        "HOTKEY_ENABLE", "HOTKEY_CONTROL_MODIFIER", "DISABLE_ALL_COMMENT_NOTIFICATIONS", "NOTIFY_ON_STATUS_UPDATES", "NOTIFY_ON_STATUS_UPDATES_ALL", "SHOW_REPOS_IN_NAME", "INCLUDE_REPOS_IN_FILTER", "SHOW_STATUSES_EVERYWHERE",
        "INCLUDE_LABELS_IN_FILTER", "INCLUDE_STATUSES_IN_FILTER", "HOTKEY_COMMAND_MODIFIER", "HOTKEY_OPTION_MODIFIER", "HOTKEY_SHIFT_MODIFIER", "GRAY_OUT_WHEN_REFRESHING", "SHOW_ISSUES_MENU", "NOTIFY_ON_ITEM_REACTIONS",
        "SHOW_ISSUES_IN_WATCH_GLANCE", "ASSIGNED_PR_HANDLING_POLICY", "HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW", "AUTO_REPEAT_SETTINGS_EXPORT", "DONT_CONFIRM_SETTINGS_IMPORT", "NOTIFY_ON_COMMENT_REACTIONS", "REACTION_SCANNING_BATCH",
        "LAST_EXPORT_URL", "LAST_EXPORT_TIME", "CLOSE_HANDLING_POLICY_2", "MERGE_HANDLING_POLICY_2", "LAST_PREFS_TAB_SELECTED_OSX", "NEW_PR_DISPLAY_POLICY_INDEX", "NEW_ISSUE_DISPLAY_POLICY_INDEX", "HIDE_PRS_THAT_ARENT_PASSING_ONLY_IN_ALL",
        "INCLUDE_SERVERS_IN_FILTER", "INCLUDE_USERS_IN_FILTER", "INCLUDE_TITLES_IN_FILTER", "INCLUDE_NUMBERS_IN_FILTER", "DUMP_API_RESPONSES_IN_CONSOLE", "OPEN_ITEMS_DIRECTLY_IN_SAFARI", "HIDE_PRS_THAT_ARENT_PASSING", "ITEM_AUTHOR_BLACKLIST",
        "REMOVE_RELATED_NOTIFICATIONS_ON_ITEM_REMOVE", "HIDE_SNOOZED_ITEMS", "INCLUDE_MILESTONES_IN_FILTER", "INCLUDE_ASSIGNEE_NAMES_IN_FILTER", "API_SERVERS_IN_SEPARATE_MENUS", "ASSUME_READ_ITEM_IF_USER_HAS_NEWER_COMMENTS",
        "AUTO_SNOOZE_DAYS", "HIDE_MENUBAR_COUNTS", "AUTO_ADD_NEW_REPOS", "AUTO_REMOVE_DELETED_REPOS", "MARK_PRS_AS_UNREAD_ON_NEW_COMMITS", "SHOW_LABELS", "DISPLAY_REVIEW_CHANGE_REQUESTS", "SHOW_RELATIVE_DATES", "QUERY_AUTHORED_PRS", "QUERY_AUTHORED_ISSUES",
        "DISPLAY_MILESTONES", "DEFAULT_APP_FOR_OPENING_WEB", "DEFAULT_APP_FOR_OPENING_ITEMS", "HIDE_ARCHIVED_REPOS", "DRAFT_HANDLING_POLICY", "MARK_UNMERGEABLE_ITEMS", "SHOW_PR_LINES", "SCAN_CLOSED_AND_MERGED", "USE_V4_API", "REQUESTED_TEAM_REVIEWS",
        "SHOW_STATUSES_GREEN", "SHOW_STATUSES_GRAY", "SHOW_STATUSES_YELLOW", "SHOW_STATUSES_RED", "SHOW_BASE_AND_HEAD_BRANCHES", "PERSISTED_TAB_FILTERS", "PR_V4_SYNC_PAGE", "ISSUE_V4_SYNC_PAGE", "V4_THREAD_SYNC", "ASSIGNED_PR_TEAM_HANDLING_POLICY",
        "ASSIGNED_REVIEW_TEAM_HANDLING_POLICY", "AUTO_REMOVE_MERGED_ITEMS", "AUTO_REMOVE_CLOSED_ITEMS", "LABELS_INCLUSION_RULE", "AUTHORS_INCLUSION_RULE", "COMMENTER_INCLUSION_RULE", "SHOW_CLOSING_INFO"
    ] }

    @MainActor
    static func checkMigration() {
        if let snoozeWakeOnComment = Settings["SNOOZE_WAKEUP_ON_COMMENT"] as? Bool {
            DataManager.postMigrationSnoozeWakeOnComment = snoozeWakeOnComment
            Settings["SNOOZE_WAKEUP_ON_COMMENT"] = nil
        }
        if let snoozeWakeOnMention = Settings["SNOOZE_WAKEUP_ON_MENTION"] as? Bool {
            DataManager.postMigrationSnoozeWakeOnMention = snoozeWakeOnMention
            Settings["SNOOZE_WAKEUP_ON_MENTION"] = nil
        }
        if let snoozeWakeOnStatusUpdate = Settings["SNOOZE_WAKEUP_ON_STATUS_UPDATE"] as? Bool {
            DataManager.postMigrationSnoozeWakeOnStatusUpdate = snoozeWakeOnStatusUpdate
            Settings["SNOOZE_WAKEUP_ON_STATUS_UPDATE"] = nil
        }

        if Settings["SHOW_STATUSES_EVERYWHERE"] as? Bool == nil,
           let showStats = Settings["SHOW_STATUS_ITEMS"] as? Bool, showStats,
           let notifyAll = Settings["NOTIFY_ON_STATUS_UPDATES_ALL"] as? Bool, notifyAll {
            Settings["SHOW_STATUSES_EVERYWHERE"] = true
        }

        if let moveAssignedPrs = Settings["MOVE_ASSIGNED_PRS_TO_MY_SECTION"] as? Bool {
            Settings["ASSIGNED_PR_HANDLING_POLICY"] = moveAssignedPrs ? Section.mine.assignmentPolicySettingsValue : Section.hidden(cause: .unknown).assignmentPolicySettingsValue
            Settings["MOVE_ASSIGNED_PRS_TO_MY_SECTION"] = nil
        }

        if let mergeHandlingPolicyLegacy = Settings["MERGE_HANDLING_POLICY"] as? Int {
            Settings["MERGE_HANDLING_POLICY_2"] = mergeHandlingPolicyLegacy + (mergeHandlingPolicyLegacy > 0).asInt
            Settings["MERGE_HANDLING_POLICY"] = nil
        }

        if let closeHandlingPolicyLegacy = Settings["CLOSE_HANDLING_POLICY"] as? Int {
            Settings["CLOSE_HANDLING_POLICY_2"] = closeHandlingPolicyLegacy + (closeHandlingPolicyLegacy > 0).asInt
            Settings["CLOSE_HANDLING_POLICY"] = nil
        }

        if let mentionedUserMoveLegacy = Settings["AUTO_PARTICIPATE_IN_MENTIONS_KEY"] as? Bool {
            Settings["NEW_MENTION_MOVE_POLICY"] = mentionedUserMoveLegacy ? Section.mentioned.movePolicySettingsValue : Section.hidden(cause: .unknown).movePolicySettingsValue
            Settings["AUTO_PARTICIPATE_IN_MENTIONS_KEY"] = nil
        }

        if let mentionedTeamMoveLegacy = Settings["AUTO_PARTICIPATE_ON_TEAM_MENTIONS"] as? Bool {
            Settings["TEAM_MENTION_MOVE_POLICY"] = mentionedTeamMoveLegacy ? Section.mentioned.movePolicySettingsValue : Section.hidden(cause: .unknown).movePolicySettingsValue
            Settings["AUTO_PARTICIPATE_ON_TEAM_MENTIONS"] = nil
        }

        if let mentionedRepoMoveLegacy = Settings["MOVE_NEW_ITEMS_IN_OWN_REPOS_TO_MENTIONED"] as? Bool {
            Settings["NEW_ITEM_IN_OWNED_REPO_MOVE_POLICY"] = mentionedRepoMoveLegacy ? Section.mentioned.movePolicySettingsValue : Section.hidden(cause: .unknown).movePolicySettingsValue
            Settings["MOVE_NEW_ITEMS_IN_OWN_REPOS_TO_MENTIONED"] = nil
        }

        DataManager.postMigrationRepoPrPolicy = .all
        DataManager.postMigrationRepoIssuePolicy = .hide

        if let showIssues = Settings["SHOW_ISSUES_MENU"] as? Bool {
            Settings["NEW_ISSUE_DISPLAY_POLICY_INDEX"] = showIssues ? RepoDisplayPolicy.all.intValue : RepoDisplayPolicy.hide.intValue
            DataManager.postMigrationRepoIssuePolicy = showIssues ? RepoDisplayPolicy.all : RepoDisplayPolicy.hide
            Settings["SHOW_ISSUES_MENU"] = nil
        }

        if let hideNewRepositories = Settings["HIDE_NEW_REPOS_KEY"] as? Bool {
            Settings["NEW_PR_DISPLAY_POLICY_INDEX"] = hideNewRepositories ? RepoDisplayPolicy.hide.intValue : RepoDisplayPolicy.all.intValue
            Settings["NEW_ISSUE_DISPLAY_POLICY_INDEX"] = hideNewRepositories ? RepoDisplayPolicy.hide.intValue : RepoDisplayPolicy.all.intValue
            Settings["HIDE_NEW_REPOS_KEY"] = nil
        }

        if let hideAllSection = Settings["HIDE_ALL_SECTION"] as? Bool {
            if hideAllSection {
                if DataManager.postMigrationRepoPrPolicy == .all {
                    DataManager.postMigrationRepoPrPolicy = .mineAndPaticipated
                }
                if DataManager.postMigrationRepoIssuePolicy == .all {
                    DataManager.postMigrationRepoIssuePolicy = .mineAndPaticipated
                }

                let newPrPolicy = Settings["NEW_PR_DISPLAY_POLICY_INDEX"] as? Int ?? RepoDisplayPolicy.all.rawValue
                if newPrPolicy == RepoDisplayPolicy.all.rawValue {
                    Settings["NEW_PR_DISPLAY_POLICY_INDEX"] = RepoDisplayPolicy.mineAndPaticipated.intValue
                }
                let newIssuePolicy = Settings["NEW_ISSUE_DISPLAY_POLICY_INDEX"] as? Int ?? RepoDisplayPolicy.all.rawValue
                if newIssuePolicy == RepoDisplayPolicy.all.rawValue {
                    Settings["NEW_ISSUE_DISPLAY_POLICY_INDEX"] = RepoDisplayPolicy.mineAndPaticipated.intValue
                }
            }
            Settings["HIDE_ALL_SECTION"] = nil
        }

        if Settings["ASSIGNED_REVIEW_TEAM_HANDLING_POLICY"] == nil {
            assignedTeamReviewHandlingPolicy = assignedDirectReviewHandlingPolicy
        }

        if Settings["ASSIGNED_PR_TEAM_HANDLING_POLICY"] == nil {
            assignedItemTeamHandlingPolicy = assignedItemDirectHandlingPolicy
        }

        if Settings["HIDE_NOTIFICATION_AVATARS_KEY"] == nil {
            Settings["HIDE_NOTIFICATION_AVATARS_KEY"] = Settings["HIDE_AVATARS_KEY"] as? Bool ?? false
        }

        for repo in Repo.allItems(in: DataManager.main) where repo.value(forKey: "archived") == nil {
            repo.archived = false
            repo.updatedAt = .distantPast
        }

        let allServers = ApiServer.allApiServers(in: DataManager.main)
        for server in allServers where server.isGitHub && server.graphQLPath.isEmpty {
            server.graphQLPath = "https://api.github.com/graphql"
        }

        #if os(macOS)
            if Settings.lastRunVersion != "", Settings["launchAtLogin"] == nil {
                Logging.log("Migrated to the new startup mechanism, activating it by default")
                isAppLoginItem = true
            }
        #endif

        sharedDefaults.synchronize()
    }

    private static subscript(key: String) -> Any? {
        get {
            sharedDefaults.object(forKey: key)
        }
        set {
            if let newValue {
                sharedDefaults.set(newValue, forKey: key)
            } else {
                sharedDefaults.removeObject(forKey: key)
            }
            Task { @MainActor in
                cache = Cache()
                #if os(macOS)
                    possibleExport(key)
                #endif
            }
        }
    }

    private static let saveTimer = PopTimer(timeInterval: 2) {
        if let e = Settings.lastExportUrl {
            Settings.writeToURL(e)
        }
    }

    private static let goodKeys: Set<String> = ["LAST_SUCCESSFUL_REFRESH", "LAST_EXPORT_URL", "LAST_EXPORT_TIME"]

    #if os(macOS)
        static var isAppLoginItem: Bool {
            get {
                Settings["launchAtLogin"] as? Bool ?? false
            }
            set {
                Settings["launchAtLogin"] = newValue
                SMLoginItemSetEnabled(LauncherCommon.helperAppId as CFString, newValue)
            }
        }

        static func possibleExport(_ key: String?) {
            if !Settings.autoRepeatSettingsExport {
                return
            }

            let keyIsGood: Bool
            if let key {
                keyIsGood = !goodKeys.contains(key)
            } else {
                keyIsGood = true
            }
            if keyIsGood, Settings.lastExportUrl != nil {
                saveTimer.push()
            }
        }
    #endif

    ///////////////////////////////// IMPORT / EXPORT

    @discardableResult
    @MainActor
    static func writeToURL(_ url: URL) -> Bool {
        saveTimer.abort()

        Settings.lastExportUrl = url
        Settings.lastExportDate = Date()
        let settings = NSMutableDictionary()
        for k in allFields where k != "AUTO_REPEAT_SETTINGS_EXPORT" {
            if let v = Settings[k] {
                settings[k] = v
            }
        }
        settings["DB_CONFIG_OBJECTS"] = ApiServer.archivedApiServers
        settings["DB_SNOOZE_OBJECTS"] = SnoozePreset.archivedPresets
        if !settings.write(to: url, atomically: true) {
            Logging.log("Warning, exporting settings failed")
            return false
        }
        NotificationCenter.default.post(name: .SettingsExported, object: nil)
        Logging.log("Written settings to \(url.absoluteString)")
        return true
    }

    @MainActor
    static func readFromURL(_ url: URL) async -> Bool {
        if let settings = NSDictionary(contentsOf: url) {
            Logging.log("Reading settings from \(url.absoluteString)")
            resetAllSettings()
            for k in allFields {
                if let v = settings[k] {
                    Settings[k] = v
                }
            }
            let result1 = await ApiServer.configure(from: settings["DB_CONFIG_OBJECTS"] as! [String: [String: NSObject]])
            let result2 = await SnoozePreset.configure(from: settings["DB_SNOOZE_OBJECTS"] as! [[String: NSObject]])
            return result1 && result2
        }
        return false
    }

    static func resetAllSettings() {
        for k in allFields {
            sharedDefaults.removeObject(forKey: k)
        }
    }

    ///////////////////////////////// NUMBERS

    @UserDefault(key: "AUTO_REMOVE_MERGED_ITEMS", defaultValue: 0)
    static var autoRemoveMergedItems: Int
    static let autoRemoveMergedItemsHelp = "Automatically remove merged items which have been inactive for a certain amount of time."

    @UserDefault(key: "AUTO_REMOVE_CLOSED_ITEMS", defaultValue: 0)
    static var autoRemoveClosedItems: Int
    static let autoRemoveClosedItemsHelp = "Automatically remove closed items which have been inactive for a certain amount of time."

    @EnumUserDefault(key: "PR_V4_SYNC_PROFILE", defaultValue: GraphQL.Profile.cautious)
    static var syncProfile: GraphQL.Profile
    static let syncProfileHelp = "Preferred balance between query size and safety when using v4 API."

    @UserDefault(key: "V4_THREAD_SYNC", defaultValue: false)
    static var threadedSync: Bool
    static let threadedSyncHelp = "Try two parallel queries to the server when using v4 API. Can greatly speed up incremental syncs but in some corner cases cause throttling by GitHub."

    @UserDefault(key: "AUTO_SNOOZE_DAYS", defaultValue: 0)
    static var autoSnoozeDuration: Int
    static let autoSnoozeDurationHelp = "How many days before an item is automatically snoozed. An item is auto-snoozed forever but will wake up on any comment, mention, or status update."

    @EnumUserDefault(key: "SORT_METHOD_KEY", defaultValue: SortingMethod.creationDate)
    static var sortMethod: SortingMethod
    static let sortMethodHelp = "The criterion to use when sorting items."

    @EnumUserDefault(key: "STATUS_FILTERING_METHOD_KEY", defaultValue: .all)
    static var statusFilteringMode: StatusFilter

    @UserDefault(key: "LAST_PREFS_TAB_SELECTED", defaultValue: 0)
    static var lastPreferencesTabSelected: Int

    @UserDefault(key: "LAST_PREFS_TAB_SELECTED_OSX", defaultValue: 0)
    static var lastPreferencesTabSelectedOSX: Int

    @EnumUserDefault(key: "CLOSE_HANDLING_POLICY_2", defaultValue: KeepPolicy.mine)
    static var closeHandlingPolicy: KeepPolicy
    static let closeHandlingPolicyHelp = "How to handle an item when it is believed to be closed (or has disappeared)."

    @EnumUserDefault(key: "MERGE_HANDLING_POLICY_2", defaultValue: KeepPolicy.mine)
    static var mergeHandlingPolicy: KeepPolicy
    static let mergeHandlingPolicyHelp = "How to handle an item when it is detected as merged."

    static let statusItemRefreshBatchSizeHelp = "Because querying statuses can be bandwidth and time intensive, Trailer will scan for updates on items that haven't been scanned for the longest time, at every refresh, up to a maximum of this number of items. Higher values mean longer sync times and more API usage."
    static var statusItemRefreshBatchSize: Int {
        get { if let n = self["STATUS_ITEM_REFRESH_BATCH"] as? Int { return n > 0 ? n : 100 } else { return 100 } }
        set { self["STATUS_ITEM_REFRESH_BATCH"] = newValue }
    }

    @UserDefault(key: "UPDATE_CHECK_INTERVAL_KEY", defaultValue: 8)
    static var checkForUpdatesInterval: Int

    @AssignmentPlacementUserDefault(key: "ASSIGNED_REVIEW_HANDLING_POLICY", defaultValue: .hidden(cause: .unknown))
    static var assignedDirectReviewHandlingPolicy: Section
    static let assignedDirectReviewHandlingPolicyHelp = "If an item is assigned for you to review, Trailer can move it to a specific section or leave it as-is."

    @AssignmentPlacementUserDefault(key: "ASSIGNED_REVIEW_TEAM_HANDLING_POLICY", defaultValue: .hidden(cause: .unknown))
    static var assignedTeamReviewHandlingPolicy: Section
    static let assignedTeamReviewHandlingPolicyHelp = "If an item is assigned for your team to review, Trailer can move it to a specific section or leave it as-is."

    @AssignmentPlacementUserDefault(key: "ASSIGNED_PR_HANDLING_POLICY", defaultValue: .mine)
    static var assignedItemDirectHandlingPolicy: Section
    static let assignedItemDirectHandlingPolicyHelp = "If an item is assigned to you, Trailer can move it to a specific section or leave it as-is."

    @AssignmentPlacementUserDefault(key: "ASSIGNED_PR_TEAM_HANDLING_POLICY", defaultValue: .mine)
    static var assignedItemTeamHandlingPolicy: Section
    static let assignedItemTeamHandlingPolicyHelp = "If an item is assigned to your team(s), Trailer can move it to a specific section or leave it as-is."

    @EnumUserDefault(key: "NEW_PR_DISPLAY_POLICY_INDEX", defaultValue: .hide)
    static var displayPolicyForNewPrs: RepoDisplayPolicy
    static let displayPolicyForNewPrsHelp = "When a new repository is detected in your watchlist, this display policy will be applied by default to pull requests that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."

    @EnumUserDefault(key: "NEW_ISSUE_DISPLAY_POLICY_INDEX", defaultValue: .hide)
    static var displayPolicyForNewIssues: RepoDisplayPolicy
    static let displayPolicyForNewIssuesHelp = "When a new repository is detected in your watchlist, this display policy will be applied by default to issues that come from it. You can further customize the display policy for any individual repository from the 'Repositories' tab."

    @MovePlacementUserDefault(key: "NEW_MENTION_MOVE_POLICY", defaultValue: .mentioned)
    static var newMentionMovePolicy: Section
    static let newMentionMovePolicyHelp = "If your username is mentioned in an item's description or a comment posted inside it, move the item to the specified section."

    @MovePlacementUserDefault(key: "TEAM_MENTION_MOVE_POLICY", defaultValue: .mentioned)
    static var teamMentionMovePolicy: Section
    static let teamMentionMovePolicyHelp = "If the name of one of the teams you belong to is mentioned in an item's description or a comment posted inside it, move the item to the specified section."

    @MovePlacementUserDefault(key: "NEW_ITEM_IN_OWNED_REPO_MOVE_POLICY", defaultValue: .hidden(cause: .unknown))
    static var newItemInOwnedRepoMovePolicy: Section
    static let newItemInOwnedRepoMovePolicyHelp = "Automatically move an item to the specified section if it has been created in a repo which you own, even if there is no direct mention of you."

    /////////////////////////// STRINGS

    @UserDefault(key: "DEFAULT_APP_FOR_OPENING_ITEMS", defaultValue: "")
    static var defaultAppForOpeningItems: String

    @UserDefault(key: "DEFAULT_APP_FOR_OPENING_WEB", defaultValue: "")
    static var defaultAppForOpeningWeb: String

    @UserDefault(key: "STATUS_FILTERING_TERMS_KEY", defaultValue: [])
    static var statusFilteringTerms: [String]
    static let statusFilteringTermsHelp = "You can specify specific terms which can then be matched against status items, in order to hide or show them."

    @UserDefault(key: "COMMENT_AUTHOR_BLACKLIST", defaultValue: [])
    static var commentAuthorBlacklist: [String]

    @UserDefault(key: "ITEM_AUTHOR_BLACKLIST", defaultValue: [])
    static var itemAuthorBlacklist: [String]
    static let itemAuthorBlacklistHelp = "Items from the specified usernames will be hidden."

    @UserDefault(key: "LABEL_BLACKLIST", defaultValue: [])
    static var labelBlacklist: [String]
    static let labelBlacklistHelp = "Items containing the specified labels will be hidden."

    @UserDefault(key: "HOTKEY_LETTER", defaultValue: "T")
    static var hotkeyLetter: String

    @UserDefault(key: "LAST_RUN_VERSION_KEY", defaultValue: "")
    static var lastRunVersion: String

    /////////////////////////// FLOATS

    #if os(iOS)
        static let backgroundRefreshPeriodHelp = "The minimum amount of time to wait before requesting an update when the app is in the background. Even though this is quite efficient, it's still a good idea to keep this to a high value in order to keep battery and bandwidth use low. The default of half an hour is generally a good number. Please note that iOS may ignore this value and perform background refreshes at longer intervals depending on battery level and other reasons."
        static var backgroundRefreshPeriod: TimeInterval {
            get { if let n = self["IOS_BACKGROUND_REFRESH_PERIOD_KEY"] as? TimeInterval { return n > 0 ? n : 1800 } else { return 1800 } }
            set { self["IOS_BACKGROUND_REFRESH_PERIOD_KEY"] = newValue }
        }
    #else
        static let refreshPeriodHelp = "How often to refresh items when the app is active and in the foreground."
        static var refreshPeriod: TimeInterval {
            get { if let n = self["REFRESH_PERIOD_KEY"] as? TimeInterval { return n < 60 ? 120 : n } else { return 120 } }
            set { self["REFRESH_PERIOD_KEY"] = newValue }
        }
    #endif

    static let newRepoCheckPeriodHelp = "How long before reloading your team list and watched repositories from a server. Since this doesn't change often, it's good to keep this as high as possible in order to keep bandwidth use as low as possible during refreshes. Set this to a lower value if you often update your watched repositories or teams."
    static var newRepoCheckPeriod: Float {
        get { if let n = self["NEW_REPO_CHECK_PERIOD"] as? Float { return max(n, 2) } else { return 2 } }
        set { self["NEW_REPO_CHECK_PERIOD"] = newValue }
    }

    /////////////////////////// DATES

    @OptionalUserDefault(key: "LAST_SUCCESSFUL_REFRESH")
    static var lastSuccessfulRefresh: Date?

    @OptionalUserDefault(key: "LAST_EXPORT_TIME")
    static var lastExportDate: Date?

    /////////////////////////// URLs

    static var lastExportUrl: URL? {
        get {
            if let s = self["LAST_EXPORT_URL"] as? String {
                return URL(string: s)
            } else {
                return nil
            }
        }
        set { self["LAST_EXPORT_URL"] = newValue?.absoluteString }
    }

    /////////////////////////// SWITCHES

    @EnumUserDefault(key: "V4_ID_MIGRATION_PHASE", defaultValue: .pending)
    static var V4IdMigrationPhase: MigrationStatus

    @UserDefault(key: "HIDE_ARCHIVED_REPOS", defaultValue: false)
    static var hideArchivedRepos: Bool
    static let hideArchivedReposHelp = "Automatically hide repositories which have been marked as archived"

    @UserDefault(key: "HIDE_MENUBAR_COUNTS", defaultValue: false)
    static var hideMenubarCounts: Bool
    static let hideMenubarCountsHelp = "Hide the counts of items in each status item in the menubar"

    @UserDefault(key: "HIDE_SNOOZED_ITEMS", defaultValue: false)
    static var hideSnoozedItems: Bool
    static let hideSnoozedItemsHelp = "Hide the snoozed items section"

    @UserDefault(key: "HIDE_UNCOMMENTED_PRS_KEY", defaultValue: false)
    static var hideUncommentedItems: Bool
    static let hideUncommentedItemsHelp = "Only show items which have red number badges."

    @UserDefault(key: "SHOW_COMMENTS_EVERYWHERE_KEY", defaultValue: false)
    static var showCommentsEverywhere: Bool
    static let showCommentsEverywhereHelp = "Badge and send notificatons for items in the 'all' sections as well as your own and participated ones."

    @UserDefault(key: "SORT_ORDER_KEY", defaultValue: false)
    static var sortDescending: Bool
    static let sortDescendingHelp = "The direction to sort items based on the criterion below. Toggling this option will change the set of options available in the option below to better reflect what that will do."

    @UserDefault(key: "SHOW_UPDATED_KEY", defaultValue: false)
    static var showCreatedInsteadOfUpdated: Bool
    static let showCreatedInsteadOfUpdatedHelp = "Trailer will usually display the time of the most recent activity in an item, such as comments. This setting replaces that with the orignal creation time of the item. Together with the sorting options, this is useful for helping prioritise items based on how old, or new, they are."

    @UserDefault(key: "DONT_KEEP_MY_PRS_KEY", defaultValue: false)
    static var dontKeepPrsMergedByMe: Bool
    static let dontKeepPrsMergedByMeHelp = "If a PR is detected as merged by you, remove it immediately from the list of merged items"

    @UserDefault(key: "HIDE_AVATARS_KEY", defaultValue: false)
    static var hideAvatars: Bool
    static let hideAvatarsHelp = "Hide the image of the author's avatar on the left of listed items"

    @UserDefault(key: "HIDE_NOTIFICATION_AVATARS_KEY", defaultValue: false)
    static var hideAvatarsInNotifications: Bool
    static let hideAvatarsInNotificationsHelp = "Hide the image of the author's avatar in the notifications that Trailer posts"

    @UserDefault(key: "DONT_ASK_BEFORE_WIPING_MERGED", defaultValue: false)
    static var dontAskBeforeWipingMerged: Bool
    static let dontAskBeforeWipingMergedHelp = "Don't ask for confirmation when you select 'Remove all merged items'. Please note there is no confirmation when selecting this from the Apple Watch, irrespective of this setting."

    @UserDefault(key: "DONT_ASK_BEFORE_WIPING_CLOSED", defaultValue: false)
    static var dontAskBeforeWipingClosed: Bool
    static let dontAskBeforeWipingClosedHelp = "Don't ask for confirmation when you select 'Remove all closed items'. Please note there is no confirmation when selecting this from the Apple Watch, irrespective of this setting."

    @UserDefault(key: "GROUP_BY_REPO", defaultValue: false)
    static var groupByRepo: Bool
    static let groupByRepoHelp = "Sort and gather items from the same repository next to each other, before applying the criterion specified above."

    @UserDefault(key: "SHOW_LABELS", defaultValue: false)
    static var showLabels: Bool
    static let showLabelsHelp = "Show labels associated with items, usually a good idea"

    @UserDefault(key: "SHOW_STATUS_ITEMS", defaultValue: false)
    static var showStatusItems: Bool
    static let showStatusItemsHelp = "Show status items, such as CI results or messages from code review services, that are attached to items on the server."

    @UserDefault(key: "MAKE_STATUS_ITEMS_SELECTABLE", defaultValue: false)
    static var makeStatusItemsSelectable: Bool
    static let makeStatusItemsSelectableHelp = "Normally you have to Cmd-click on status items to visit their relayed links, this option makes them always selectable, but it makes it easier to accidentally end up opening a status item page instead of an item's page."

    @UserDefault(key: "OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY", defaultValue: false)
    static var openPrAtFirstUnreadComment: Bool
    static let openPrAtFirstUnreadCommentHelp = "When opening the web view for an item, skip directly down to the first comment that has not been read, rather than starting from the top of the item's web page."

    @UserDefault(key: "HOTKEY_ENABLE", defaultValue: false)
    static var hotkeyEnable: Bool

    @UserDefault(key: "HOTKEY_CONTROL_MODIFIER", defaultValue: false)
    static var hotkeyControlModifier: Bool

    @UserDefault(key: "DISABLE_ALL_COMMENT_NOTIFICATIONS", defaultValue: false)
    static var disableAllCommentNotifications: Bool
    static let disableAllCommentNotificationsHelp = "Do not get notified about any comments at all."

    @UserDefault(key: "NOTIFY_ON_STATUS_UPDATES", defaultValue: false)
    static var notifyOnStatusUpdates: Bool
    static let notifyOnStatusUpdatesHelp = "Post notifications when status items change. Useful for tracking the CI build state of your own items, for instance."

    @UserDefault(key: "NOTIFY_ON_STATUS_UPDATES_ALL", defaultValue: false)
    static var notifyOnStatusUpdatesForAllPrs: Bool
    static let notifyOnStatusUpdatesForAllPrsHelp = "Notificaitons for status items are sent only for your own and particiapted items by default. Select this to receive status update notifications for the items in the 'all' section too."

    @UserDefault(key: "SHOW_ISSUES_IN_WATCH_GLANCE", defaultValue: false)
    static var preferIssuesInWatch: Bool
    static let preferIssuesInWatchHelp = "If there is only enough space to display one count or set of statistics on the Apple Watch, prefer the ones for issues rather than the ones for PRs."

    @UserDefault(key: "HIDE_DESCRIPTION_IN_WATCH_DETAIL_VIEW", defaultValue: false)
    static var hideDescriptionInWatchDetail: Bool
    static let hideDescriptionInWatchDetailHelp = "When showing the full detail view of items on the Apple Watch, skip showing the description of the item, instead showing only status and comments for it."

    @UserDefault(key: "AUTO_REPEAT_SETTINGS_EXPORT", defaultValue: false)
    static var autoRepeatSettingsExport: Bool

    @UserDefault(key: "DONT_CONFIRM_SETTINGS_IMPORT", defaultValue: false)
    static var dontConfirmSettingsImport: Bool

    static let removeNotificationsWhenItemIsRemovedHelp = "When an item is removed, whether through user action or automatically due to settings, also remove any notifications in the Notification Center that are related to this item."
    @UserDefault(key: "REMOVE_RELATED_NOTIFICATIONS_ON_ITEM_REMOVE", defaultValue: true)
    static var removeNotificationsWhenItemIsRemoved: Bool

    @UserDefault(key: "INCLUDE_SERVERS_IN_FILTER", defaultValue: false)
    static var includeServersInFilter: Bool
    static let includeServersInFilterHelp = "Check the name of the server an item came from when selecting it for inclusion in filtered results. You can also prefix a search with 'server:' to specifically search for this."

    @UserDefault(key: "HIDE_PRS_THAT_ARENT_PASSING", defaultValue: false)
    static var hidePrsThatArentPassing: Bool
    static let hidePrsThatArentPassingHelp = "Hide PR items which have status items, but are not all green. Useful for hiding PRs which are not ready to review or those who have not passed certain checks yet."

    @UserDefault(key: "HIDE_PRS_THAT_ARENT_PASSING_ONLY_IN_ALL", defaultValue: false)
    static var hidePrsThatDontPassOnlyInAll: Bool
    static let hidePrsThatDontPassOnlyInAllHelp = "Normally hiding red PRs will happen on every section. Selecting this will limit that filter to the 'All' section only, so red PRs which are yours or you have participated in will still show up."

    @UserDefault(key: "DISPLAY_MILESTONES", defaultValue: false)
    static var showMilestones: Bool
    static let showMilestonesHelp = "Include milestone information, if any, on current items."

    @UserDefault(key: "SHOW_RELATIVE_DATES", defaultValue: false)
    static var showRelativeDates: Bool
    static let showRelativeDatesHelp = "Show relative dates to now, e.g. '6d, 4h ago' instead of '12 May 2017, 11:00"

    @UserDefault(key: "NOTIFY_ON_REVIEW_CHANGE_REQUESTS", defaultValue: false)
    static var notifyOnReviewChangeRequests: Bool
    static let notifyOnReviewChangeRequestsHelp = "Issue a notification when someone creates a review in a PR that requires changes."

    @UserDefault(key: "NOTIFY_ON_REVIEW_ACCEPTANCES", defaultValue: false)
    static var notifyOnReviewAcceptances: Bool
    static let notifyOnReviewAcceptancesHelp = "Issue a notification when someone accepts the changes related to a review in a PR that required changes."

    @UserDefault(key: "NOTIFY_ON_REVIEW_DISMISSALS", defaultValue: false)
    static var notifyOnReviewDismissals: Bool
    static let notifyOnReviewDismissalsHelp = "Issue a notification when someone dismissed a review in a PR that required changes."

    @UserDefault(key: "NOTIFY_ON_ALL_REVIEW_CHANGE_REQUESTS", defaultValue: false)
    static var notifyOnAllReviewChangeRequests: Bool
    static let notifyOnAllReviewChangeRequestsHelp = "Do this for all items, not just those created by me."

    @UserDefault(key: "NOTIFY_ON_ALL_REVIEW_ACCEPTANCES", defaultValue: false)
    static var notifyOnAllReviewAcceptances: Bool
    static let notifyOnAllReviewAcceptancesHelp = "Do this for all items, not just those created by me."

    @UserDefault(key: "NOTIFY_ON_ALL_REVIEW_DISMISSALS", defaultValue: false)
    static var notifyOnAllReviewDismissals: Bool
    static let notifyOnAllReviewDismissalsHelp = "Do this for all items, not just those created by me."

    @UserDefault(key: "NOTIFY_ON_REVIEW_ASSIGNMENTS", defaultValue: false)
    static var notifyOnReviewAssignments: Bool
    static let notifyOnReviewAssignmentsHelp = "Issue a notification when someone assigns me a PR to review."

    @UserDefault(key: "SHOW_STATUSES_EVERYWHERE", defaultValue: false)
    static var showStatusesOnAllItems: Bool
    static let showStatusesOnAllItemsHelp = "Show statuses in the 'all' section too."

    @UserDefault(key: "UPDATE_CHECK_AUTO_KEY", defaultValue: true)
    static var checkForUpdatesAutomatically: Bool
    static let checkForUpdatesAutomaticallyHelp = "Check for updates to Trailer automatically. It is generally a very good idea to keep this selected, unless you are using an external package manager to manage the updates."

    @UserDefault(key: "SHOW_REPOS_IN_NAME", defaultValue: true)
    static var showReposInName: Bool
    static let showReposInNameHelp = "Show the name of the repository each item comes from."

    @UserDefault(key: "INCLUDE_TITLES_IN_FILTER", defaultValue: true)
    static var includeTitlesInFilter: Bool
    static let includeTitlesInFilterHelp = "Check item titles when selecting items for inclusion in filtered results. You can also prefix a search with 'title:' to specifically search for this."

    @UserDefault(key: "MARK_PRS_AS_UNREAD_ON_NEW_COMMITS", defaultValue: false)
    static var markPrsAsUnreadOnNewCommits: Bool
    static let markPrsAsUnreadOnNewCommitsHelp = "Mark a PR with an exclamation mark even if they it may not have unread comments, in case there have been new commits from other users."

    @UserDefault(key: "INCLUDE_MILESTONES_IN_FILTER", defaultValue: false)
    static var includeMilestonesInFilter: Bool
    static let includeMilestonesInFilterHelp = "Check item milestone names for inclusion in filtered results. You can also prefix a search with 'milestone:' to specifically search for this."

    @UserDefault(key: "INCLUDE_ASSIGNEE_NAMES_IN_FILTER", defaultValue: false)
    static var includeAssigneeNamesInFilter: Bool
    static let includeAssigneeInFilterHelp = "Check item assignee names for inclusion in filtered results. You can also prefix a search with 'assignee:' to specifically search for this."

    @UserDefault(key: "INCLUDE_NUMBERS_IN_FILTER", defaultValue: false)
    static var includeNumbersInFilter: Bool
    static let includeNumbersInFilterHelp = "Check the PR/Issue number of the item when selecting it for inclusion in filtered results. You can also prefix a search with 'number:' to specifically search for this."

    @UserDefault(key: "INCLUDE_REPOS_IN_FILTER", defaultValue: true)
    static var includeReposInFilter: Bool
    static let includeReposInFilterHelp = "Check repository names when selecting items for inclusion in filtered results. You can also prefix a search with 'repo:' to specifically search for this."

    @UserDefault(key: "INCLUDE_LABELS_IN_FILTER", defaultValue: true)
    static var includeLabelsInFilter: Bool
    static let includeLabelsInFilterHelp = "Check labels of items when selecting items for inclusion in filtered results. You can also prefix a search with 'label:' to specifically search for this."

    @UserDefault(key: "AUTO_ADD_NEW_REPOS", defaultValue: true)
    static var automaticallyAddNewReposFromWatchlist: Bool
    static let automaticallyAddNewReposFromWatchlistHelp = "Automatically add to Trailer any repos are added to your remote watchlist"

    @UserDefault(key: "AUTO_REMOVE_DELETED_REPOS", defaultValue: true)
    static var automaticallyRemoveDeletedReposFromWatchlist: Bool
    static let automaticallyRemoveDeletedReposFromWatchlistHelp = "Automatically remove from Trailer any (previously automatically added) repos if they are no longer on your remote watchlist"

    @UserDefault(key: "INCLUDE_USERS_IN_FILTER", defaultValue: true)
    static var includeUsersInFilter: Bool
    static let includeUsersInFilterHelp = "Check the name of the author of an item when selecting it for inclusion in filtered results. You can also prefix a search with 'user:' to specifically search for this."

    @UserDefault(key: "INCLUDE_STATUSES_IN_FILTER", defaultValue: true)
    static var includeStatusesInFilter: Bool
    static let includeStatusesInFilterHelp = "Check status lines of items when selecting items for inclusion in filtered results. You can also prefix a search with 'status:' to specifically search for this."

    @UserDefault(key: "SHOW_STATUSES_GRAY", defaultValue: true)
    static var showStatusesGray: Bool
    static let showStatusesGrayHelp = "Include neutral statuses in an item's status list"

    @UserDefault(key: "SHOW_STATUSES_GREEN", defaultValue: true)
    static var showStatusesGreen: Bool
    static let showStatusesGreenHelp = "Include green statuses in an item's status list"

    @UserDefault(key: "SHOW_STATUSES_YELLOW", defaultValue: true)
    static var showStatusesYellow: Bool
    static let showStatusesYellowHelp = "Include yellow statuses in an item's status list"

    @UserDefault(key: "SHOW_STATUSES_RED", defaultValue: true)
    static var showStatusesRed: Bool
    static let showStatusesRedHelp = "Include red statuses in an item's status list"

    @UserDefault(key: "HOTKEY_COMMAND_MODIFIER", defaultValue: true)
    static var hotkeyCommandModifier: Bool

    @UserDefault(key: "HOTKEY_OPTION_MODIFIER", defaultValue: true)
    static var hotkeyOptionModifier: Bool

    @UserDefault(key: "HOTKEY_SHIFT_MODIFIER", defaultValue: true)
    static var hotkeyShiftModifier: Bool

    @UserDefault(key: "GRAY_OUT_WHEN_REFRESHING", defaultValue: true)
    static var grayOutWhenRefreshing: Bool
    static let grayOutWhenRefreshingHelp = "Gray out the menubar icon when refreshing data from the configured servers. You may want to turn this off if you find that distracting or use a menu bar management tool that automatically highlights menubar items which get updated"

    @UserDefault(key: "API_SERVERS_IN_SEPARATE_MENUS", defaultValue: false)
    static var showSeparateApiServersInMenu: Bool
    static let showSeparateApiServersInMenuHelp = "Show each API server as a separate item on the menu bar"

    @UserDefault(key: "QUERY_AUTHORED_PRS", defaultValue: false)
    static var queryAuthoredPRs: Bool
    static let queryAuthoredPRsHelp = "Query all authored PRs for the current user, irrespective of repository visibility or if the repository is in the watchlist."

    @UserDefault(key: "QUERY_AUTHORED_ISSUES", defaultValue: false)
    static var queryAuthoredIssues: Bool
    static let queryAuthoredIssuesHelp = "Query all authored issues for the current user, irrespective of repository visibility or if the repository is in the watchlist."

    @UserDefault(key: "ASSUME_READ_ITEM_IF_USER_HAS_NEWER_COMMENTS", defaultValue: false)
    static var assumeReadItemIfUserHasNewerComments: Bool
    static let assumeReadItemIfUserHasNewerCommentsHelp = "Mark any comments posted by others before your own as read. Warning: Only turn this on if you are sure you can catch any comments that others may add while you are adding yours! (This is a very useful setting for *secondary* Trailer displays)"

    @UserDefault(key: "DISPLAY_REVIEW_CHANGE_REQUESTS", defaultValue: false)
    static var displayReviewsOnItems: Bool
    static let displayReviewsOnItemsHelp = "List requested, approving, and blocking reviews in the list of Pull Requests."

    @UserDefault(key: "REACTION_SCANNING_BATCH", defaultValue: 100)
    static var reactionScanningBatchSize: Int
    static let reactionScanningBatchSizeHelp = "Because querying reactions can be bandwidth and time intensive, Trailer will scan for updates on items that haven't been scanned for the longest time, at every refresh, up to a maximum of this number of items. Higher values mean longer sync times and more API usage."

    @UserDefault(key: "NOTIFY_ON_ITEM_REACTIONS", defaultValue: false)
    static var notifyOnItemReactions: Bool
    static let notifyOnItemReactionsHelp = "Count reactions to PRs and issues as comments. Increase the total count. Notify and badge an item as unread depending on the comment section settings."

    @UserDefault(key: "NOTIFY_ON_COMMENT_REACTIONS", defaultValue: false)
    static var notifyOnCommentReactions: Bool
    static let notifyOnCommentReactionsHelp = "Count reactions to comments themselves as comments. Increase the total count of the item that contains the comment being reacted to. Notify and badge it as unread depending on the comment section settings."

    @UserDefault(key: "DISPLAY_NUMBERS_FOR_ITEMS", defaultValue: false)
    static var displayNumbersForItems: Bool
    static let displayNumbersForItemsHelp = "Prefix titles of items with the number of the referenced PR or issue."

    @EnumUserDefault(key: "DRAFT_HANDLING_POLICY", defaultValue: .nothing)
    static var draftHandlingPolicy: DraftHandlingPolicy
    static let draftHandlingPolicyHelp = "How to deal with a PR if it is marked as a draft."

    @UserDefault(key: "COUNT_VISIBLE_SNOOZED_ITEMS", defaultValue: true)
    static var countVisibleSnoozedItems: Bool
    static let countVisibleSnoozedItemsHelp = "Include visible snoozed items in menubar count."

    @UserDefault(key: "SHOW_BASE_AND_HEAD_BRANCHES", defaultValue: false)
    static var showBaseAndHeadBranches: Bool
    static let showBaseAndHeadBranchesHelp = "Display the source and destination branches for PRs."

    @UserDefault(key: "MARK_UNMERGEABLE_ITEMS", defaultValue: false)
    static var markUnmergeablePrs: Bool
    static let markUnmergeablePrsHelp = "Indicate PRs which cannot be merged. This option only works for items synced via the new v4 API."

    @UserDefault(key: "SHOW_PR_LINES", defaultValue: false)
    static var showPrLines: Bool
    static let showPrLinesHelp = "Sync and show the number of lines added and/or removed on PRs. This option only works for items synced via the new v4 API."

    @UserDefault(key: "SHOW_CLOSING_INFO", defaultValue: false)
    static var showClosingInfo: Bool
    static let showClosingInfoHelp = "If a PR closes a certain issue, or an Issue is closed by a PR, this option will display that. This option only works for items synced via the new v4 API."

    @UserDefault(key: "SCAN_CLOSED_AND_MERGED", defaultValue: false)
    static var scanClosedAndMergedItems: Bool
    static let scanClosedAndMergedItemsHelp = "Also highlight unread comments on closed and merged items. This option only works for items synced via the new v4 API."

    @UserDefault(key: "REQUESTED_TEAM_REVIEWS", defaultValue: false)
    static var showRequestedTeamReviews: Bool
    static let showRequestedTeamReviewsHelp = "Display the name(s) of teams which have been assigned as reviewers on PRs"

    @UserDefault(key: "REVIEWS_AUTOHIDE_MY_APPROVED", defaultValue: false)
    static var autoHidePrsIApproved: Bool
    static let autoHidePrsIApprovedHelp = "Automatically hide PRs which I have reviewed and approved. The PR will re-appear if a review is requested again."

    @UserDefault(key: "REVIEWS_AUTOHIDE_MY_REJECTED", defaultValue: false)
    static var autoHidePrsIRejected: Bool
    static let autoHidePrsIRejectedHelp = "Automatically hide PRs which I have reviewed and requested changed for. The PR will re-appear if a review is requested again."

    @UserDefault(key: "USE_V4_API", defaultValue: false)
    static var useV4API: Bool
    static let useV4APIHelp = "In cases where the new v4 API is available, such as the public GitHub server, using it can result in significant efficiency and speed improvements when syncing."

    static let v4title = "Can't be turned on yet"
    static let v4DBMessage = "Your repo list seems to contain entries which have not yet been migrated in order to be able to use the new API.\n\nYou will have to perform a sync before being able to turn this setting on."
    static let v4DAPIessage = "One of your servers doesn't have a v4 API path defined. Please configure this before turning on v4 API support."
    static let reloadAllDataHelp = "Choosing this option will remove all synced data and reload everything from scratch. This can take a while and use up a large amount of API quota, so only use it if things seem broken."
    static let snoozeWakeOnCommentHelp = "Wake up snoozing items if a new comment is made"
    static let snoozeWakeOnMentionHelp = "Wake up snoozing items in you are mentioned in a new comment"
    static let snoozeWakeOnStatusUpdateHelp = "Wake up snoozing items if there is a status or CI update"

    //////////////////////// Filters

    @EnumUserDefault(key: "LABELS_INCLUSION_RULE", defaultValue: .excludeIfAny)
    static var labelsIncludionRule: InclusionSetting
    static let labelsIncludionRuleHelp = "How to handle the list of labels"

    @EnumUserDefault(key: "AUTHORS_INCLUSION_RULE", defaultValue: .excludeIfAny)
    static var authorsIncludionRule: InclusionSetting
    static let authorsIncludionRuleHelp = "How to handle the list of item authors"

    @EnumUserDefault(key: "COMMENTER_INCLUSION_RULE", defaultValue: .excludeIfAny)
    static var commenterInclusionRule: InclusionSetting
    static let commenterIncludionRuleHelp = "How to handle the list of comment authors"

    private static var filterLookup: [String: String] = {
        if let data = sharedDefaults.data(forKey: "PERSISTED_TAB_FILTERS"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return dict
        } else {
            return [:]
        }
    }()

    static func filter(for key: String) -> String? {
        filterLookup[key]
    }

    static func setFilter(to text: String, for key: String) {
        let new = text.isEmpty ? nil : text
        if new != filterLookup[key] {
            filterLookup[key] = new
            if let data = try? JSONEncoder().encode(filterLookup) {
                Logging.log("Persisting filters for menus")
                sharedDefaults.setValue(data, forKey: "PERSISTED_TAB_FILTERS")
            }
        }
    }

    @propertyWrapper
    struct UserDefault<Value> {
        let key: String
        let defaultValue: Value

        init(key: String, defaultValue: Value) {
            self.key = key
            self.defaultValue = defaultValue
        }

        var wrappedValue: Value {
            get {
                Settings[key] as? Value ?? defaultValue
            }
            set {
                Settings[key] = newValue
            }
        }
    }

    @propertyWrapper
    struct OptionalUserDefault<Value> {
        let key: String

        init(key: String) {
            self.key = key
        }

        var wrappedValue: Value? {
            get {
                Settings[key] as? Value
            }
            set {
                Settings[key] = newValue
            }
        }
    }

    @propertyWrapper
    struct EnumUserDefault<Value: RawRepresentable> {
        let key: String
        let defaultValue: Value

        init(key: String, defaultValue: Value) {
            self.key = key
            self.defaultValue = defaultValue
        }

        var wrappedValue: Value {
            get {
                if let o = Settings[key] as? Value.RawValue, let v = Value(rawValue: o) {
                    return v
                }
                return defaultValue
            }
            set {
                Settings[key] = newValue.rawValue
            }
        }
    }

    @propertyWrapper
    struct MovePlacementUserDefault {
        let key: String
        let defaultValue: Section

        init(key: String, defaultValue: Section) {
            self.key = key
            self.defaultValue = defaultValue
        }

        var wrappedValue: Section {
            get {
                if let o = Settings[key] as? Int {
                    return Section(movePolicySettingsValue: o)
                }
                return defaultValue
            }
            set {
                Settings[key] = newValue.movePolicySettingsValue
            }
        }
    }

    @propertyWrapper
    struct AssignmentPlacementUserDefault {
        let key: String
        let defaultValue: Section

        init(key: String, defaultValue: Section) {
            self.key = key
            self.defaultValue = defaultValue
        }

        var wrappedValue: Section {
            get {
                if let o = Settings[key] as? Int {
                    return Section(assignmentPolicySettingsValue: o)
                }
                return defaultValue
            }
            set {
                Settings[key] = newValue.assignmentPolicySettingsValue
            }
        }
    }
}
