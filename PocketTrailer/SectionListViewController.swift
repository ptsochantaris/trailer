import Combine
import UIKit

final class SectionListViewController: UITableViewController {
    static var tabBarSets = [TabInfo]() {
        didSet {
            NotificationCenter.default.post(name: .tabBarSetUpdate, object: nil)
        }
    }

    private func updateTabs() {
        tableView.reloadData()
    }

    private var tabObservation: Cancellable?
    private var syncObservation: Cancellable?
    private var prefsObservation: Cancellable?
    private var refreshObservation: Cancellable?
    private var firstAppearance = true

    private var statusMessage: String? {
        didSet {
            if isViewLoaded {
                tableView.reloadData()
            }
        }
    }

    override func tableView(_: UITableView, viewForHeaderInSection _: Int) -> UIView? {
        guard let statusMessage else {
            return nil
        }

        let frame = view.readableContentGuide.layoutFrame
        let label = UILabel(frame: CGRect(
            x: view.bounds.midX - frame.width * 0.5,
            y: 0,
            width: frame.width,
            height: 88
        ))
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.text = statusMessage
        return label
    }

    override func tableView(_: UITableView, heightForHeaderInSection _: Int) -> CGFloat {
        statusMessage == nil ? 0 : 88
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        tabObservation = NotificationCenter.default.publisher(for: .tabBarSetUpdate)
            .debounce(for: .seconds(0.01), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateTabs()
            }

        prefsObservation = NotificationCenter.default.publisher(for: .showPreferences)
            .debounce(for: .seconds(0.01), scheduler: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.performSegue(withIdentifier: "showPreferences", sender: notification.object as? Int)
            }

        syncObservation = NotificationCenter.default.publisher(for: .SyncProgressUpdate)
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.title = "Refreshing…"
                self?.statusMessage = API.currentOperationName
            }

        refreshObservation = NotificationCenter.default.publisher(for: .RefreshEnded)
            .debounce(for: .seconds(0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.title = "Sections"
                self?.statusMessage = nil
            }

        updateTabs()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard firstAppearance else {
            return
        }
        firstAppearance = false

        if !ApiServer.someServersHaveAuthTokens(in: DataManager.main) {
            if ApiServer.countApiServers(in: DataManager.main) == 1, let a = ApiServer.allApiServers(in: DataManager.main).first, a.authToken == nil || a.authToken!.isEmpty {
                performSegue(withIdentifier: "showQuickstart", sender: self)
            } else {
                NotificationCenter.default.post(name: .showPreferences, object: nil)
            }
        }
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        SectionListViewController.tabBarSets.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Section", for: indexPath)

        let section = SectionListViewController.tabBarSets[indexPath.row]

        var config = UIListContentConfiguration.valueCell()
        config.text = section.title
        config.secondaryText = section.badgeValue
        config.image = UIImage(resource: section.image).withRenderingMode(.alwaysTemplate)

        cell.contentConfiguration = config

        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let splitViewController, let detail = splitViewController.viewController(for: .secondary) as? DetailViewController {
            detail.currentTabBar = SectionListViewController.tabBarSets[indexPath.row]
            splitViewController.show(.secondary)
        }
    }

    ////////////////// opening prefs

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        var allServersHaveTokens = true
        for a in ApiServer.allApiServers(in: DataManager.main) where !a.goodToGo {
            allServersHaveTokens = false
            break
        }

        if let destination = segue.destination as? UITabBarController {
            let index = sender as? Int ?? Settings.lastPreferencesTabSelected
            if allServersHaveTokens {
                destination.selectedIndex = min(index, (destination.viewControllers?.count ?? 1) - 1)
            }
            destination.delegate = self
        }
    }
}

extension SectionListViewController: UITabBarControllerDelegate {
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        Settings.lastPreferencesTabSelected = tabBarController.viewControllers?.firstIndex(of: viewController) ?? 0
    }
}
