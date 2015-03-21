
import WatchKit

class PRRow: NSObject {

    @IBOutlet weak var titleL: WKInterfaceLabel!
    @IBOutlet weak var detailsL: WKInterfaceLabel!

    @IBOutlet weak var totalCommentsL: WKInterfaceLabel!
    @IBOutlet weak var totalCommentsGroup: WKInterfaceGroup!

    @IBOutlet weak var unreadCommentsL: WKInterfaceLabel!
    @IBOutlet weak var unreadCommentsGroup: WKInterfaceGroup!

    @IBOutlet weak var counterGroup: WKInterfaceGroup!

    func setPullRequest(pr: PullRequest) {

        let smallSize = UIFont.smallSystemFontSize()-2
        let size = UIFont.systemFontSize()

        titleL.setAttributedText(pr.titleWithFont(
            UIFont.systemFontOfSize(size),
            labelFont: UIFont.systemFontOfSize(smallSize),
            titleColor: UIColor.whiteColor()))

        let a = pr.subtitleWithFont(
            UIFont.systemFontOfSize(smallSize),
            lightColor: UIColor.lightGrayColor(),
            darkColor: UIColor.grayColor())

        let p = NSMutableParagraphStyle()
        p.lineSpacing = 0
        a.addAttribute(NSParagraphStyleAttributeName, value: p, range: NSMakeRange(0, a.length))

        detailsL.setAttributedText(a)

        let totalCount = pr.totalComments?.integerValue ?? 0
        totalCommentsL.setText("\(totalCount)")
        totalCommentsGroup.setHidden(totalCount==0)

        let unreadCount = pr.unreadComments?.integerValue ?? 0
        unreadCommentsL.setText("\(unreadCount)")
        unreadCommentsGroup.setHidden(unreadCount==0)

        counterGroup.setHidden(totalCount+unreadCount==0)
    }
}
