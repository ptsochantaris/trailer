import Foundation

extension Section {
    var shouldBadgeComments: Bool {
        switch self {
        case .all:
            return Settings.cache.showCommentsEverywhere
        case .closed, .merged:
            return Settings.cache.scanClosedAndMergedItems
        case .mentioned, .mine, .participated:
            return true
        case .hidden, .snoozed:
            return false
        }
    }

    @MainActor
    var shouldListReactions: Bool {
        if Settings.cache.shouldSyncReactions {
            return shouldBadgeComments
        }
        return false
    }

    @MainActor
    var shouldListStatuses: Bool {
        if !Settings.cache.showStatusItems {
            return false
        }
        switch self {
        case .all, .closed, .merged:
            return Settings.cache.showStatusesOnAllItems
        case .mentioned, .mine, .participated:
            return true
        case .hidden, .snoozed:
            return false
        }
    }

    @MainActor
    var shouldCheckStatuses: Bool {
        if !Settings.cache.showStatusItems {
            return false
        }
        switch self {
        case .all, .closed, .merged:
            return Settings.cache.showStatusesOnAllItems
        case .mentioned, .mine, .participated, .snoozed:
            return true
        case .hidden:
            return Settings.cache.hidePrsThatArentPassing // if visibility depends on statuses, check for statuses on hidden PRs because they may change
        }
    }
}
