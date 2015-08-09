
import WatchKit

final class SectionRow: NSObject {
    
    @IBOutlet weak var titleL: WKInterfaceLabel!
    @IBOutlet weak var countL: WKInterfaceLabel!
    @IBOutlet weak var countHolder: WKInterfaceGroup!
	@IBOutlet weak var group: WKInterfaceGroup!

	/*
    func setPr(section: PullRequestSection) {

        let count = PullRequest.countRequestsInSection(section, moc: mainObjectContext)
        titleL.setText("\(count) \(section.watchMenuName().uppercaseString)")

        let unreadCount = PullRequest.badgeCountInSection(section, moc: mainObjectContext)
        countL.setText("\(unreadCount)")
        countHolder.setHidden(unreadCount==0)
    }

	func setIssue(section: PullRequestSection) {

		let count = Issue.countIssuesInSection(section, moc: mainObjectContext)
		titleL.setText("\(count) \(section.watchMenuName().uppercaseString)")

		let unreadCount = Issue.badgeCountInSection(section, moc: mainObjectContext)
		countL.setText("\(unreadCount)")
		countHolder.setHidden(unreadCount==0)
	}
*/
}
