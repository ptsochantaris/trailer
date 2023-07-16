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
        var valueDisplayed: () -> String?

        func isRelevant(to searchText: String?, showingHelp: Bool) -> Bool {
            if let s = searchText, !s.isEmpty {
                return title.localizedCaseInsensitiveContains(s) || (showingHelp && description.localizedCaseInsensitiveContains(s))
            } else {
                return true
            }
        }
    }

    private let settings = [
        Setting(section: .Refresh,
                title: "Background refresh interval (minimum)",
                description: Settings.backgroundRefreshPeriodHelp,
                valueDisplayed: { String(format: "%.0f minutes", Settings.backgroundRefreshPeriod / 60.0) }),
        Setting(section: .Refresh,
                title: "Watchlist & team list refresh interval",
                description: Settings.newRepoCheckPeriodHelp,
                valueDisplayed: { String(format: "%.0f hours", Settings.newRepoCheckPeriod) }),

        Setting(section: .Display,
                title: "Show item labels",
                description: Settings.showLabelsHelp,
                valueDisplayed: { Settings.showLabels ? "✓" : " " }),
        Setting(section: .Display,
                title: "Display item creation times instead of update times",
                description: Settings.showCreatedInsteadOfUpdatedHelp,
                valueDisplayed: { Settings.showCreatedInsteadOfUpdated ? "✓" : " " }),
        Setting(section: .Display,
                title: "Display relative times and dates",
                description: Settings.showRelativeDatesHelp,
                valueDisplayed: { Settings.showRelativeDates ? "✓" : " " }),
        Setting(section: .Display,
                title: "Assigned items",
                description: "How to handle items that have been detected as assigned to you.",
                valueDisplayed: { AssignmentPolicy(rawValue: Settings.assignedPrHandlingPolicy)?.name }),
        Setting(section: .Display,
                title: "Display repository names",
                description: Settings.showReposInNameHelp,
                valueDisplayed: { Settings.showReposInName ? "✓" : " " }),
        Setting(section: .Display,
                title: "…including base and head branches",
                description: Settings.showBaseAndHeadBranchesHelp,
                valueDisplayed: { Settings.showBaseAndHeadBranches ? "✓" : " " }),
        Setting(section: .Display,
                title: "Separate API servers into their own groups",
                description: Settings.showSeparateApiServersInMenuHelp,
                valueDisplayed: { Settings.showSeparateApiServersInMenu ? "✓" : " " }),
        Setting(section: .Display,
                title: "Highlight PRs with new commits",
                description: Settings.markPrsAsUnreadOnNewCommitsHelp,
                valueDisplayed: { Settings.markPrsAsUnreadOnNewCommits ? "✓" : " " }),
        Setting(section: .Display,
                title: "Display milestones",
                description: Settings.showMilestonesHelp,
                valueDisplayed: { Settings.showMilestones ? "✓" : " " }),
        Setting(section: .Display,
                title: "Prefix PR/Issue numbers in item titles",
                description: Settings.displayNumbersForItemsHelp,
                valueDisplayed: { Settings.displayNumbersForItems ? "✓" : " " }),
        Setting(section: .Display,
                title: "Draft PRs",
                description: Settings.draftHandlingPolicyHelp,
                valueDisplayed: { DraftHandlingPolicy.labels[Settings.draftHandlingPolicy] }),
        Setting(section: .Display,
                title: "Mark non-mergeable PRs (v4 API only)",
                description: Settings.markUnmergeablePrsHelp,
                valueDisplayed: { Settings.markUnmergeablePrs ? "✓" : " " }),
        Setting(section: .Display,
                title: "Show PR line counts (v4 API only)",
                description: Settings.showPrLinesHelp,
                valueDisplayed: { Settings.showPrLines ? "✓" : " " }),

        Setting(section: .Filtering,
                title: "Include item titles",
                description: Settings.includeTitlesInFilterHelp,
                valueDisplayed: { Settings.includeTitlesInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Include repository names",
                description: Settings.includeReposInFilterHelp,
                valueDisplayed: { Settings.includeReposInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Include labels",
                description: Settings.includeLabelsInFilterHelp,
                valueDisplayed: { Settings.includeLabelsInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Include statuses",
                description: Settings.includeStatusesInFilterHelp,
                valueDisplayed: { Settings.includeStatusesInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Include servers",
                description: Settings.includeServersInFilterHelp,
                valueDisplayed: { Settings.includeServersInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Include usernames",
                description: Settings.includeUsersInFilterHelp,
                valueDisplayed: { Settings.includeUsersInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Include PR or issue numbers",
                description: Settings.includeNumbersInFilterHelp,
                valueDisplayed: { Settings.includeNumbersInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Include milestones",
                description: Settings.includeMilestonesInFilterHelp,
                valueDisplayed: { Settings.includeMilestonesInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Include assignee names",
                description: Settings.includeAssigneeInFilterHelp,
                valueDisplayed: { Settings.includeAssigneeNamesInFilter ? "✓" : " " }),
        Setting(section: .Filtering,
                title: "Hide items created by these usernames…",
                description: Settings.itemAuthorBlacklistHelp,
                valueDisplayed: { ">" }),
        Setting(section: .Filtering,
                title: "Hide items that contain these labels…",
                description: Settings.itemAuthorBlacklistHelp,
                valueDisplayed: { ">" }),

        Setting(section: .AppleWatch,
                title: "Prefer issues instead of PRs in Apple Watch complications",
                description: Settings.preferIssuesInWatchHelp,
                valueDisplayed: { Settings.preferIssuesInWatch ? "✓" : " " }),
        Setting(section: .AppleWatch,
                title: "Hide descriptions in Apple Watch detail views",
                description: Settings.hideDescriptionInWatchDetailHelp,
                valueDisplayed: { Settings.hideDescriptionInWatchDetail ? "✓" : " " }),

        Setting(section: .Comments,
                title: "Badge & send alerts for the 'all' section too",
                description: Settings.showCommentsEverywhereHelp,
                valueDisplayed: { Settings.showCommentsEverywhere ? "✓" : " " }),
        Setting(section: .Comments,
                title: "Only display items with unread badges",
                description: Settings.hideUncommentedItemsHelp,
                valueDisplayed: { Settings.hideUncommentedItems ? "✓" : " " }),
        Setting(section: .Comments,
                title: "Move items mentioning me to…",
                description: Settings.newMentionMovePolicyHelp,
                valueDisplayed: { Section(rawValue: Settings.newMentionMovePolicy)!.movePolicyName }),
        Setting(section: .Comments,
                title: "Move items mentioning my teams to…",
                description: Settings.teamMentionMovePolicyHelp,
                valueDisplayed: { Section(rawValue: Settings.teamMentionMovePolicy)!.movePolicyName }),
        Setting(section: .Comments,
                title: "Move items created in my repos to…",
                description: Settings.newItemInOwnedRepoMovePolicyHelp,
                valueDisplayed: { Section(rawValue: Settings.newItemInOwnedRepoMovePolicy)!.movePolicyName }),
        Setting(section: .Comments,
                title: "Open items at first unread comment",
                description: Settings.openPrAtFirstUnreadCommentHelp,
                valueDisplayed: { Settings.openPrAtFirstUnreadComment ? "✓" : " " }),
        Setting(section: .Comments,
                title: "Block comment notifications from usernames…",
                description: "A list of usernames whose comments you don't want to receive notifications for.",
                valueDisplayed: { ">" }),
        Setting(section: .Comments,
                title: "Disable all comment notifications",
                description: Settings.disableAllCommentNotificationsHelp,
                valueDisplayed: { Settings.disableAllCommentNotifications ? "✓" : " " }),
        Setting(section: .Comments,
                title: "Mark any comments before my own as read",
                description: Settings.assumeReadItemIfUserHasNewerCommentsHelp,
                valueDisplayed: { Settings.assumeReadItemIfUserHasNewerComments ? "✓" : " " }),

        Setting(section: .Watchlist,
                title: "PR visibility for new repos",
                description: Settings.displayPolicyForNewPrsHelp,
                valueDisplayed: { RepoDisplayPolicy(rawValue: Settings.displayPolicyForNewPrs)?.name }),
        Setting(section: .Watchlist,
                title: "Issue visibility for new repos",
                description: Settings.displayPolicyForNewIssuesHelp,
                valueDisplayed: { RepoDisplayPolicy(rawValue: Settings.displayPolicyForNewIssues)?.name }),

        Setting(section: .Reviews,
                title: "Show reviews for PRs",
                description: Settings.displayReviewsOnItemsHelp,
                valueDisplayed: { Settings.displayReviewsOnItems ? "✓" : " " }),
        Setting(section: .Reviews,
                title: "Show teams asked to review",
                description: Settings.showRequestedTeamReviewsHelp,
                valueDisplayed: { Settings.showRequestedTeamReviews ? "✓" : " " }),
        Setting(section: .Reviews,
                title: "When a PR is assigned to me for review",
                description: Settings.assignedReviewHandlingPolicyHelp,
                valueDisplayed: { Section.movePolicyNames[Settings.assignedReviewHandlingPolicy] }),
        Setting(section: .Reviews,
                title: "Notify on change requests",
                description: Settings.notifyOnReviewChangeRequestsHelp,
                valueDisplayed: { Settings.notifyOnReviewChangeRequests ? "✓" : " " }),
        Setting(section: .Reviews,
                title: "…for all change requests",
                description: Settings.notifyOnAllReviewChangeRequestsHelp,
                valueDisplayed: { Settings.notifyOnAllReviewChangeRequests ? "✓" : " " }),
        Setting(section: .Reviews,
                title: "Notify on approvals",
                description: Settings.notifyOnReviewAcceptancesHelp,
                valueDisplayed: { Settings.notifyOnReviewAcceptances ? "✓" : " " }),
        Setting(section: .Reviews,
                title: "…for all approvals",
                description: Settings.notifyOnAllReviewAcceptancesHelp,
                valueDisplayed: { Settings.notifyOnAllReviewAcceptances ? "✓" : " " }),
        Setting(section: .Reviews,
                title: "Notify on dismissals",
                description: Settings.notifyOnReviewDismissalsHelp,
                valueDisplayed: { Settings.notifyOnReviewDismissals ? "✓" : " " }),
        Setting(section: .Reviews,
                title: "…for all dismissals",
                description: Settings.notifyOnAllReviewDismissalsHelp,
                valueDisplayed: { Settings.notifyOnAllReviewDismissals ? "✓" : " " }),
        Setting(section: .Reviews,
                title: "Notify on assignments",
                description: Settings.notifyOnReviewAssignmentsHelp,
                valueDisplayed: { Settings.notifyOnReviewAssignments ? "✓" : " " }),

        Setting(section: .Reactions,
                title: "Count / notify on item reactions",
                description: Settings.notifyOnItemReactionsHelp,
                valueDisplayed: { Settings.notifyOnItemReactions ? "✓" : " " }),
        Setting(section: .Reactions,
                title: "Count / notify on comment reactions",
                description: Settings.notifyOnCommentReactionsHelp,
                valueDisplayed: { Settings.notifyOnCommentReactions ? "✓" : " " }),
        Setting(section: .Reactions,
                title: "Scan for reactions",
                description: Settings.reactionScanningBatchSizeHelp,
                valueDisplayed: { "\(Settings.reactionScanningBatchSize) items per refresh" }),

        Setting(section: .Stauses,
                title: "Show statuses",
                description: Settings.showStatusItemsHelp,
                valueDisplayed: { Settings.showStatusItems ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "…for all PRs",
                description: Settings.showStatusesOnAllItemsHelp,
                valueDisplayed: { Settings.showStatusesOnAllItems ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "Scan for statuses",
                description: Settings.statusItemRefreshBatchSizeHelp,
                valueDisplayed: { "\(Settings.statusItemRefreshBatchSize) items per refresh" }),
        Setting(section: .Stauses,
                title: "Notify status changes for my & participated PRs",
                description: Settings.notifyOnStatusUpdatesHelp,
                valueDisplayed: { Settings.notifyOnStatusUpdates ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "…in the 'All' section too",
                description: Settings.notifyOnStatusUpdatesForAllPrsHelp,
                valueDisplayed: { Settings.notifyOnStatusUpdatesForAllPrs ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "Hide PRs whose status items are not all green",
                description: Settings.hidePrsThatArentPassingHelp,
                valueDisplayed: { Settings.hidePrsThatArentPassing ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "…only in the 'All' section",
                description: Settings.hidePrsThatDontPassOnlyInAllHelp,
                valueDisplayed: { Settings.hidePrsThatDontPassOnlyInAll ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "Show neutral statuses",
                description: Settings.showStatusesGrayHelp,
                valueDisplayed: { Settings.showStatusesGray ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "Show green statuses",
                description: Settings.showStatusesGreenHelp,
                valueDisplayed: { Settings.showStatusesGreen ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "Show yellow statuses",
                description: Settings.showStatusesYellowHelp,
                valueDisplayed: { Settings.showStatusesYellow ? "✓" : " " }),
        Setting(section: .Stauses,
                title: "Show red statuses",
                description: Settings.showStatusesRedHelp,
                valueDisplayed: { Settings.showStatusesRed ? "✓" : " " }),

        Setting(section: .History,
                title: "When something is merged",
                description: Settings.mergeHandlingPolicyHelp,
                valueDisplayed: { HandlingPolicy(rawValue: Settings.mergeHandlingPolicy)?.name }),
        Setting(section: .History,
                title: "When something is closed",
                description: Settings.closeHandlingPolicyHelp,
                valueDisplayed: { HandlingPolicy(rawValue: Settings.closeHandlingPolicy)?.name }),
        Setting(section: .History,
                title: "Don't keep PRs merged by me",
                description: Settings.dontKeepPrsMergedByMeHelp,
                valueDisplayed: { Settings.dontKeepPrsMergedByMe ? "✓" : " " }),
        Setting(section: .History,
                title: "Clear notifications of removed items",
                description: Settings.removeNotificationsWhenItemIsRemovedHelp,
                valueDisplayed: { Settings.removeNotificationsWhenItemIsRemoved ? "✓" : " " }),
        Setting(section: .History,
                title: "Highlight comments on closed or merged items",
                description: Settings.scanClosedAndMergedItemsHelp,
                valueDisplayed: { Settings.scanClosedAndMergedItems ? "✓" : " " }),

        Setting(section: .Confirm,
                title: "Removing all merged items",
                description: Settings.dontAskBeforeWipingMergedHelp,
                valueDisplayed: { Settings.dontAskBeforeWipingMerged ? "✓" : " " }),
        Setting(section: .Confirm,
                title: "Removing all closed items",
                description: Settings.dontAskBeforeWipingClosedHelp,
                valueDisplayed: { Settings.dontAskBeforeWipingClosed ? "✓" : " " }),

        Setting(section: .Sort,
                title: "Direction",
                description: Settings.sortDescendingHelp,
                valueDisplayed: { Settings.sortDescending ? "Reverse" : "Normal" }),
        Setting(section: .Sort,
                title: "Criterion",
                description: Settings.sortMethodHelp,
                valueDisplayed: {
                    if let m = SortingMethod(rawValue: Settings.sortMethod) {
                        return Settings.sortDescending ? m.reverseTitle : m.normalTitle
                    } else {
                        return nil
                    }
                }),
        Setting(section: .Sort,
                title: "Bunch by repository",
                description: Settings.groupByRepoHelp,
                valueDisplayed: { Settings.groupByRepo ? "✓" : " " }),

        Setting(section: .Misc,
                title: "Log activity to console",
                description: Settings.logActivityToConsoleHelp,
                valueDisplayed: { Settings.logActivityToConsole ? "✓" : " " }),
        Setting(section: .Misc,
                title: "Log API calls to console",
                description: Settings.dumpAPIResponsesInConsoleHelp,
                valueDisplayed: { Settings.dumpAPIResponsesInConsole ? "✓" : " " })
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
            Task {
                await DataManager.postProcessAllItems(in: DataManager.main)
            }
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
        showHelp = !showHelp
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
            return buildFooter("You can use title: server: label: repo: user: number: milestone: assignee: and status: to filter specific properties, e.g. \"label:bug,suggestion\". Prefix with '!' to exclude some terms. You can also use \"state:\" with unread/open/closed/merged/snoozed/draft/conflict as an argument, e.g. \"state:unread,draft\"")
        case SettingsSection.Reviews.title:
            return buildFooter("To disable usage of the Reviews API, uncheck all options above and set the moving option to \"Don't Move It\".")
        case SettingsSection.Reactions.title:
            return buildFooter("To completely disable all usage of the Reactions API, uncheck all above options.")
        case SettingsSection.Misc.title:
            return buildFooter("You can open Trailer via the URL scheme \"pockettrailer://\" or run a search using the search query parameter, e.g.: \"pockettrailer://?search=author:john\"")
        default:
            return nil
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
        if !previousSync, API.shouldSyncReviews || API.shouldSyncReviewAssignments {
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

        var originalIndex = 0
        for x in unFilteredItemsForSection {
            if x.title == setting.title {
                break
            }
            originalIndex += 1
        }

        if section == SettingsSection.Refresh {
            var values = [String]()
            var count = 0
            var previousIndex: Int?
            switch originalIndex {
            case 0:
                // minutes
                let period = Int(Settings.backgroundRefreshPeriod / 60)
                for f in 2 ..< 1000 {
                    if f == period { previousIndex = count }
                    values.append("\(f) minutes")
                    count += 1
                }
            case 1:
                // hours
                let period = Int(Settings.newRepoCheckPeriod)
                for f in 2 ..< 100 {
                    if f == period { previousIndex = count }
                    values.append("\(f) hours")
                    count += 1
                }
            default: break
            }
            let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: previousIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
            performSegue(withIdentifier: "showPicker", sender: v)

        } else if section == SettingsSection.Display {
            switch originalIndex {
            case 0:
                let wasOff = !Settings.showLabels
                Settings.showLabels = !Settings.showLabels
                if wasOff, Settings.showLabels {
                    ApiServer.resetSyncOfEverything()
                    preferencesDirty = true
                    showLongSyncWarning()
                }
                settingsChangedTimer.push()
            case 1:
                Settings.showCreatedInsteadOfUpdated = !Settings.showCreatedInsteadOfUpdated
                settingsChangedTimer.push()
            case 2:
                Settings.showRelativeDates = !Settings.showRelativeDates
                settingsChangedTimer.push()
            case 3:
                let v = PickerViewController.Info(title: setting.title, values: AssignmentPolicy.labels, selectedIndex: Settings.assignedPrHandlingPolicy, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)
            case 4:
                Settings.showReposInName = !Settings.showReposInName
                settingsChangedTimer.push()
            case 5:
                Settings.showBaseAndHeadBranches = !Settings.showBaseAndHeadBranches
                settingsChangedTimer.push()
            case 6:
                Settings.showSeparateApiServersInMenu = !Settings.showSeparateApiServersInMenu
                Task { @MainActor in
                    popupManager.masterController.updateStatus(becauseOfChanges: true)
                }
                settingsChangedTimer.push()
            case 7:
                Settings.markPrsAsUnreadOnNewCommits = !Settings.markPrsAsUnreadOnNewCommits
                settingsChangedTimer.push()
            case 8:
                Settings.showMilestones = !Settings.showMilestones
                settingsChangedTimer.push()
            case 9:
                Settings.displayNumbersForItems = !Settings.displayNumbersForItems
                settingsChangedTimer.push()
            case 10:
                let v = PickerViewController.Info(title: setting.title, values: DraftHandlingPolicy.labels, selectedIndex: Settings.draftHandlingPolicy, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)
            case 11:
                Settings.markUnmergeablePrs = !Settings.markUnmergeablePrs
                settingsChangedTimer.push()
            case 12:
                Settings.showPrLines = !Settings.showPrLines
                settingsChangedTimer.push()
            default: break
            }

        } else if section == SettingsSection.Filtering {
            switch originalIndex {
            case 0:
                Settings.includeTitlesInFilter = !Settings.includeTitlesInFilter
            case 1:
                Settings.includeReposInFilter = !Settings.includeReposInFilter
            case 2:
                Settings.includeLabelsInFilter = !Settings.includeLabelsInFilter
            case 3:
                Settings.includeStatusesInFilter = !Settings.includeStatusesInFilter
            case 4:
                Settings.includeServersInFilter = !Settings.includeServersInFilter
            case 5:
                Settings.includeUsersInFilter = !Settings.includeUsersInFilter
            case 6:
                Settings.includeNumbersInFilter = !Settings.includeNumbersInFilter
            case 7:
                Settings.includeMilestonesInFilter = !Settings.includeMilestonesInFilter
            case 8:
                Settings.includeAssigneeNamesInFilter = !Settings.includeAssigneeNamesInFilter
            case 9:
                performSegue(withIdentifier: "showBlacklist", sender: CommentBlacklistViewController.Mode.itemAuthors)
            case 10:
                performSegue(withIdentifier: "showBlacklist", sender: CommentBlacklistViewController.Mode.labels)
            default: break
            }
            settingsChangedTimer.push()

        } else if section == SettingsSection.AppleWatch {
            switch originalIndex {
            case 0:
                Settings.preferIssuesInWatch = !Settings.preferIssuesInWatch
                settingsChangedTimer.push()
            case 1:
                Settings.hideDescriptionInWatchDetail = !Settings.hideDescriptionInWatchDetail
            default: break
            }

        } else if section == SettingsSection.Comments {
            switch originalIndex {
            case 0:
                Settings.showCommentsEverywhere = !Settings.showCommentsEverywhere
                settingsChangedTimer.push()
            case 1:
                Settings.hideUncommentedItems = !Settings.hideUncommentedItems
                settingsChangedTimer.push()
            case 2, 3, 4:
                let previousIndex = originalIndex == 2 ? Settings.newMentionMovePolicy :
                    originalIndex == 3 ? Settings.teamMentionMovePolicy :
                    Settings.newItemInOwnedRepoMovePolicy
                let v = PickerViewController.Info(title: setting.title, values: Section.movePolicyNames, selectedIndex: previousIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)
            case 5:
                Settings.openPrAtFirstUnreadComment = !Settings.openPrAtFirstUnreadComment
            case 6:
                performSegue(withIdentifier: "showBlacklist", sender: CommentBlacklistViewController.Mode.commentAuthors)
            case 7:
                Settings.disableAllCommentNotifications = !Settings.disableAllCommentNotifications
            case 8:
                Settings.assumeReadItemIfUserHasNewerComments = !Settings.assumeReadItemIfUserHasNewerComments
            default: break
            }

        } else if section == SettingsSection.Reviews {
            switch originalIndex {
            case 0:
                let previousShouldSync = (API.shouldSyncReviews || API.shouldSyncReviewAssignments)
                Settings.displayReviewsOnItems = !Settings.displayReviewsOnItems
                showOptionalReviewWarning(previousSync: previousShouldSync)

            case 1:
                let previousShouldSync = (API.shouldSyncReviews || API.shouldSyncReviewAssignments)
                Settings.showRequestedTeamReviews = !Settings.showRequestedTeamReviews
                showOptionalReviewWarning(previousSync: previousShouldSync)

            case 2:
                let v = PickerViewController.Info(title: setting.title, values: Section.movePolicyNames, selectedIndex: Settings.assignedReviewHandlingPolicy, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)

            case 3:
                let previousShouldSync = (API.shouldSyncReviews || API.shouldSyncReviewAssignments)
                Settings.notifyOnReviewChangeRequests = !Settings.notifyOnReviewChangeRequests
                showOptionalReviewWarning(previousSync: previousShouldSync)

            case 4:
                Settings.notifyOnAllReviewChangeRequests = !Settings.notifyOnAllReviewChangeRequests

            case 5:
                let previousShouldSync = (API.shouldSyncReviews || API.shouldSyncReviewAssignments)
                Settings.notifyOnReviewAcceptances = !Settings.notifyOnReviewAcceptances
                showOptionalReviewWarning(previousSync: previousShouldSync)

            case 6:
                Settings.notifyOnAllReviewAcceptances = !Settings.notifyOnAllReviewAcceptances

            case 7:
                let previousShouldSync = (API.shouldSyncReviews || API.shouldSyncReviewAssignments)
                Settings.notifyOnReviewDismissals = !Settings.notifyOnReviewDismissals
                showOptionalReviewWarning(previousSync: previousShouldSync)

            case 8:
                Settings.notifyOnAllReviewDismissals = !Settings.notifyOnAllReviewDismissals

            case 9:
                let previousShouldSync = (API.shouldSyncReviews || API.shouldSyncReviewAssignments)
                Settings.notifyOnReviewAssignments = !Settings.notifyOnReviewAssignments
                showOptionalReviewWarning(previousSync: previousShouldSync)

            default: break
            }

            if !Settings.notifyOnReviewChangeRequests {
                Settings.notifyOnAllReviewChangeRequests = false
            }
            if !Settings.notifyOnReviewDismissals {
                Settings.notifyOnAllReviewDismissals = false
            }
            if !Settings.notifyOnReviewAcceptances {
                Settings.notifyOnAllReviewAcceptances = false
            }

        } else if section == SettingsSection.Reactions {
            switch originalIndex {
            case 0:
                Settings.notifyOnItemReactions = !Settings.notifyOnItemReactions
                settingsChangedTimer.push()

            case 1:
                Settings.notifyOnCommentReactions = !Settings.notifyOnCommentReactions
                settingsChangedTimer.push()

            case 2:
                var values = [String]()
                values.append("1 item per refresh")
                for f in 2 ..< 999 {
                    values.append("\(f) items per refresh")
                }
                let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: Settings.reactionScanningBatchSize - 1, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)

            default: break
            }

        } else if section == SettingsSection.Watchlist {
            var previousIndex: Int?
            switch originalIndex {
            case 0:
                previousIndex = Settings.displayPolicyForNewPrs
            case 1:
                previousIndex = Settings.displayPolicyForNewIssues
            default: break
            }
            let v = PickerViewController.Info(title: setting.title, values: RepoDisplayPolicy.labels, selectedIndex: previousIndex, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
            performSegue(withIdentifier: "showPicker", sender: v)

        } else if section == SettingsSection.Stauses {
            switch originalIndex {
            case 0:
                Settings.showStatusItems = !Settings.showStatusItems
                settingsChangedTimer.push()
                if Settings.showStatusItems {
                    preferencesDirty = true
                }
            case 1:
                Settings.showStatusesOnAllItems = !Settings.showStatusesOnAllItems
                settingsChangedTimer.push()
                if Settings.showStatusesOnAllItems {
                    preferencesDirty = true
                }
            case 2:
                var values = [String]()
                values.append("1 item per refresh")
                for f in 2 ..< 999 {
                    values.append("\(f) items per refresh")
                }
                let v = PickerViewController.Info(title: setting.title, values: values, selectedIndex: Settings.statusItemRefreshBatchSize - 1, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)
            case 3:
                Settings.notifyOnStatusUpdates = !Settings.notifyOnStatusUpdates
            case 4:
                Settings.notifyOnStatusUpdatesForAllPrs = !Settings.notifyOnStatusUpdatesForAllPrs
            case 5:
                Settings.hidePrsThatArentPassing = !Settings.hidePrsThatArentPassing
                settingsChangedTimer.push()
            case 6:
                Settings.hidePrsThatDontPassOnlyInAll = !Settings.hidePrsThatDontPassOnlyInAll
                settingsChangedTimer.push()
            case 7:
                Settings.showStatusesGray = !Settings.showStatusesGray
                settingsChangedTimer.push()
            case 8:
                Settings.showStatusesGreen = !Settings.showStatusesGreen
                settingsChangedTimer.push()
            case 9:
                Settings.showStatusesYellow = !Settings.showStatusesYellow
                settingsChangedTimer.push()
            case 10:
                Settings.showStatusesRed = !Settings.showStatusesRed
                settingsChangedTimer.push()
            default:
                break
            }

        } else if section == SettingsSection.History {
            switch originalIndex {
            case 0:
                let v = PickerViewController.Info(title: setting.title, values: HandlingPolicy.labels, selectedIndex: Settings.mergeHandlingPolicy, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)
            case 1:
                let v = PickerViewController.Info(title: setting.title, values: HandlingPolicy.labels, selectedIndex: Settings.closeHandlingPolicy, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)
            case 2:
                Settings.dontKeepPrsMergedByMe = !Settings.dontKeepPrsMergedByMe
            case 3:
                Settings.removeNotificationsWhenItemIsRemoved = !Settings.removeNotificationsWhenItemIsRemoved
            case 4:
                Settings.scanClosedAndMergedItems = !Settings.scanClosedAndMergedItems
            default: break
            }

        } else if section == SettingsSection.Confirm {
            switch originalIndex {
            case 0:
                Settings.dontAskBeforeWipingMerged = !Settings.dontAskBeforeWipingMerged
            case 1:
                Settings.dontAskBeforeWipingClosed = !Settings.dontAskBeforeWipingClosed
            default: break
            }
        } else if section == SettingsSection.Sort {
            switch originalIndex {
            case 0:
                Settings.sortDescending = !Settings.sortDescending
                settingsChangedTimer.push()
            case 1:
                let valuesToPush = Settings.sortDescending ? SortingMethod.reverseTitles : SortingMethod.normalTitles
                let v = PickerViewController.Info(title: setting.title, values: valuesToPush, selectedIndex: Settings.sortMethod, sourceIndexPath: IndexPath(row: originalIndex, section: section.rawValue))
                performSegue(withIdentifier: "showPicker", sender: v)
            case 2:
                Settings.groupByRepo = !Settings.groupByRepo
                settingsChangedTimer.push()
            default: break
            }

        } else if section == SettingsSection.Misc {
            switch originalIndex {
            case 0:
                Settings.logActivityToConsole = !Settings.logActivityToConsole
                if Settings.logActivityToConsole {
                    showMessage("Warning", "Logging is a feature meant to aid error reporting, having it constantly enabled will cause this app to be less responsive and use more battery")
                }
            case 1:
                Settings.dumpAPIResponsesInConsole = !Settings.dumpAPIResponsesInConsole
                if Settings.dumpAPIResponsesInConsole {
                    showMessage("Warning", "Logging is a feature meant to aid error reporting, having it constantly enabled will cause this app to be less responsive and use more battery")
                }
            default: break
            }
        }
        reload()
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
                Settings.assignedPrHandlingPolicy = didSelectIndexPath.row
                settingsChangedTimer.push()
            } else if sip.row == 9 {
                Settings.draftHandlingPolicy = didSelectIndexPath.row
                settingsChangedTimer.push()
            }

        } else if sip.section == SettingsSection.Sort.rawValue {
            Settings.sortMethod = didSelectIndexPath.row
            settingsChangedTimer.push()

        } else if sip.section == SettingsSection.Watchlist.rawValue {
            if sip.row == 0 {
                Settings.displayPolicyForNewPrs = didSelectIndexPath.row
            } else if sip.row == 1 {
                Settings.displayPolicyForNewIssues = didSelectIndexPath.row
            }

        } else if sip.section == SettingsSection.History.rawValue {
            if sip.row == 0 {
                Settings.mergeHandlingPolicy = didSelectIndexPath.row
            } else if sip.row == 1 {
                Settings.closeHandlingPolicy = didSelectIndexPath.row
            }

        } else if sip.section == SettingsSection.Stauses.rawValue {
            Settings.statusItemRefreshBatchSize = didSelectIndexPath.row + 1

        } else if sip.section == SettingsSection.Comments.rawValue {
            if sip.row == 2 {
                Settings.newMentionMovePolicy = didSelectIndexPath.row
            } else if sip.row == 3 {
                Settings.teamMentionMovePolicy = didSelectIndexPath.row
            } else if sip.row == 4 {
                Settings.newItemInOwnedRepoMovePolicy = didSelectIndexPath.row
            }
            settingsChangedTimer.push()

        } else if sip.section == SettingsSection.Reviews.rawValue {
            let previous = (API.shouldSyncReviews || API.shouldSyncReviewAssignments)
            Settings.assignedReviewHandlingPolicy = didSelectIndexPath.row
            showOptionalReviewWarning(previousSync: previous)

        } else if sip.section == SettingsSection.Reactions.rawValue {
            let previous = API.shouldSyncReactions
            Settings.reactionScanningBatchSize = didSelectIndexPath.row + 1
            showOptionalReviewWarning(previousSync: previous)
        }
        reload()
    }
}
