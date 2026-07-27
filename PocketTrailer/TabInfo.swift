import Foundation
import SwiftUI

struct TabInfo: Equatable {
    let title: String
    let image: ImageResource
    let badgeValue: String?
    let viewCriterion: GroupingCriterion?
    let isPr: Bool

    /// Value equality, deliberately ignoring `badgeValue` and `title` — the badge changes on every
    /// sync, and callers compare a tab they are holding against a freshly built list to find its
    /// position. `isPr` plus the criterion is already unique, since each criterion yields at most one
    /// pull request tab and one issue tab.
    ///
    /// This used to be identity equality on a per-instance `UUID`, which meant a recomputed tab never
    /// matched an existing one. That forced every consumer to share a single stored array, and that
    /// shared array was the reason the sections list could not refresh itself.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isPr == rhs.isPr && lhs.viewCriterion?.id == rhs.viewCriterion?.id
    }

    /// Every tab the app currently has, in display order.
    @MainActor
    static func allSets() -> [TabInfo] {
        var newSets = [TabInfo]()

        for groupLabel in Repo.allGroupLabels(in: DataManager.main) {
            newSets.append(contentsOf: items(for: .group(groupLabel)))
        }

        if Settings.showSeparateApiServersInMenu {
            for a in ApiServer.allApiServers(in: DataManager.main) where a.goodToGo {
                newSets.append(contentsOf: items(for: .server(a.objectID)))
            }
        } else {
            newSets.append(contentsOf: items(for: nil))
        }

        return newSets
    }

    @MainActor
    static func items(for viewCriterion: GroupingCriterion?) -> [TabInfo] {
        let label = viewCriterion?.label
        var items = [TabInfo]()

        let settings = Settings.cache

        let prf = ListableItem.requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: viewCriterion, settings: settings, moc: DataManager.main)
        if try! DataManager.main.count(for: prf) > 0 {
            let prUnreadCount = PullRequest.badgeCount(in: DataManager.main, criterion: viewCriterion, settings: settings)
            let badgeValue = prUnreadCount > 0 ? "\(prUnreadCount)" : nil
            let i = TabInfo(title: label ?? "Pull Requests", image: .prsTab, badgeValue: badgeValue, viewCriterion: viewCriterion, isPr: true)
            items.append(i)
        }

        let isf = ListableItem.requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: viewCriterion, settings: settings, moc: DataManager.main)
        if try! DataManager.main.count(for: isf) > 0 {
            let issuesUnreadCount = Issue.badgeCount(in: DataManager.main, criterion: viewCriterion, settings: settings)
            let badgeValue = issuesUnreadCount > 0 ? "\(issuesUnreadCount)" : nil
            let i = TabInfo(title: label ?? "Issues", image: .issuesTab, badgeValue: badgeValue, viewCriterion: viewCriterion, isPr: false)
            items.append(i)
        }

        return items
    }
}
