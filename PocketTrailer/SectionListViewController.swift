import UIKit

final class SectionListViewController: UITableViewController {
    /// Owned by this view controller and rebuilt from the database on demand. This used to be a
    /// `static var` that `DetailViewController` wrote to, announcing itself via a notification. That
    /// made the sections list unable to refresh itself: the only post-sync write sat behind
    /// `DetailViewController.updateStatus`'s `guard isViewLoaded`, so while the split view was
    /// collapsed on iPhone the detail controller had never loaded and this list never changed.
    private var tabBarSets = [TabInfo]()

    private func refreshTabs() {
        tabBarSets = TabInfo.allSets()
        tableView.reloadData()
    }

    private var observers = [NotificationObserver]()
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

        observers = [
            NotificationObserver(.showPreferences, debounce: 0.01) { [weak self] notification in
                self?.performSegue(withIdentifier: "showPreferences", sender: notification.object as? Int)
            },
            NotificationObserver(.SyncProgressUpdate, debounce: 0.1) { [weak self] _ in
                self?.title = "Refreshing…"
                self?.statusMessage = API.currentOperationName
            },
            NotificationObserver(.RefreshEnded, debounce: 0.1) { [weak self] _ in
                self?.title = "Sections"
                self?.statusMessage = nil
                self?.refreshTabs()
            },
            // Observed directly rather than waiting to be told by `DetailViewController`, so the list
            // stays correct even when that controller has never been loaded.
            NotificationObserver(.dbSaved, debounce: 0.1) { [weak self] _ in
                self?.refreshTabs()
            }
        ]

        refreshTabs()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Cheap insurance: anything that changed the database while this list was off-screen — repo
        // visibility, a background sync — is picked up without needing to have observed it.
        refreshTabs()
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
                // Deliberately delayed. Our own `.showPreferences` observer registers when its
                // task first runs, which is a later main-actor turn than this one, so posting
                // synchronously here would be missed on first launch.
                Task {
                    try? await Task.sleep(for: .milliseconds(100))
                    NotificationCenter.default.post(name: .showPreferences, object: nil)
                }
            }
        }
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        tabBarSets.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Section", for: indexPath)

        let section = tabBarSets[indexPath.row]

        var config = UIListContentConfiguration.valueCell()
        config.text = section.title
        config.textProperties.font = .preferredFont(forTextStyle: .headline)

        config.secondaryText = section.badgeValue
        config.secondaryTextProperties.color = .red
        config.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)

        config.image = UIImage(resource: section.image).withRenderingMode(.alwaysTemplate)

        cell.contentConfiguration = config

        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let splitViewController, let detail = splitViewController.viewController(for: .secondary) as? DetailViewController {
            detail.currentTabBar = tabBarSets[indexPath.row]
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
