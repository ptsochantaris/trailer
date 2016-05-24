
import UIKit

final class CommentBlacklistViewController: UITableViewController {

	override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
		return Settings.commentAuthorBlacklist.count == 0 ? 0 : 1
	}

	override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
		return true
	}

	override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return Settings.commentAuthorBlacklist.count
	}

	override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCellWithIdentifier("UsernameCell", forIndexPath: indexPath) 
		cell.textLabel?.text = Settings.commentAuthorBlacklist[indexPath.row]
		return cell
	}

	override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
		if editingStyle == UITableViewCellEditingStyle.Delete {
			var blackList = Settings.commentAuthorBlacklist
			blackList.removeAtIndex(indexPath.row)
			Settings.commentAuthorBlacklist = blackList
			if blackList.count==0 { // last delete
				tableView.deleteSections(NSIndexSet(index: 0), withRowAnimation: .Automatic)
			} else {
				tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
			}
		}
	}

	@IBAction func addSelected() {

		let a = UIAlertController(title: "Block commenter",
			message: "Enter the username of the poster whose comments you don't want to be notified about",
			preferredStyle: UIAlertControllerStyle.Alert)

		a.addTextFieldWithConfigurationHandler({ textField in
			textField.placeholder = "Username"
		})
		a.addAction(UIAlertAction(title: "Cancel", style: .Cancel, handler: nil))
		a.addAction(UIAlertAction(title: "Block", style: .Default, handler: { action in

			if let tf = a.textFields?.first, n = tf.text?.trim() {

				var name: String = n
				if name.characters.startsWith("@".characters) {
					name = name.substringFromIndex(name.startIndex.advancedBy(1))
				}

				atNextEvent(self) { S in
					if !name.isEmpty && !Settings.commentAuthorBlacklist.contains(name) {
						var blackList = Settings.commentAuthorBlacklist
						blackList.append(name)
						Settings.commentAuthorBlacklist = blackList
						let ip = NSIndexPath(forRow: blackList.count-1, inSection: 0)
						if blackList.count == 1 { // first insert
							S.tableView.insertSections(NSIndexSet(index: 0), withRowAnimation:.Automatic)
						} else {
							S.tableView.insertRowsAtIndexPaths([ip], withRowAnimation:.Automatic)
						}
					}
				}
			}
		}))

		presentViewController(a, animated: true, completion: nil)
	}
}
