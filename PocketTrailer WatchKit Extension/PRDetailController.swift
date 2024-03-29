import Foundation
import WatchKit

final class PRDetailController: CommonController {
    @IBOutlet private var table: WKInterfaceTable!
    @IBOutlet private var statusLabel: WKInterfaceLabel!

    private var rowControllers = [PopulatableRow]()
    private var itemId: String!
    private var loading = false

    @IBOutlet private var openInAppButton: WKInterfaceButton!
    @IBOutlet private var markReadButton: WKInterfaceButton!

    override func awake(withContext context: Any?) {
        _statusLabel = statusLabel
        _table = table

        let c = context as! [AnyHashable: Any]
        itemId = (c[ITEM_KEY] as! String)

        super.awake(withContext: context)
    }

    override func requestData(command: String?) {
        if !loading {
            loading = true
            var params = ["list": "item_detail", "localId": itemId!]
            if let command {
                params["command"] = command
            }
            send(request: params)
        }
    }

    @IBAction private func refreshSelected() {
        show(status: "Starting refresh", hideTable: true)
        requestData(command: "refresh")
    }

    @IBAction private func markAllReadSelected() {
        requestData(command: "markItemsRead")
    }

    @IBAction private func openOnDeviceSelected() {
        requestData(command: "openItem")
    }

    override func update(from response: [AnyHashable: Any]) {
        guard let compressedData = response["result"] as? Data,
              let uncompressedData = compressedData.data(operation: .decompress),
              let itemInfo = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: uncompressedData),
              let item = itemInfo as? [AnyHashable: Any]
        else { return }
        Task { @MainActor in
            completeUpdate(from: item)
        }
    }

    override func show(status: String, hideTable: Bool) {
        if hideTable {
            markReadButton.setHidden(true)
            openInAppButton.setHidden(true)
        }
        super.show(status: status, hideTable: hideTable)
    }

    private func completeUpdate(from itemInfo: [AnyHashable: Any]) {
        loading = false

        rowControllers.removeAll(keepingCapacity: false)

        var rowCount = 0

        if let statuses = itemInfo["statuses"] as? [[AnyHashable: Any]] {
            for status in statuses {
                if !(table.rowController(at: rowCount) is StatusRow) {
                    table.insertRows(at: IndexSet(integer: rowCount), withRowType: "StatusRow")
                }
                if let s = table.rowController(at: rowCount) as? StatusRow {
                    s.labelL.setText(status["text"] as? String)
                    let c = status["color"] as! UIColor
                    s.labelL.setTextColor(c)
                    s.margin.setBackgroundColor(c)
                }
                rowCount += 1
            }
        }

        if let description = itemInfo["description"] as? String {
            while table.rowController(at: rowCount) is StatusRow {
                table.removeRows(at: IndexSet(integer: rowCount))
            }
            if !(table.rowController(at: rowCount) is LabelRow) {
                table.insertRows(at: IndexSet(integer: rowCount), withRowType: "LabelRow")
            }
            if let r = table.rowController(at: rowCount) as? LabelRow {
                r.labelL.setText(description)
            }
            rowCount += 1
        }

        if let comments = itemInfo["comments"] as? [[AnyHashable: Any]] {
            if comments.isEmpty {
                setTitle("\(comments.count) Comments")
            } else {
                setTitle("Details")
            }

            var unreadIndex = 0
            let unreadCount = itemInfo["unreadCount"] as? Int ?? 0
            for comment in comments {
                while table.rowController(at: rowCount) is LabelRow {
                    table.removeRows(at: IndexSet(integer: rowCount))
                }
                if !(table.rowController(at: rowCount) is CommentRow) {
                    table.insertRows(at: IndexSet(integer: rowCount), withRowType: "CommentRow")
                }
                if let s = table.rowController(at: rowCount) as? CommentRow {
                    s.set(comment: comment, unreadCount: unreadCount, unreadIndex: &unreadIndex)
                }
                rowCount += 1
            }
            markReadButton.setHidden(unreadCount > 0)
        } else {
            setTitle("Details")
            markReadButton.setHidden(true)
        }

        while table.numberOfRows > rowCount {
            table.removeRows(at: IndexSet(integer: rowCount))
        }

        openInAppButton.setHidden(false)

        show(status: "", hideTable: false)
    }
}
