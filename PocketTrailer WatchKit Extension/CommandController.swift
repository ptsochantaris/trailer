//
//  RefreshController.swift
//  Trailer
//
//  Created by Paul Tsochantaris on 14/03/2015.
//
//

import WatchKit
import Foundation


class CommandController: WKInterfaceController {

    @IBOutlet weak var feedbackLabel: WKInterfaceLabel!

    override func awakeWithContext(context: AnyObject?) {

        super.awakeWithContext(context)

        let result = WKInterfaceController.openParentApplication(["command": context as String], reply: {
            [weak self] result, error -> Void in
            if let e = error {
                self?.feedbackLabel.setTextColor(UIColor.redColor())
                self?.feedbackLabel.setText("Error: \(e.localizedDescription)")
                self?.dismissAfterPause(2.0)
            } else {
                self?.feedbackLabel.setText(result["status"] as? String)
                if result["color"] as String == "red" {
                    self?.feedbackLabel.setTextColor(UIColor.redColor())
                    self?.dismissAfterPause(2.0)
                } else {
                    self?.feedbackLabel.setTextColor(UIColor.greenColor())
                    self?.dismissAfterPause(0.5)
                }
            }
        })
        if !result {
            self.feedbackLabel.setTextColor(UIColor.redColor())
            self.feedbackLabel.setText("Could not send request to the parent app")
            self.dismissAfterPause(2.0)
        }
    }

    func dismissAfterPause(pause: Double) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (Int64)(pause * Double(NSEC_PER_SEC))), dispatch_get_main_queue()) {
            self.dismissController()
        }
    }

    override func willActivate() {
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

}
