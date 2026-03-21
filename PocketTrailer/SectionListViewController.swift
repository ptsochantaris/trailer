import Combine
import UIKit

final class SectionListViewController: UITableViewController {
    static var tabBarSets = [TabBarSet]() {
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

        var config = UIListContentConfiguration.valueCell()

        let section = SectionListViewController.tabBarSets[indexPath.row]

        config.text = section.prItem?.title ?? section.issuesItem?.title

        config.secondaryText = section.prItem?.badgeValue ?? section.issuesItem?.badgeValue

        if let resource = section.prItem?.image ?? section.issuesItem?.image {
            config.image = UIImage(resource: resource).withRenderingMode(.alwaysTemplate)
        } else {
            config.image = nil
        }

        cell.contentConfiguration = config

        return cell
    }

    override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let splitViewController, let detail = splitViewController.viewController(for: .secondary) as? DetailViewController {
            detail.currentTabBarSet = SectionListViewController.tabBarSets[indexPath.row]
            splitViewController.show(.secondary)
        }
    }
}
