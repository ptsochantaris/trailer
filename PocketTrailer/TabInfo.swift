import Foundation

struct TabInfo: Equatable {
    let title: String
    let image: ImageResource
    let badgeValue: String?
    let viewCriterion: GroupingCriterion?
    let isPr: Bool

    private let id = UUID()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    @MainActor
    static func items(for viewCriterion: GroupingCriterion?) -> [TabInfo] {
        let label = viewCriterion?.label
        var items = [TabInfo]()

        let settings = Settings.cache

        let prf = ListableItem.requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: viewCriterion, settings: settings)
        if try! DataManager.main.count(for: prf) > 0 {
            let prUnreadCount = PullRequest.badgeCount(in: DataManager.main, criterion: viewCriterion, settings: settings)
            let badgeValue = prUnreadCount > 0 ? "\(prUnreadCount)" : nil
            let i = TabInfo(title: label ?? "Pull Requests", image: .prsTab, badgeValue: badgeValue, viewCriterion: viewCriterion, isPr: true)
            items.append(i)
        }

        let isf = ListableItem.requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: viewCriterion, settings: settings)
        if try! DataManager.main.count(for: isf) > 0 {
            let issuesUnreadCount = Issue.badgeCount(in: DataManager.main, criterion: viewCriterion, settings: settings)
            let badgeValue = issuesUnreadCount > 0 ? "\(issuesUnreadCount)" : nil
            let i = TabInfo(title: label ?? "Issues", image: .issuesTab, badgeValue: badgeValue, viewCriterion: viewCriterion, isPr: false)
            items.append(i)
        }

        return items
    }
}
