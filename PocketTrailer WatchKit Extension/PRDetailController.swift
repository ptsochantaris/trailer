
import WatchKit
import Foundation

let shortDateFormatter = { () -> NSDateFormatter in
	let d = NSDateFormatter()
	d.dateStyle = NSDateFormatterStyle.ShortStyle
	d.timeStyle = NSDateFormatterStyle.ShortStyle
	return d
	}()

final class PRDetailController: WKInterfaceController {

	@IBOutlet weak var table: WKInterfaceTable!

	var pullRequest: PullRequest?
	var issue: Issue?

	override func awakeWithContext(context: AnyObject?) {
		super.awakeWithContext(context)

		let c = context as! [NSObject : AnyObject]
		issue = c[ISSUE_KEY] as? Issue
		pullRequest = c[PULL_REQUEST_KEY] as? PullRequest
	}

	override func willActivate() {
		if let p = pullRequest {
			mainObjectContext.refreshObject(p, mergeChanges: false)
		}
		if let i = issue {
			mainObjectContext.refreshObject(i, mergeChanges: false)
		}
		buildUI()
		super.willActivate()
	}

	@IBAction func refreshSelected() {
		presentControllerWithName("Command Controller", context: ["command": "refresh"])
	}

	@IBAction func markAllReadSelected() {
		if let i = issue {
			presentControllerWithName("Command Controller", context: ["command": "markIssueRead", "id": i.objectID.URIRepresentation().absoluteString!])
		} else if let p = pullRequest {
			presentControllerWithName("Command Controller", context: ["command": "markPrRead", "id": p.objectID.URIRepresentation().absoluteString!])
		}
	}

	@IBAction func openOnDeviceSelected() {
		if let i = issue?.objectID.URIRepresentation().absoluteString {
			presentControllerWithName("Command Controller", context: ["command": "openissue", "id": i])
		} else if let p = pullRequest?.objectID.URIRepresentation().absoluteString {
			presentControllerWithName("Command Controller", context: ["command": "openpr", "id": p])
		}
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		let r: AnyObject? = table.rowControllerAtIndex(rowIndex)
		if let c = r as? CommentRow, commentId = c.commentId
		{
			presentControllerWithName("Command Controller", context: ["command": "opencomment", "id": commentId])
		}
	}

	private func buildUI() {

		var displayedStatuses: [PRStatus]?

		if let p = pullRequest {
			setTitle(p.title)
			displayedStatuses = p.displayedStatuses()
		}
		if let i = issue {
			setTitle(i.title)
		}

		var rowTypes = [String]()

		for s in displayedStatuses ?? [] {
			rowTypes.append("StatusRow")
		}

		var showDescription = false

		if let p = pullRequest {

			showDescription = !(Settings.hideDescriptionInWatchDetail || (p.body ?? "").isEmpty)
			if showDescription {
				rowTypes.append("LabelRow")
			}

			for c in 0..<p.comments.count {
				rowTypes.append("CommentRow")
			}

		} else if let i = issue {

			showDescription = !(Settings.hideDescriptionInWatchDetail || (i.body ?? "").isEmpty)
			if showDescription {
				rowTypes.append("LabelRow")
			}

			for c in 0..<i.comments.count {
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
			setDisplayForBody(showDescription ? p.body : nil,
				unreadComments: p.unreadComments?.integerValue ?? 0,
				comments: p.sortedComments(NSComparisonResult.OrderedDescending),
				startingAtIndex: index)
		} else if let i = issue {
			setDisplayForBody(showDescription ? i.body : nil,
				unreadComments: i.unreadComments?.integerValue ?? 0,
				comments: i.sortedComments(NSComparisonResult.OrderedDescending),
				startingAtIndex: index)
		}
	}

	private func setDisplayForBody(body: String?, unreadComments: Int, comments: [PRComment], startingAtIndex: Int) {
		var index = startingAtIndex
		if let b = body {
			(table.rowControllerAtIndex(index++) as! LabelRow).labelL.setText(b)
		}
		var unreadCount = unreadComments
		for c in comments {
			setCommentRow(table.rowControllerAtIndex(index++) as! CommentRow, comment: c, unreadCount: &unreadCount)
		}
	}

	private func setCommentRow(controller: CommentRow, comment: PRComment, inout unreadCount: Int) {
		let date = comment.createdAt ?? NSDate()

		controller.usernameL.setText("@" + (comment.userName?.uppercaseString ?? "(unknown)"))
		controller.dateL.setText(shortDateFormatter.stringFromDate(date))
		controller.commentL.setText(comment.body)
		controller.commentId = comment.objectID.URIRepresentation().absoluteString

		if unreadCount > 0 {
			unreadCount--
			controller.margin.setBackgroundColor(UIColor.redColor())
		} else {
			controller.margin.setBackgroundColor(UIColor(white: 0.86, alpha: 1.0))
		}
	}
}
