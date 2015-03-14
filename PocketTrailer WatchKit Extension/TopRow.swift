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

    func setRow(count: Int, _ suffix: String) {
        titleL.setText("\(count) \(suffix)")
        titleL.setAlpha(count==0 ? 0.4 : 1.0)
    }
}
