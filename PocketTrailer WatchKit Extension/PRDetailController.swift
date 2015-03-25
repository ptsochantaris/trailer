
import WatchKit
import Foundation

let shortDateFormatter = { () -> NSDateFormatter in
    let d = NSDateFormatter()
    d.dateStyle = NSDateFormatterStyle.ShortStyle
    d.timeStyle = NSDateFormatterStyle.ShortStyle
    return d
    }()

class PRDetailController: WKInterfaceController {

    @IBOutlet weak var table: WKInterfaceTable!

    var pullRequest: PullRequest?
	var issue: Issue?
    var refreshWhenBack = false

    override func awakeWithContext(context: AnyObject?) {
        super.awakeWithContext(context)

        let c = context as! NSDictionary
		issue = c[ISSUE_KEY] as? Issue
		pullRequest = c[PULL_REQUEST_KEY] as? PullRequest

        buildUI()
    }

    override func willActivate() {
        if refreshWhenBack {
			if let p = pullRequest {
				mainObjectContext.refreshObject(p, mergeChanges: false)
			}
			if let i = issue {
				mainObjectContext.refreshObject(i, mergeChanges: false)
			}
            buildUI()
            refreshWhenBack = false
        }
        super.willActivate()
    }

    override func didDeactivate() {
        super.didDeactivate()
    }

    @IBAction func refreshSelected() {
        refreshWhenBack = true
        presentControllerWithName("Command Controller", context: "refresh")
    }

    private func buildUI() {

		var displayedStatuses: [PRStatus]?

		if let p = pullRequest {
			self.setTitle(p.title)
			displayedStatuses = p.displayedStatuses()
		}
		if let i = issue {
			self.setTitle(i.title)
		}

        var rowTypes = [String]()

        for s in displayedStatuses ?? [] {
            rowTypes.append("StatusRow")
        }

		if let p = pullRequest {

			if !(p.body ?? "").isEmpty {
				rowTypes.append("LabelRow")
			}

			for c in p.comments.allObjects as! [PRComment] {
				rowTypes.append("CommentRow")
			}

		} else if let i = issue {

			if !(i.body ?? "").isEmpty {
				rowTypes.append("LabelRow")
			}

			for c in i.comments.allObjects as! [PRComment] {
				rowTypes.append("CommentRow")
			}
		}

        table.setRowTypes(rowTypes)

        var index = 0

        for s in displayedStatuses ?? [] {
            let controller = table.rowControllerAtIndex(index++) as! StatusRow
            controller.labelL.setText(s.displayText())
            let color = s.colorForDarkDisplay()
            controller.labelL.setTextColor(color)
            controller.margin.setBackgroundColor(color)
        }

		if let p = pullRequest {
			if !(p.body ?? "").isEmpty {
				(table.rowControllerAtIndex(index++) as! LabelRow).labelL.setText(p.body)
			}
			for c in p.comments.allObjects as! [PRComment] {
				let controller = table.rowControllerAtIndex(index++) as! CommentRow
				controller.usernameL.setText((c.userName ?? "(unknown)") + " " + shortDateFormatter.stringFromDate(c.createdAt ?? NSDate()))
				controller.commentL.setText(c.body)
			}
		} else if let i = issue {
			if !(i.body ?? "").isEmpty {
				(table.rowControllerAtIndex(index++) as! LabelRow).labelL.setText(i.body)
			}
			for c in i.comments.allObjects as! [PRComment] {
				let controller = table.rowControllerAtIndex(index++) as! CommentRow
				controller.usernameL.setText((c.userName ?? "(unknown)") + " " + shortDateFormatter.stringFromDate(c.createdAt ?? NSDate()))
				controller.commentL.setText(c.body)
			}
		}
    }
}
