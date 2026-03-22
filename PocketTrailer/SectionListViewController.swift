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
    private var prefsObservation: Cancellable?

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

        updateTabs()
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
