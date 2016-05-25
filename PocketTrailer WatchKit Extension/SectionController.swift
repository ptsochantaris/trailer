
import WatchKit
import WatchConnectivity

final class SectionController: CommonController {

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet weak var statusLabel: WKInterfaceLabel!

	private var rowControllers = [PopulatableRow]()

	override func awakeWithContext(context: AnyObject?) {
		_statusLabel = statusLabel
		_table = table
		super.awakeWithContext(context)
	}

	override func showLoadingFeedback() -> Bool {
		return false
	}

	@IBAction func clearMergedSelected() {
		showStatus("Clearing merged", hideTable: true)
		requestData("clearAllMerged")
	}

	@IBAction func clearClosedSelected() {
		showStatus("Clearing closed", hideTable: true)
		requestData("clearAllClosed")
	}

	@IBAction func markAllReadSelected() {
		showStatus("Marking all as read", hideTable: true)
		requestData("markEverythingRead")
	}

	@IBAction func refreshSelected() {
		showStatus("Refreshing", hideTable: true)
		requestData("refresh")
	}

	override func requestData(command: String?) {
		if let c = command {
			sendRequest(["command": c])
		} else {
			updateUI()
		}
	}

	override func table(table: WKInterfaceTable, didSelectRowAtIndex rowIndex: Int) {
		let r = rowControllers[rowIndex] as! SectionRow
		let section = r.section?.rawValue ?? -1
		pushControllerWithName("ListController", context: [ SECTION_KEY: section, TYPE_KEY: r.type!, UNREAD_KEY: section == -1 ] )
	}

	override func updateFromData(response: [NSString : AnyObject]) {
		super.updateFromData(response)
		updateUI()
	}

	private func sectionFromApi(apiName: String) -> Section {
		return Section(rawValue: Section.apiTitles.indexOf(apiName)!)!
	}

	private func updateUI() {

		rowControllers.removeAll(keepCapacity: false)
		let session = WCSession.defaultSession()
		if let result = session.receivedApplicationContext["overview"] as? [String : AnyObject] {

			func addSectionsFor(itemType: String, header: String) {
				let items = result[itemType] as! [String : AnyObject]
				let totalItems = items["total"] as! Int
				let pt = TitleRow()
				rowControllers.append(pt)
				if totalItems > 0 {
					pt.title = "\(totalItems) \(header)"
					var totalUnread = 0
					for itemSection in Section.apiTitles {
						if itemSection == Section.None.apiName() { continue }

						if let section = items[itemSection], count = section["total"] as? Int, unread = section["unread"] as? Int where count > 0 {
							let s = SectionRow()
							s.section = sectionFromApi(itemSection)
							s.totalCount = count
							s.unreadCount = unread
							s.type = itemType
							rowControllers.append(s)

							totalUnread += unread
						}
					}
					if totalUnread > 0 {
						let s = SectionRow()
						s.section = nil
						s.totalCount = 0
						s.unreadCount = totalUnread
						s.type = itemType
						rowControllers.append(s)
					}

				} else {
					pt.title = items["error"] as? String
				}
			}

			addSectionsFor("prs", header: "Pull Requests")
			addSectionsFor("issues", header: "Issues")

			table.setRowTypes(rowControllers.map({ $0.rowType() }))

			var index = 0
			for rc in rowControllers {
				if let c = table.rowControllerAtIndex(index) as? PopulatableRow {
					c.populateFrom(rc)
				}
				index += 1
			}

			showStatus("", hideTable: false)
			(WKExtension.sharedExtension().delegate as! ExtensionDelegate).updateComplications()
		} else {
			showStatus("There is no data from Trailer yet, please run it once on your iOS device", hideTable: true)
		}
	}
}
