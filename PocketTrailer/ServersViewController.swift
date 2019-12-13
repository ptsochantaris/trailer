
import UIKit
import CoreData

final class ServersViewController: UITableViewController {

	private var selectedServerId: NSManagedObjectID?
	private var allServers: [ApiServer]!

	@IBAction private func doneSelected() {
		dismiss(animated: true)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		navigationItem.largeTitleDisplayMode = .automatic
		clearsSelectionOnViewWillAppear = true
        NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .RefreshEnded, object: nil)
	}

	deinit {
		if let tableView = tableView {
			NotificationCenter.default.removeObserver(tableView)
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		allServers = ApiServer.allApiServers(in: DataManager.main)
		tableView.reloadData()
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return allServers.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "ServerCell", for: indexPath)
		if let T = cell.textLabel, let D = cell.detailTextLabel {
			let a = allServers[indexPath.row]
			if S(a.authToken).isEmpty {
				T.textColor = .systemRed
				T.text = "\(S(a.label)) (needs token!)"
			} else if !a.lastSyncSucceeded {
				T.textColor = .systemRed
				T.text = "\(S(a.label)) (last sync failed)"
			} else {
                T.textColor = labelColour
				T.text = a.label
			}
			if a.requestsLimit == 0 {
				D.text = nil
			} else {
				let total = Double(a.requestsLimit)
				let used = Double(total - Double(a.requestsRemaining))
				if a.resetDate != nil {
					D.text = String(format:"%.01f%% API used (%.0f / %.0f requests)\nNext reset: %@", 100*used/total, used, total, shortDateFormatter.string(from: a.resetDate!))
				} else {
					D.text = String(format:"%.01f%% API used (%.0f / %.0f requests)", 100*used/total, used, total)
				}
			}
		}
		return cell
	}

	override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
		return true
	}

	override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
		if editingStyle == UITableViewCell.EditingStyle.delete {
			let a = allServers[indexPath.row]
			allServers.remove(at: indexPath.row)
			DataManager.main.delete(a)
			DataManager.saveDB()
			tableView.deleteRows(at: [indexPath], with: .fade)
		}
	}

	override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
		let a = allServers[indexPath.row]
		selectedServerId = a.objectID
		performSegue(withIdentifier: "editServer", sender: self)
	}

	@IBAction private func newServer() {
		performSegue(withIdentifier: "editServer", sender: self)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let sd = segue.destination as? ServerDetailViewController {
			sd.serverId = selectedServerId
			selectedServerId = nil
		}
	}
}
