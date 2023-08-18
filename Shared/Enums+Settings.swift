import Foundation

extension Section {
    var shouldBadgeComments: Bool {
        switch self {
        case .all:
            return Settings.showCommentsEverywhere
        case .closed, .merged:
            return Settings.scanClosedAndMergedItems
        case .mentioned, .mine, .participated:
            return true
        case .hidden, .snoozed:
            return false
        }
    }

    @MainActor
    var shouldListReactions: Bool {
        if API.shouldSyncReactions {
            return shouldBadgeComments
        }
        return false
    }

    @MainActor
    var shouldListStatuses: Bool {
        if !Settings.showStatusItems {
            return false
        }
        switch self {
        case .all, .closed, .merged:
            return Settings.showStatusesOnAllItems
        case .mentioned, .mine, .participated:
            return true
        case .hidden, .snoozed:
            return false
        }
    }

    @MainActor
    var shouldCheckStatuses: Bool {
        if !Settings.showStatusItems {
            return false
        }
        switch self {
        case .all, .closed, .merged:
            return Settings.showStatusesOnAllItems
        case .mentioned, .mine, .participated, .snoozed:
            return true
        case .hidden:
            return Settings.hidePrsThatArentPassing // if visibility depends on statuses, check for statuses on hidden PRs because they may change
        }
    }
}
