
import WatchKit

class SectionRow: NSObject {
    
    @IBOutlet weak var titleL: WKInterfaceLabel!
    @IBOutlet weak var countL: WKInterfaceLabel!
    @IBOutlet weak var countHolder: WKInterfaceGroup!

    func setPr(section: PullRequestSection) {

        let count = PullRequest.countRequestsInSection(section.rawValue, moc: mainObjectContext)
        titleL.setText("\(count) \(section.watchMenuName())")
        titleL.setAlpha(count==0 ? 0.4 : 1.0)

        let unreadCount = PullRequest.badgeCountInSection(section.rawValue, moc: mainObjectContext)
        countL.setText("\(unreadCount)")
        countHolder.setHidden(unreadCount==0)
    }

	func setIssue(section: PullRequestSection) {

		let count = Issue.countIssuesInSection(section.rawValue, moc: mainObjectContext)
		titleL.setText("\(count) \(section.watchMenuName())")
		titleL.setAlpha(count==0 ? 0.4 : 1.0)

		let unreadCount = Issue.badgeCountInSection(section.rawValue, moc: mainObjectContext)
		countL.setText("\(unreadCount)")
		countHolder.setHidden(unreadCount==0)
	}

}
