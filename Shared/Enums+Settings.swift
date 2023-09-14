import Foundation

extension Section {
    func shouldBadgeComments(settings: Settings.Cache) -> Bool {
        switch self {
        case .all:
            settings.showCommentsEverywhere
        case .closed, .merged:
            settings.scanClosedAndMergedItems
        case .mentioned, .mine, .participated:
            true
        case .hidden, .snoozed:
            false
        }
    }

    func shouldListReactions(settings: Settings.Cache) -> Bool {
        if settings.shouldSyncReactions {
            return shouldBadgeComments(settings: settings)
        }
        return false
    }

    func shouldListStatuses(settings: Settings.Cache) -> Bool {
        if !settings.showStatusItems {
            return false
        }
        switch self {
        case .all, .closed, .merged:
            return settings.showStatusesOnAllItems
        case .mentioned, .mine, .participated:
            return true
        case .hidden, .snoozed:
            return false
        }
    }

    func shouldCheckStatuses(settings: Settings.Cache) -> Bool {
        if !settings.showStatusItems {
            return false
        }
        switch self {
        case .all, .closed, .merged:
            return settings.showStatusesOnAllItems
        case .mentioned, .mine, .participated, .snoozed:
            return true
        case .hidden:
            return settings.hidePrsThatArentPassing // if visibility depends on statuses, check for statuses on hidden PRs because they may change
        }
    }
}
