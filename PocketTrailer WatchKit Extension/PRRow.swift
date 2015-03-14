//
//  PRRow.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit

class PRRow: NSObject {

    @IBOutlet weak var titleL: WKInterfaceLabel!
    @IBOutlet weak var detailsL: WKInterfaceLabel!

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
    }
}
