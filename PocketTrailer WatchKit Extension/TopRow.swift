//
//  TitleRow.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit

class TopRow: NSObject {
    
    @IBOutlet weak var titleL: WKInterfaceLabel!
    @IBOutlet weak var countL: WKInterfaceLabel!

    func setRow(section: PullRequestSection, _ suffix: String) -> String {

        let prCount = PullRequest.countRequestsInSection(section.rawValue, moc: mainObjectContext)

        let titleText = "\(prCount) \(suffix)"
        titleL.setText(titleText)
        titleL.setAlpha(prCount==0 ? 0.4 : 1.0)

        let unreadCount = PullRequest.badgeCountInSection(section.rawValue, moc: mainObjectContext)
        countL.setText("\(unreadCount)")
        countL.setHidden(unreadCount==0)

        return titleText
    }
}
