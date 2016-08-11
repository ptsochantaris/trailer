
import WatchKit
import WatchConnectivity

final class SectionController: CommonController {

	////////////////////// List

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet weak var statusLabel: WKInterfaceLabel!

	private var rowControllers = [PopulatableRow]()

	override func awake(withContext context: AnyObject?) {
		_statusLabel = statusLabel
		_table = table
		super.awake(withContext: context)
		updateUI()
	}

	override var showLoadingFeedback: Bool {
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

	override func requestData(_ command: String?) {
		if let c = command {
			sendRequest(["command": c])
		} else if WCSession.default().receivedApplicationContext["overview"] != nil {
			updateUI()
		} else {
			requestData("needsOverview")
		}
	}

	override func table(_ table: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
		let r = rowControllers[rowIndex] as! SectionRow
		let section = r.section?.rawValue ?? -1
		pushController(withName: "ListController", context: [
			SECTION_KEY: NSNumber(value: section),
			TYPE_KEY: r.type!,
			UNREAD_KEY: section == -1,
			GROUP_KEY: r.groupLabel!,
			API_URI_KEY: r.apiServerUri! ] )
	}

	override func updateFromData(_ response: [NSString : AnyObject]) {
		super.updateFromData(response)
		updateUI()
	}

	private func sectionFromApi(_ apiName: String) -> Section {
		return Section(Section.apiTitles.index(of: apiName)!)!
	}

	func resetUI() {
		if table.numberOfRows > 0 {
			table.scrollToRow(at: 0)
		}
	}

	private func updateUI() {

		rowControllers.removeAll(keepingCapacity: false)

		func addSectionsFor(_ entry: [String : AnyObject], itemType: String, label: String, apiServerUri: String, header: String, showEmptyDescriptions: Bool) {
			let items = entry[itemType] as! [String : AnyObject]
			let totalItems = items["total"] as! Int
			let prefix = label.isEmpty ? "" : "\(label): "
			if totalItems > 0 {
				let pt = TitleRow()
				pt.title = "\(prefix)\(totalItems) \(header)"
				rowControllers.append(pt)
				var totalUnread = 0
				for itemSection in Section.apiTitles {
					if itemSection == Section.none.apiName { continue }

					if let section = items[itemSection], let count = section["total"] as? Int, let unread = section["unread"] as? Int, count > 0 {
						let s = SectionRow()
						s.section = sectionFromApi(itemSection)
						s.totalCount = count
						s.unreadCount = unread
						s.type = itemType
						s.groupLabel = label
						s.apiServerUri = apiServerUri
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
					s.groupLabel = label
					s.apiServerUri = apiServerUri
					rowControllers.append(s)
				}

			} else if showEmptyDescriptions {
				let error = (items["error"] as? String) ?? ""
				let pt = TitleRow()
				pt.title = "\(prefix)\(header): \(error)"
				rowControllers.append(pt)
			}
		}

		let session = WCSession.default()
		guard let result = session.receivedApplicationContext["overview"] as? [String : AnyObject] else {
			if session.iOSDeviceNeedsUnlockAfterRebootForReachability {
				showStatus("Can't connect: To re-establish your secure connection, please unlock your iOS device.", hideTable: true)
			} else {
				switch session.activationState {
				case .activated:
					showStatus("Loading...", hideTable: true)
				case .inactive:
					showStatus("Connecting...", hideTable: true)
				case .notActivated:
					showStatus("Not connected to Trailer on your iOS device.", hideTable: true)
				}
			}
			return
		}

		guard let views = result["views"] as? [[String : AnyObject]] else {
			showStatus("There is no data from Trailer on your iOS device yet. Please launch it once and configure your settings.", hideTable: true)
			return
		}

		let showEmptyDescriptions = views.count == 1

		let s = SummaryRow()
		if s.setSummary(result) {
			rowControllers.append(s)
		}

		for v in views {
			let label = v["title"] as! String
			let apiServerUri = v["apiUri"] as! String
			addSectionsFor(v, itemType: "prs", label: label, apiServerUri: apiServerUri, header: "Pull Requests", showEmptyDescriptions: showEmptyDescriptions)
			addSectionsFor(v, itemType: "issues", label: label, apiServerUri: apiServerUri, header: "Issues", showEmptyDescriptions: showEmptyDescriptions)
		}

		let rowTypes = rowControllers.map { $0.rowType }
		table.setRowTypes(rowTypes)

		var index = 0
		for rc in rowControllers {
			if let c = table.rowController(at: index) as? PopulatableRow {
				c.populateFrom(rc)
			}
			index += 1
		}

		showStatus("", hideTable: false)
	}
}
