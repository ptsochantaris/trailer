
import WatchKit
import WatchConnectivity

final class SectionController: CommonController {

	////////////////////// List

	@IBOutlet weak var table: WKInterfaceTable!
	@IBOutlet weak var statusLabel: WKInterfaceLabel!

	private var rowControllers = [PopulatableRow]()

	override func awake(withContext context: Any?) {
		_statusLabel = statusLabel
		_table = table
		super.awake(withContext: context)
		updateUI()
	}

	override var showLoadingFeedback: Bool {
		return false
	}

	@IBAction func clearMergedSelected() {
		show(status: "Clearing merged", hideTable: true)
		requestData(command: "clearAllMerged")
	}

	@IBAction func clearClosedSelected() {
		show(status: "Clearing closed", hideTable: true)
		requestData(command: "clearAllClosed")
	}

	@IBAction func markAllReadSelected() {
		show(status: "Marking all as read", hideTable: true)
		requestData(command: "markEverythingRead")
	}

	@IBAction func refreshSelected() {
		show(status: "Starting refresh", hideTable: true)
		requestData(command: "refresh")
	}

	override func requestData(command: String?) {
		if let c = command {
			send(request: ["command": c])
		} else if WCSession.default.receivedApplicationContext.keys.contains("overview") {
			updateUI()
		} else {
			requestData(command: "needsOverview")
		}
	}

	override func table(_ table: WKInterfaceTable, didSelectRowAt rowIndex: Int) {
		let r = rowControllers[rowIndex] as! SectionRow
		let section = r.section?.rawValue ?? -1
		pushController(withName: "ListController", context: [
			SECTION_KEY: section,
			TYPE_KEY: r.type!,
			UNREAD_KEY: section == -1,
			GROUP_KEY: r.groupLabel!,
			API_URI_KEY: r.apiServerUri! ] )
	}

	override func update(from response: [AnyHashable : Any]) {
		super.update(from: response)
		updateUI()
	}

	private func sectionFrom(apiName: String) -> Section {
		return Section(Section.apiTitles.index(of: apiName)!)!
	}

	func resetUI() {
		if table.numberOfRows > 0 {
			table.scrollToRow(at: 0)
		}
	}

	private func updateUI() {

		rowControllers.removeAll(keepingCapacity: false)

		func addSectionsFor(_ entry: [AnyHashable : Any], itemType: String, label: String, apiServerUri: String, header: String, showEmptyDescriptions: Bool) {
			let items = entry[itemType] as! [AnyHashable : Any]
			let totalItems = items["total"] as! Int
			let prefix = label.isEmpty ? "" : "\(label): "
			if totalItems > 0 {
				let pt = TitleRow()
				pt.title = "\(prefix)\(totalItems) \(header)"
				rowControllers.append(pt)
				var totalUnread = 0
				for itemSection in Section.apiTitles {
					if itemSection == Section.none.apiName { continue }

					if let section = items[itemSection] as? [AnyHashable : Any], let count = section["total"] as? Int, let unread = section["unread"] as? Int, count > 0 {
						let s = SectionRow()
						s.section = sectionFrom(apiName: itemSection)
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

		let session = WCSession.default
		guard let result = session.receivedApplicationContext["overview"] as? [AnyHashable : Any] else {
			if session.iOSDeviceNeedsUnlockAfterRebootForReachability {
				show(status: "Can't connect: To re-establish your secure connection, please unlock your iOS device.", hideTable: true)
			} else {
				switch session.activationState {
				case .inactive:
					show(status: "Not connected to Trailer on your iOS device.", hideTable: true)
				case .notActivated:
					show(status: "Connecting…", hideTable: true)
				case .activated:
					show(status: "Loading…", hideTable: true)
				}
			}
			return
		}

		guard let views = result["views"] as? [[AnyHashable : Any]] else {
			show(status: "There is no data from Trailer on your iOS device yet. Please launch it once and configure your settings.", hideTable: true)
			return
		}
		
		let showEmptyDescriptions = views.count == 1

		let s = SummaryRow()
		if s.setSummary(from: result) {
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
				c.populate(from: rc)
			}
			index += 1
		}

		show(status: "", hideTable: false)
	}
}
