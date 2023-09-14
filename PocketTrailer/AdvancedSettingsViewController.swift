import PopTimer
import UIKit

final class AdvancedSettingsViewController: UITableViewController, PickerViewControllerDelegate, UISearchResultsUpdating {
    private enum SettingsSection: Int {
        case Refresh, Display, Filtering, AppleWatch, Comments, Watchlist, Reviews, Reactions, Stauses, History, Confirm, Sort, Misc
        static let allNames = ["Auto Refresh", "Display", "Filtering", "Apple Watch", "Comments", "Watchlist", "Reviews", "Reactions", "Statuses", "History", "Don't confirm when", "Sorting", "Misc"]
        var title: String { SettingsSection.allNames[rawValue] }
    }

    private struct Setting {
        let section: SettingsSection
        let title: String
        let description: String
        let valueDisplayed: () -> String?
        let optionSelected: (Int, SettingsSection, Setting) -> Void

        func isRelevant(to searchText: String?, showingHelp: Bool) -> Bool {
            if let searchText, !searchText.isEmpty {
                title.localizedCaseInsensitiveContains(searchText) || (showingHelp && description.localizedCaseInsensitiveContains(searchText))
            } else {
                true
            }
        }
    }

    private lazy var settings = [
        Setting(section: .Refresh,
                title: "Background refresh interval (minimum)",
                description: Settings.backgroundRefreshPeriodHelp,
                valueDisplayed: { String(format: "%.0f minutes", Settings.backgroundRefreshPeriod / 60.0) },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    var values = [String]()
                    var count = 0
                    var previousIndex: Int?
                    // minutes
                    let period = Int(Settings.backgroundRefreshPeriod / 60)
                    for f in 2 ..< 1000 {
                        if f == period { previousIndex = count }
                        values.append("\(f) minutes")
                        count += 1
                    }
                    let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: previousIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Refresh,
                title: "Watchlist & team list refresh interval",
                description: Settings.newRepoCheckPeriodHelp,
                valueDisplayed: { String(format: "%.0f hours", Settings.newRepoCheckPeriod) },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    var values = [String]()
                    var count = 0
                    var previousIndex: Int?
                    // hours
                    let period = Int(Settings.newRepoCheckPeriod)
                    for f in 2 ..< 100 {
                        if f == period { previousIndex = count }
                        values.append("\(f) hours")
                        count += 1
                    }
                    let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: previousIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),

        Setting(section: .Display,
                title: "Show item labels",
                description: Settings.showLabelsHelp,
                valueDisplayed: { Settings.showLabels ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    let newValue = !Settings.showLabels
                    Settings.showLabels = newValue
                    if newValue, Settings.showLabels {
                        ApiServer.resetSyncOfEverything()
                        preferencesDirty = true
                        showLongSyncWarning()
                    }
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Display item creation times instead of update times",
                description: Settings.showCreatedInsteadOfUpdatedHelp,
                valueDisplayed: { Settings.showCreatedInsteadOfUpdated ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showCreatedInsteadOfUpdated.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Display relative times and dates",
                description: Settings.showRelativeDatesHelp,
                valueDisplayed: { Settings.showRelativeDates ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showRelativeDates.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Assigned items to me",
                description: Settings.assignedItemDirectHandlingPolicyHelp,
                valueDisplayed: { Settings.assignedItemDirectHandlingPolicy.placementName },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: Section.assignmentPlacementLabels, selectedIndex: Settings.assignedItemDirectHandlingPolicy.assignmentPolicyMenuIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Display,
                title: "Assigned items to my team(s)",
                description: Settings.assignedItemTeamHandlingPolicyHelp,
                valueDisplayed: { Settings.assignedItemTeamHandlingPolicy.placementName },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: Section.assignmentPlacementLabels, selectedIndex: Settings.assignedItemTeamHandlingPolicy.assignmentPolicyMenuIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Display,
                title: "Display repository names",
                description: Settings.showReposInNameHelp,
                valueDisplayed: { Settings.showReposInName ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showReposInName.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "…including base and head branches",
                description: Settings.showBaseAndHeadBranchesHelp,
                valueDisplayed: { Settings.showBaseAndHeadBranches ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showBaseAndHeadBranches.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Separate API servers into their own groups",
                description: Settings.showSeparateApiServersInMenuHelp,
                valueDisplayed: { Settings.showSeparateApiServersInMenu ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showSeparateApiServersInMenu.toggle()
                    Task { @MainActor in
                        popupManager.masterController.updateStatus(becauseOfChanges: true)
                    }
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Highlight PRs with new commits",
                description: Settings.markPrsAsUnreadOnNewCommitsHelp,
                valueDisplayed: { Settings.markPrsAsUnreadOnNewCommits ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.markPrsAsUnreadOnNewCommits.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Display milestones",
                description: Settings.showMilestonesHelp,
                valueDisplayed: { Settings.showMilestones ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showMilestones.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Prefix PR/Issue numbers in item titles",
                description: Settings.displayNumbersForItemsHelp,
                valueDisplayed: { Settings.displayNumbersForItems ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.displayNumbersForItems.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Draft PRs",
                description: Settings.draftHandlingPolicyHelp,
                valueDisplayed: { Settings.draftHandlingPolicy.label },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: DraftHandlingPolicy.allCases.map(\.label), selectedIndex: Settings.draftHandlingPolicy.rawValue, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Display,
                title: "Mark non-mergeable PRs (v4 API only)",
                description: Settings.markUnmergeablePrsHelp,
                valueDisplayed: { Settings.markUnmergeablePrs ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.markUnmergeablePrs.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Display,
                title: "Show PR line counts (v4 API only)",
                description: Settings.showPrLinesHelp,
                valueDisplayed: { Settings.showPrLines ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showPrLines.toggle()
                    settingsChangedTimer.push()

                }),
        Setting(section: .Display,
                title: "Show items that close or are closed by this item (v4 API only)",
                description: Settings.showClosingInfoHelp,
                valueDisplayed: { Settings.showClosingInfo ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showClosingInfo.toggle()
                    settingsChangedTimer.push()
                }),

        Setting(section: .Filtering,
                title: "Include item titles",
                description: Settings.includeTitlesInFilterHelp,
                valueDisplayed: { Settings.includeTitlesInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeTitlesInFilter.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Filtering,
                title: "Include repository names",
                description: Settings.includeReposInFilterHelp,
                valueDisplayed: { Settings.includeReposInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeReposInFilter.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Filtering,
                title: "Include labels",
                description: Settings.includeLabelsInFilterHelp,
                valueDisplayed: { Settings.includeLabelsInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeLabelsInFilter.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Filtering,
                title: "Include statuses",
                description: Settings.includeStatusesInFilterHelp,
                valueDisplayed: { Settings.includeStatusesInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeStatusesInFilter.toggle()
                    settingsChangedTimer.push()

                }),
        Setting(section: .Filtering,
                title: "Include servers",
                description: Settings.includeServersInFilterHelp,
                valueDisplayed: { Settings.includeServersInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeServersInFilter.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Filtering,
                title: "Include usernames",
                description: Settings.includeUsersInFilterHelp,
                valueDisplayed: { Settings.includeUsersInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeUsersInFilter.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Filtering,
                title: "Include PR or issue numbers",
                description: Settings.includeNumbersInFilterHelp,
                valueDisplayed: { Settings.includeNumbersInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeNumbersInFilter.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Filtering,
                title: "Include milestones",
                description: Settings.includeMilestonesInFilterHelp,
                valueDisplayed: { Settings.includeMilestonesInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeMilestonesInFilter.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Filtering,
                title: "Include assignee names",
                description: Settings.includeAssigneeInFilterHelp,
                valueDisplayed: { Settings.includeAssigneeNamesInFilter ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.includeAssigneeNamesInFilter.toggle()
                    settingsChangedTimer.push()

                }),
        Setting(section: .Filtering,
                title: "Hide items created by these usernames…",
                description: Settings.itemAuthorBlacklistHelp,
                valueDisplayed: { ">" },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    performSegue(withIdentifier: "showBlacklist", sender: CommentBlacklistViewController.Mode.itemAuthors)
                }),
        Setting(section: .Filtering,
                title: "Hide items that contain these labels…",
                description: Settings.itemAuthorBlacklistHelp,
                valueDisplayed: { ">" },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    performSegue(withIdentifier: "showBlacklist", sender: CommentBlacklistViewController.Mode.labels)
                }),

        Setting(section: .AppleWatch,
                title: "Prefer issues instead of PRs in Apple Watch complications",
                description: Settings.preferIssuesInWatchHelp,
                valueDisplayed: { Settings.preferIssuesInWatch ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.preferIssuesInWatch.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .AppleWatch,
                title: "Hide descriptions in Apple Watch detail views",
                description: Settings.hideDescriptionInWatchDetailHelp,
                valueDisplayed: { Settings.hideDescriptionInWatchDetail ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.hideDescriptionInWatchDetail.toggle()
                }),

        Setting(section: .Comments,
                title: "Badge & send alerts for the 'all' section too",
                description: Settings.showCommentsEverywhereHelp,
                valueDisplayed: { Settings.showCommentsEverywhere ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showCommentsEverywhere.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Comments,
                title: "Only display items with unread badges",
                description: Settings.hideUncommentedItemsHelp,
                valueDisplayed: { Settings.hideUncommentedItems ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.hideUncommentedItems.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Comments,
                title: "Move items mentioning me to…",
                description: Settings.newMentionMovePolicyHelp,
                valueDisplayed: { Settings.newMentionMovePolicy.placementName },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: Section.movePlacementLabels, selectedIndex: Settings.newMentionMovePolicy.movePolicyMenuIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Comments,
                title: "Move items mentioning my teams to…",
                description: Settings.teamMentionMovePolicyHelp,
                valueDisplayed: { Settings.teamMentionMovePolicy.placementName },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: Section.movePlacementLabels, selectedIndex: Settings.teamMentionMovePolicy.movePolicyMenuIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Comments,
                title: "Move items created in my repos to…",
                description: Settings.newItemInOwnedRepoMovePolicyHelp,
                valueDisplayed: { Settings.newItemInOwnedRepoMovePolicy.placementName },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: Section.movePlacementLabels, selectedIndex: Settings.newItemInOwnedRepoMovePolicy.movePolicyMenuIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Comments,
                title: "Open items at first unread comment",
                description: Settings.openPrAtFirstUnreadCommentHelp,
                valueDisplayed: { Settings.openPrAtFirstUnreadComment ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.openPrAtFirstUnreadComment.toggle()
                }),
        Setting(section: .Comments,
                title: "Block comment notifications from usernames…",
                description: "A list of usernames whose comments you don't want to receive notifications for.",
                valueDisplayed: { ">" },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    performSegue(withIdentifier: "showBlacklist", sender: CommentBlacklistViewController.Mode.commentAuthors)
                }),
        Setting(section: .Comments,
                title: "Disable all comment notifications",
                description: Settings.disableAllCommentNotificationsHelp,
                valueDisplayed: { Settings.disableAllCommentNotifications ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.disableAllCommentNotifications.toggle()
                }),
        Setting(section: .Comments,
                title: "Mark any comments before my own as read",
                description: Settings.assumeReadItemIfUserHasNewerCommentsHelp,
                valueDisplayed: { Settings.assumeReadItemIfUserHasNewerComments ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.assumeReadItemIfUserHasNewerComments.toggle()
                }),

        Setting(section: .Watchlist,
                title: "PR visibility for new repos",
                description: Settings.displayPolicyForNewPrsHelp,
                valueDisplayed: { Settings.displayPolicyForNewPrs.name },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    var previousIndex = Settings.displayPolicyForNewPrs.rawValue
                    let v = PickerViewController.Info(title: setting.title, values: RepoDisplayPolicy.labels, selectedIndex: previousIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Watchlist,
                title: "Issue visibility for new repos",
                description: Settings.displayPolicyForNewIssuesHelp,
                valueDisplayed: { Settings.displayPolicyForNewIssues.name },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    var previousIndex = Settings.displayPolicyForNewIssues.rawValue
                    let v = PickerViewController.Info(title: setting.title, values: RepoDisplayPolicy.labels, selectedIndex: previousIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),

        Setting(section: .Reviews,
                title: "Show reviews for PRs",
                description: Settings.displayReviewsOnItemsHelp,
                valueDisplayed: { Settings.displayReviewsOnItems ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    let previousShouldSync = Settings.cache.requiresReviewApis
                    Settings.displayReviewsOnItems.toggle()
                    showOptionalReviewWarning(previousSync: previousShouldSync)
                }),
        Setting(section: .Reviews,
                title: "Show teams asked to review",
                description: Settings.showRequestedTeamReviewsHelp,
                valueDisplayed: { Settings.showRequestedTeamReviews ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    let previousShouldSync = Settings.cache.requiresReviewApis
                    Settings.showRequestedTeamReviews.toggle()
                    showOptionalReviewWarning(previousSync: previousShouldSync)
                }),
        Setting(section: .Reviews,
                title: "When a PR is assigned to me for review",
                description: Settings.assignedDirectReviewHandlingPolicyHelp,
                valueDisplayed: { Settings.assignedDirectReviewHandlingPolicy.placementName },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: Section.assignmentPlacementLabels, selectedIndex: Settings.assignedDirectReviewHandlingPolicy.assignmentPolicyMenuIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Reviews,
                title: "When a PR is assigned to my team(s) for review",
                description: Settings.assignedTeamReviewHandlingPolicyHelp,
                valueDisplayed: { Settings.assignedTeamReviewHandlingPolicy.placementName },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: Section.assignmentPlacementLabels, selectedIndex: Settings.assignedTeamReviewHandlingPolicy.assignmentPolicyMenuIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Reviews,
                title: "Notify on change requests",
                description: Settings.notifyOnReviewChangeRequestsHelp,
                valueDisplayed: { Settings.notifyOnReviewChangeRequests ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    let previousShouldSync = Settings.cache.requiresReviewApis
                    Settings.notifyOnReviewChangeRequests.toggle()
                    showOptionalReviewWarning(previousSync: previousShouldSync)
                    if !Settings.notifyOnReviewChangeRequests {
                        Settings.notifyOnAllReviewChangeRequests = false
                    }
                }),
        Setting(section: .Reviews,
                title: "…for all change requests",
                description: Settings.notifyOnAllReviewChangeRequestsHelp,
                valueDisplayed: { Settings.notifyOnAllReviewChangeRequests ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.notifyOnAllReviewChangeRequests.toggle()
                }),
        Setting(section: .Reviews,
                title: "Notify on approvals",
                description: Settings.notifyOnReviewAcceptancesHelp,
                valueDisplayed: { Settings.notifyOnReviewAcceptances ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    let previousShouldSync = Settings.cache.requiresReviewApis
                    Settings.notifyOnReviewAcceptances.toggle()
                    showOptionalReviewWarning(previousSync: previousShouldSync)
                }),
        Setting(section: .Reviews,
                title: "…for all approvals",
                description: Settings.notifyOnAllReviewAcceptancesHelp,
                valueDisplayed: { Settings.notifyOnAllReviewAcceptances ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.notifyOnAllReviewAcceptances.toggle()
                    if !Settings.notifyOnReviewAcceptances {
                        Settings.notifyOnAllReviewAcceptances = false
                    }
                }),
        Setting(section: .Reviews,
                title: "Notify on dismissals",
                description: Settings.notifyOnReviewDismissalsHelp,
                valueDisplayed: { Settings.notifyOnReviewDismissals ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    let previousShouldSync = Settings.cache.requiresReviewApis
                    Settings.notifyOnReviewDismissals.toggle()
                    showOptionalReviewWarning(previousSync: previousShouldSync)
                    if !Settings.notifyOnReviewDismissals {
                        Settings.notifyOnAllReviewDismissals = false
                    }
                }),
        Setting(section: .Reviews,
                title: "…for all dismissals",
                description: Settings.notifyOnAllReviewDismissalsHelp,
                valueDisplayed: { Settings.notifyOnAllReviewDismissals ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.notifyOnAllReviewDismissals.toggle()

                }),
        Setting(section: .Reviews,
                title: "Notify on assignments",
                description: Settings.notifyOnReviewAssignmentsHelp,
                valueDisplayed: { Settings.notifyOnReviewAssignments ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    let previousShouldSync = Settings.cache.requiresReviewApis
                    Settings.notifyOnReviewAssignments.toggle()
                    showOptionalReviewWarning(previousSync: previousShouldSync)
                }),

        Setting(section: .Reactions,
                title: "Count / notify on item reactions",
                description: Settings.notifyOnItemReactionsHelp,
                valueDisplayed: { Settings.notifyOnItemReactions ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.notifyOnItemReactions.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Reactions,
                title: "Count / notify on comment reactions",
                description: Settings.notifyOnCommentReactionsHelp,
                valueDisplayed: { Settings.notifyOnCommentReactions ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.notifyOnCommentReactions.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Reactions,
                title: "Scan for reactions",
                description: Settings.reactionScanningBatchSizeHelp,
                valueDisplayed: { "\(Settings.reactionScanningBatchSize) items per refresh" },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    var values = [String]()
                    values.append("1 item per refresh")
                    for f in 2 ..< 999 {
                        values.append("\(f) items per refresh")
                    }
                    let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: Settings.reactionScanningBatchSize - 1, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),

        Setting(section: .Stauses,
                title: "Show statuses",
                description: Settings.showStatusItemsHelp,
                valueDisplayed: { Settings.showStatusItems ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showStatusItems.toggle()
                    settingsChangedTimer.push()
                    if Settings.showStatusItems {
                        preferencesDirty = true
                    }
                }),
        Setting(section: .Stauses,
                title: "…for all PRs",
                description: Settings.showStatusesOnAllItemsHelp,
                valueDisplayed: { Settings.showStatusesOnAllItems ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showStatusesOnAllItems.toggle()
                    settingsChangedTimer.push()
                    if Settings.showStatusesOnAllItems {
                        preferencesDirty = true
                    }
                }),
        Setting(section: .Stauses,
                title: "Scan for statuses",
                description: Settings.statusItemRefreshBatchSizeHelp,
                valueDisplayed: { "\(Settings.statusItemRefreshBatchSize) items per refresh" },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    var values = [String]()
                    values.append("1 item per refresh")
                    for f in 2 ..< 999 {
                        values.append("\(f) items per refresh")
                    }
                    let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: Settings.statusItemRefreshBatchSize - 1, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Stauses,
                title: "Notify status changes for my & participated PRs",
                description: Settings.notifyOnStatusUpdatesHelp,
                valueDisplayed: { Settings.notifyOnStatusUpdates ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.notifyOnStatusUpdates.toggle()

                }),
        Setting(section: .Stauses,
                title: "…in the 'All' section too",
                description: Settings.notifyOnStatusUpdatesForAllPrsHelp,
                valueDisplayed: { Settings.notifyOnStatusUpdatesForAllPrs ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.notifyOnStatusUpdatesForAllPrs.toggle()
                }),
        Setting(section: .Stauses,
                title: "Hide PRs whose status items are not all green",
                description: Settings.hidePrsThatArentPassingHelp,
                valueDisplayed: { Settings.hidePrsThatArentPassing ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.hidePrsThatArentPassing.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Stauses,
                title: "…only in the 'All' section",
                description: Settings.hidePrsThatDontPassOnlyInAllHelp,
                valueDisplayed: { Settings.hidePrsThatDontPassOnlyInAll ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.hidePrsThatDontPassOnlyInAll.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Stauses,
                title: "Show neutral statuses",
                description: Settings.showStatusesGrayHelp,
                valueDisplayed: { Settings.showStatusesGray ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showStatusesGray.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Stauses,
                title: "Show green statuses",
                description: Settings.showStatusesGreenHelp,
                valueDisplayed: { Settings.showStatusesGreen ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showStatusesGreen.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Stauses,
                title: "Show yellow statuses",
                description: Settings.showStatusesYellowHelp,
                valueDisplayed: { Settings.showStatusesYellow ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showStatusesYellow.toggle()
                    settingsChangedTimer.push()

                }),
        Setting(section: .Stauses,
                title: "Show red statuses",
                description: Settings.showStatusesRedHelp,
                valueDisplayed: { Settings.showStatusesRed ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.showStatusesRed.toggle()
                    settingsChangedTimer.push()
                }),

        Setting(section: .History,
                title: "When something is merged",
                description: Settings.mergeHandlingPolicyHelp,
                valueDisplayed: { Settings.mergeHandlingPolicy.name },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: KeepPolicy.labels, selectedIndex: Settings.mergeHandlingPolicy.rawValue, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .History,
                title: "When something is closed",
                description: Settings.closeHandlingPolicyHelp,
                valueDisplayed: { Settings.closeHandlingPolicy.name },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let v = PickerViewController.Info(title: setting.title, values: KeepPolicy.labels, selectedIndex: Settings.closeHandlingPolicy.rawValue, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .History,
                title: "Don't keep PRs merged by me",
                description: Settings.dontKeepPrsMergedByMeHelp,
                valueDisplayed: { Settings.dontKeepPrsMergedByMe ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.dontKeepPrsMergedByMe.toggle()

                }),
        Setting(section: .History,
                title: "Clear notifications of removed items",
                description: Settings.removeNotificationsWhenItemIsRemovedHelp,
                valueDisplayed: { Settings.removeNotificationsWhenItemIsRemoved ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.removeNotificationsWhenItemIsRemoved.toggle()

                }),
        Setting(section: .History,
                title: "Highlight comments on closed or merged items",
                description: Settings.scanClosedAndMergedItemsHelp,
                valueDisplayed: { Settings.scanClosedAndMergedItems ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.scanClosedAndMergedItems.toggle()

                }),
        Setting(section: .History,
                title: "Auto-remove merged items",
                description: Settings.autoRemoveMergedItemsHelp,
                valueDisplayed: { Settings.autoRemoveMergedItems == 0 ? "Never" : "After \(Settings.autoRemoveMergedItems)d" },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    var values = ["Never", "After 1 day"]
                    for f in 2 ..< 999 {
                        values.append("After \(f) day(s)")
                    }
                    let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: Settings.autoRemoveMergedItems, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .History,
                title: "Auto-remove closed items",
                description: Settings.autoRemoveMergedItemsHelp,
                valueDisplayed: { Settings.autoRemoveClosedItems == 0 ? "Never" : "After \(Settings.autoRemoveClosedItems)d" },
                optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    var values = ["Never", "After 1 day"]
                    for f in 2 ..< 999 {
                        values.append("After \(f) day(s)")
                    }
                    let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: Settings.autoRemoveClosedItems, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),

        Setting(section: .Confirm,
                title: "Removing all merged items",
                description: Settings.dontAskBeforeWipingMergedHelp,
                valueDisplayed: { Settings.dontAskBeforeWipingMerged ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.dontAskBeforeWipingMerged.toggle()
                }),
        Setting(section: .Confirm,
                title: "Removing all closed items",
                description: Settings.dontAskBeforeWipingClosedHelp,
                valueDisplayed: { Settings.dontAskBeforeWipingClosed ? "✓" : " " },
                optionSelected: { _, _, _ in
                    Settings.dontAskBeforeWipingClosed.toggle()
                }),

        Setting(section: .Sort,
                title: "Direction",
                description: Settings.sortDescendingHelp,
                valueDisplayed: { Settings.sortDescending ? "Reverse" : "Normal" },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.sortDescending.toggle()
                    settingsChangedTimer.push()
                }),
        Setting(section: .Sort,
                title: "Criterion",
                description: Settings.sortMethodHelp,
                valueDisplayed: {
                    let m = Settings.sortMethod
                    return Settings.sortDescending ? m.reverseTitle : m.normalTitle
                }, optionSelected: { [weak self] originalIndex, section, setting in
                    guard let self else { return }
                    let valuesToPush = Settings.sortDescending ? SortingMethod.allCases.map(\.reverseTitle) : SortingMethod.allCases.map(\.normalTitle)
                    let v = PickerViewController.Info(title: setting.title, values: valuesToPush, selectedIndex: Settings.sortMethod.rawValue, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                    performSegue(withIdentifier: "showPicker", sender: v)
                }),
        Setting(section: .Sort,
                title: "Bunch by repository",
                description: Settings.groupByRepoHelp,
                valueDisplayed: { Settings.groupByRepo ? "✓" : " " },
                optionSelected: { [weak self] _, _, _ in
                    guard let self else { return }
                    Settings.groupByRepo.toggle()
                    settingsChangedTimer.push()
                })
    ]

    private var settingsChangedTimer: PopTimer!
    private var searchTimer: PopTimer!

    // for the picker
    private var showHelp = true
    private var importExport: ImportExport!

    @IBAction private func done(_: UIBarButtonItem) {
        presentedViewController?.dismiss(animated: false)
        dismiss(animated: true)
    }

    private var searchText: String?

    private func reload(searchChanged: Bool = false) {
        let previousSearchText = searchText
        if searchChanged {
            searchText = navigationItem.searchController?.searchBar.text?.trim
        }
        tableView.reloadData()
        if previousSearchText != searchText {
            Task { @MainActor in
                tableView.scrollRectToVisible(CGRect(origin: .zero, size: CGSize(width: 1, height: 1)), animated: false)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120

        let searchController = UISearchController(searchResultsController: nil)
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.searchBar.tintColor = view.tintColor
        searchController.searchBar.placeholder = "Filter"
        searchController.hidesNavigationBarDuringPresentation = true
        navigationItem.searchController = searchController

        navigationItem.hidesSearchBarWhenScrolling = false

        searchTimer = PopTimer(timeInterval: 0.2) { [weak self] in
            self?.reload(searchChanged: true)
        }

        settingsChangedTimer = PopTimer(timeInterval: 1.0) {
            await DataManager.postProcessAllItems(in: DataManager.main, settings: Settings.cache)
        }

        importExport = ImportExport(parent: self)
    }

    override func scrollViewDidScroll(_: UIScrollView) {
        view.endEditing(false)
    }

    func updateSearchResults(for _: UISearchController) {
        searchTimer.push()
    }

    override func scrollViewWillBeginDragging(_: UIScrollView) {
        let searchBar = navigationItem.searchController!.searchBar
        if searchBar.isFirstResponder {
            searchBar.resignFirstResponder()
        }
    }

    @IBAction private func importSelected(button: UIBarButtonItem) {
        importExport.importSelected(sender: button)
    }

    @IBAction private func exportSelected(button: UIBarButtonItem) {
        importExport.exportSelected(sender: button)
    }

    @IBAction private func toggleHelp(button _: UIBarButtonItem) {
        showHelp.toggle()
        if let s = navigationItem.searchController?.searchBar.text, !s.isEmpty {
            reload()
        } else {
            let r = Range(uncheckedBounds: (lower: 0, upper: tableView.numberOfSections))
            tableView.reloadSections(IndexSet(integersIn: r), with: .fade)
        }
    }

    private func buildFooter(_ message: String) -> UILabel {
        let p = NSMutableParagraphStyle()
        p.headIndent = 15.0
        p.firstLineHeadIndent = 15.0
        p.tailIndent = -15.0

        let l = UILabel()
        l.attributedText = NSAttributedString(
            string: message,
            attributes: [
                NSAttributedString.Key.font: UIFont.systemFont(ofSize: UIFont.smallSystemFontSize),
                NSAttributedString.Key.foregroundColor: UIColor.tertiaryLabel,
                NSAttributedString.Key.paragraphStyle: p
            ]
        )
        l.numberOfLines = 0
        return l
    }

    override func tableView(_: UITableView, viewForFooterInSection section: Int) -> UIView? {
        switch filteredSections[section].title {
        case SettingsSection.Filtering.title:
            buildFooter("You can use title: server: label: repo: user: number: milestone: assignee: and status: to filter specific properties, e.g. \"label:bug,suggestion\". Prefix with '!' to exclude some terms. You can also use \"state:\" with unread/open/closed/merged/snoozed/draft/conflict as an argument, e.g. \"state:unread,draft\"")
        case SettingsSection.Reviews.title:
            buildFooter("To disable usage of the Reviews API, uncheck all options above and set the moving option to \"Don't Move It\".")
        case SettingsSection.Reactions.title:
            buildFooter("To completely disable all usage of the Reactions API, uncheck all above options.")
        case SettingsSection.Misc.title:
            buildFooter("You can open Trailer via the URL scheme \"pockettrailer://\" or run a search using the search query parameter, e.g.: \"pockettrailer://?search=author:john\"")
        default:
            nil
        }
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if let footer = self.tableView(tableView, viewForFooterInSection: section) {
            return footer.systemLayoutSizeFitting(CGSize(width: tableView.bounds.size.width, height: 0),
                                                  withHorizontalFittingPriority: .required,
                                                  verticalFittingPriority: .fittingSizeLevel).height + 25.0
        } else {
            return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell") as! AdvancedSettingsCell
        configureCell(cell: cell, indexPath: indexPath)
        return cell
    }

    private func configureCell(cell: AdvancedSettingsCell, indexPath: IndexPath) {
        let settingsForSection = filteredItemsForTableSection(section: indexPath.section)
        let setting = settingsForSection[indexPath.row]
        cell.titleLabel.text = setting.title
        cell.descriptionLabel.text = showHelp ? setting.description : nil
        cell.descriptionLabel.isHidden = !showHelp

        let v = setting.valueDisplayed()
        if v == "✓" {
            cell.iconView.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: nil)
            cell.iconView.isHidden = false
            cell.valueLabel.text = nil

        } else if v == " " {
            cell.iconView.image = UIImage(systemName: "circle", withConfiguration: nil)
            cell.iconView.isHidden = false
            cell.valueLabel.text = nil

        } else if v == ">" {
            cell.iconView.image = UIImage(systemName: "chevron.right.circle", withConfiguration: nil)
            cell.iconView.isHidden = false
            cell.valueLabel.text = nil

        } else {
            cell.iconView.image = nil
            cell.iconView.isHidden = true
            cell.valueLabel.text = v
        }
    }

    private func showLongSyncWarning() {
        showMessage("The next sync may take a while, because everything will need to be fully re-synced. This will be needed only once: Subsequent syncs will be fast again.", nil)
    }

    private func showOptionalReviewWarning(previousSync: Bool) {
        if !previousSync, Settings.cache.requiresReviewApis {
            for p in PullRequest.allItems(in: DataManager.main) {
                p.resetSyncState()
            }
            preferencesDirty = true
            showLongSyncWarning()
        } else {
            settingsChangedTimer.push()
        }
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        let setting = filteredItemsForTableSection(section: indexPath.section)[indexPath.row]
        let section = filteredSections[indexPath.section]
        let unFilteredItemsForSection = settings.filter { $0.section == section }

        if let originalIndex = unFilteredItemsForSection.firstIndex(where: { $0.title == setting.title }) {
            setting.optionSelected(originalIndex, section, setting)
            reload()
        }
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredItemsForTableSection(section: section).count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        filteredSections[section].title
    }

    override func numberOfSections(in _: UITableView) -> Int {
        filteredSections.count
    }

    private func filteredItemsForTableSection(section: Int) -> [Setting] {
        let sec = filteredSections[section]
        return settings.filter { $0.section == sec && $0.isRelevant(to: searchText, showingHelp: showHelp) }
    }

    private var filteredSections: [SettingsSection] {
        let matchingSettings = settings.filter { $0.isRelevant(to: searchText, showingHelp: showHelp) }
        var matchingSections = Set<SettingsSection>()
        matchingSettings.forEach { matchingSections.insert($0.section) }
        return matchingSections.sorted { $0.rawValue < $1.rawValue }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let p = segue.destination as? PickerViewController, let i = sender as? PickerViewController.Info {
            p.info = i
            p.delegate = self

        } else if let p = segue.destination as? CommentBlacklistViewController, let m = sender as? CommentBlacklistViewController.Mode {
            p.mode = m
        }
    }

    func pickerViewController(picker _: PickerViewController, didSelectIndexPath: IndexPath, info: PickerViewController.Info) {
        let sip = info.sourceIndexPath

        if sip.section == SettingsSection.Refresh.rawValue {
            if sip.row == 0 {
                Settings.backgroundRefreshPeriod = Double(didSelectIndexPath.row + 2) * 60.0
            } else if sip.row == 1 {
                Settings.newRepoCheckPeriod = Float(didSelectIndexPath.row + 2)
            }

        } else if sip.section == SettingsSection.Display.rawValue {
            if sip.row == 3 {
                Settings.assignedItemDirectHandlingPolicy = Section(assignmentPolicyMenuIndex: didSelectIndexPath.row)
                settingsChangedTimer.push()
            } else if sip.row == 4 {
                Settings.assignedItemTeamHandlingPolicy = Section(assignmentPolicyMenuIndex: didSelectIndexPath.row)
                settingsChangedTimer.push()
            } else if sip.row == 9 {
                Settings.draftHandlingPolicy = DraftHandlingPolicy(rawValue: didSelectIndexPath.row) ?? .nothing
                settingsChangedTimer.push()
            }

        } else if sip.section == SettingsSection.Sort.rawValue {
            Settings.sortMethod = SortingMethod(rawValue: didSelectIndexPath.row) ?? Settings.sortMethod
            settingsChangedTimer.push()

        } else if sip.section == SettingsSection.Watchlist.rawValue {
            if sip.row == 0 {
                Settings.displayPolicyForNewPrs = RepoDisplayPolicy(rawValue: didSelectIndexPath.row) ?? Settings.displayPolicyForNewPrs
            } else if sip.row == 1 {
                Settings.displayPolicyForNewIssues = RepoDisplayPolicy(rawValue: didSelectIndexPath.row) ?? Settings.displayPolicyForNewIssues
            }

        } else if sip.section == SettingsSection.History.rawValue {
            if sip.row == 0 {
                Settings.mergeHandlingPolicy = KeepPolicy(rawValue: didSelectIndexPath.row) ?? Settings.mergeHandlingPolicy
            } else if sip.row == 1 {
                Settings.closeHandlingPolicy = KeepPolicy(rawValue: didSelectIndexPath.row) ?? Settings.closeHandlingPolicy
            } else if sip.row == 5 {
                Settings.autoRemoveMergedItems = didSelectIndexPath.row
            } else if sip.row == 6 {
                Settings.autoRemoveClosedItems = didSelectIndexPath.row
            }

        } else if sip.section == SettingsSection.Stauses.rawValue {
            Settings.statusItemRefreshBatchSize = didSelectIndexPath.row + 1

        } else if sip.section == SettingsSection.Comments.rawValue {
            if sip.row == 2 {
                Settings.newMentionMovePolicy = Section(movePolicyMenuIndex: didSelectIndexPath.row)
            } else if sip.row == 3 {
                Settings.teamMentionMovePolicy = Section(movePolicyMenuIndex: didSelectIndexPath.row)
            } else if sip.row == 4 {
                Settings.newItemInOwnedRepoMovePolicy = Section(movePolicyMenuIndex: didSelectIndexPath.row)
            }
            settingsChangedTimer.push()

        } else if sip.section == SettingsSection.Reviews.rawValue {
            let previous = Settings.cache.requiresReviewApis
            if sip.row == 2 {
                Settings.assignedDirectReviewHandlingPolicy = Section(assignmentPolicyMenuIndex: didSelectIndexPath.row)
            } else if sip.row == 3 {
                Settings.assignedTeamReviewHandlingPolicy = Section(assignmentPolicyMenuIndex: didSelectIndexPath.row)
            }
            showOptionalReviewWarning(previousSync: previous)

        } else if sip.section == SettingsSection.Reactions.rawValue {
            let previous = Settings.cache.shouldSyncReactions
            Settings.reactionScanningBatchSize = didSelectIndexPath.row + 1
            showOptionalReviewWarning(previousSync: previous)
        }
        reload()
    }
}
