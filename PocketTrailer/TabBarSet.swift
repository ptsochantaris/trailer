struct TabInfo {
    let title: String
    let image: ImageResource
    let badgeValue: String?
}

@MainActor
struct TabBarSet {
    let prItem: TabInfo?
    let issuesItem: TabInfo?
    let viewCriterion: GroupingCriterion?
    let tabItems: [TabInfo]

    init(viewCriterion: GroupingCriterion?) {
        self.viewCriterion = viewCriterion

        let label = viewCriterion?.label
        var items = [TabInfo]()

        let settings = Settings.cache

        let prf = ListableItem.requestForItems(of: PullRequest.self, withFilter: nil, sectionIndex: -1, criterion: viewCriterion, settings: settings)
        if try! DataManager.main.count(for: prf) > 0 {
            let prUnreadCount = PullRequest.badgeCount(in: DataManager.main, criterion: viewCriterion, settings: settings)
            let badgeValue = prUnreadCount > 0 ? "\(prUnreadCount)" : nil
            let i = TabInfo(title: label ?? "Pull Requests", image: .prsTab, badgeValue: badgeValue)
            items.append(i)
            prItem = i
        } else {
            prItem = nil
        }

        let isf = ListableItem.requestForItems(of: Issue.self, withFilter: nil, sectionIndex: -1, criterion: viewCriterion, settings: settings)
        if try! DataManager.main.count(for: isf) > 0 {
            let issuesUnreadCount = Issue.badgeCount(in: DataManager.main, criterion: viewCriterion, settings: settings)
            let badgeValue = issuesUnreadCount > 0 ? "\(issuesUnreadCount)" : nil
            let i = TabInfo(title: label ?? "Issues", image: .issuesTab, badgeValue: badgeValue)
            items.append(i)
            issuesItem = i
        } else {
            issuesItem = nil
        }

        tabItems = items
    }
}
