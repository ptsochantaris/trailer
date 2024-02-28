import CoreData
import UIKit

final class ServersViewController: UITableViewController {
    private var selectedServerId: NSManagedObjectID?
    private var allServers = [ApiServer]()

    @IBOutlet var apiSwitch: UIBarButtonItem!

    @IBAction private func doneSelected() {
        dismiss(animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        clearsSelectionOnViewWillAppear = true
        NotificationCenter.default.addObserver(tableView!, selector: #selector(UITableView.reloadData), name: .RefreshEnded, object: nil)
        updateApiLabel()
        navigationItem.largeTitleDisplayMode = .automatic
    }

    private func updateApiLabel() {
        apiSwitch.title = Settings.useV4API ? "Using v4 API" : "Using v3 API"
    }

    deinit {
        if let tableView {
            NotificationCenter.default.removeObserver(tableView)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        allServers = ApiServer.allApiServers(in: DataManager.main)
        tableView.reloadData()
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        allServers.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ServerCell", for: indexPath)
        if let T = cell.textLabel, let D = cell.detailTextLabel {
            let a = allServers[indexPath.row]
            if a.authToken.isEmpty {
                T.textColor = .appRed
                T.text = "\(a.label.orEmpty) (needs token!)"
            } else if !a.lastSyncSucceeded {
                T.textColor = .appRed
                T.text = "\(a.label.orEmpty) (last sync failed)"
            } else {
                T.textColor = UIColor.label
                T.text = a.label
            }
            if a.requestsLimit == 0 {
                D.text = nil
            } else {
                let total = Double(a.requestsLimit)
                let used = Double(total - Double(a.requestsRemaining))
                if a.resetDate != nil {
                    D.text = String(format: "%.01f%% API used (%.0f / %.0f requests)\nNext reset: %@", 100 * used / total, used, total, shortDateFormatter.string(from: a.resetDate!))
                } else {
                    D.text = String(format: "%.01f%% API used (%.0f / %.0f requests)", 100 * used / total, used, total)
                }
            }
        }
        return cell
    }

    override func tableView(_: UITableView, canEditRowAt _: IndexPath) -> Bool {
        true
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == UITableViewCell.EditingStyle.delete {
            let a = allServers[indexPath.row]
            allServers.remove(at: indexPath.row)
            DataManager.main.delete(a)
            Task {
                await DataManager.saveDB()
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
        }
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        let a = allServers[indexPath.row]
        selectedServerId = a.objectID
        performSegue(withIdentifier: "editServer", sender: self)
    }

    @IBAction private func newServer() {
        performSegue(withIdentifier: "editServer", sender: self)
    }

    override func prepare(for segue: UIStoryboardSegue, sender _: Any?) {
        if let sd = segue.destination as? ServerDetailViewController {
            sd.serverLocalId = selectedServerId
            selectedServerId = nil
        }
    }

    @IBAction private func apiToggleSelected(_ sender: UIBarButtonItem) {
        let a = UIAlertController(title: "API Options", message: Settings.useV4APIHelp, preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: "Use legacy v3 API", style: .default) { [weak self] _ in
            Settings.useV4API = false
            self?.apiChanged()
        })
        a.addAction(UIAlertAction(title: "Use v4 API", style: .default) { [weak self] _ in
            if let error = API.canUseV4API(for: DataManager.main) {
                showMessage(Settings.v4title, error)
            } else {
                Settings.useV4API = true
                self?.apiChanged()
            }
        })
        a.addAction(UIAlertAction(title: "v4 API Options…", style: .default) { [weak self] _ in
            if let error = API.canUseV4API(for: DataManager.main) {
                showMessage(Settings.v4title, error)
            } else {
                self?.performSegue(withIdentifier: "apiOptions", sender: nil)
            }
        })
        a.addAction(UIAlertAction(title: "Log Monitor…", style: .default) { [weak self] _ in
            self?.performSegue(withIdentifier: "liveLog", sender: nil)
        })
        a.addAction(UIAlertAction(title: "Hidden Items…", style: .default) { [weak self] _ in
            self?.performSegue(withIdentifier: "hiddenItems", sender: nil)
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
        a.popoverPresentationController?.barButtonItem = sender
    }

    private func apiChanged() {
        updateApiLabel()
        for apiServer in ApiServer.allApiServers(in: DataManager.main) {
            apiServer.deleteEverything()
            apiServer.resetSyncState()
        }
        Task {
            await DataManager.saveDB()
        }
    }

    @IBAction private func resyncEverythingSelected(_ sender: UIBarButtonItem) {
        let a = UIAlertController(title: sender.title, message: Settings.reloadAllDataHelp, preferredStyle: .actionSheet)
        a.addAction(UIAlertAction(title: sender.title, style: .destructive) { [weak self] _ in
            self?.performFullReload()
        })
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(a, animated: true)
        a.popoverPresentationController?.barButtonItem = sender
    }

    private func performFullReload() {
        for a in ApiServer.allApiServers(in: DataManager.main) {
            a.deleteEverything()
            a.resetSyncState()
        }
        Task {
            await DataManager.saveDB()
            await DataManager.postProcessAllItems(in: DataManager.main, settings: Settings.cache)
            _ = await app.startRefresh()
        }
    }
}
