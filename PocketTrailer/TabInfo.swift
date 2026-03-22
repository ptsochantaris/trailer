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
}
