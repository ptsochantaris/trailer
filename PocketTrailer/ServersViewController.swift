
import UIKit
import CoreData

final class ServersViewController: UITableViewController {

	private var selectedServerId: NSManagedObjectID?
	private var allServers: [ApiServer]!

	@IBAction func doneSelected() {
		if preferencesDirty {
			app.startRefresh()
		}
		dismiss(animated: true, completion: nil)
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		clearsSelectionOnViewWillAppear = true
		NotificationCenter.default.addObserver(tableView, selector: #selector(UITableView.reloadData), name: RefreshEndedNotification, object: nil)
	}

	deinit {
		if tableView != nil {
			NotificationCenter.default.removeObserver(tableView)
		}
	}

	override func viewWillAppear(_ animated: Bool) {
		super.viewWillAppear(animated)
		allServers = ApiServer.allApiServers(in: DataManager.main)
		tableView.reloadData()
	}

	override func numberOfSections(in tableView: UITableView) -> Int {
		return 1
	}

	override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
		return allServers.count
	}

	override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
		let cell = tableView.dequeueReusableCell(withIdentifier: "ServerCell", for: indexPath)
		if let T = cell.textLabel, let D = cell.detailTextLabel {
			let a = allServers[indexPath.row]
			if S(a.authToken).isEmpty {
				T.textColor = .red
				T.text = "\(S(a.label)) (needs token!)"
			} else if !a.lastSyncSucceeded {
				T.textColor = .red
				T.text = "\(S(a.label)) (last sync failed)"
			} else {
				T.textColor = .darkText
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

	override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
		if editingStyle == UITableViewCellEditingStyle.delete {
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

	@IBAction func newServer() {
		performSegue(withIdentifier: "editServer", sender: self)
	}

	override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
		if let sd = segue.destination as? ServerDetailViewController {
			sd.serverId = selectedServerId
			selectedServerId = nil
		}
	}
}
