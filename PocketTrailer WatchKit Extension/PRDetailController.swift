//
//  PRDetailController.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit
import Foundation


class PRDetailController: WKInterfaceController {

    @IBOutlet weak var table: WKInterfaceTable!

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        let contextData = context as NSDictionary
        setTitle(contextData[TITLE_KEY] as? String)
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

}
