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
        case .snoozed, .none:
            return false
        }
    }

    var shouldListReactions: Bool {
        if API.shouldSyncReactions {
            return shouldBadgeComments
        }
        return false
    }

    var shouldListStatuses: Bool {
        if !Settings.showStatusItems {
            return false
        }
        switch self {
        case .all, .closed, .merged:
            return Settings.showStatusesOnAllItems
        case .mentioned, .mine, .participated:
            return true
        case .snoozed, .none:
            return false
        }
    }

    var shouldCheckStatuses: Bool {
        if !Settings.showStatusItems {
            return false
        }
        switch self {
        case .all, .closed, .merged:
            return Settings.showStatusesOnAllItems
        case .mentioned, .mine, .participated, .snoozed:
            return true
        case .none:
            return Settings.hidePrsThatArentPassing // if visibility depends on statuses, check for statuses on hidden PRs because they may change
        }
    }
}
