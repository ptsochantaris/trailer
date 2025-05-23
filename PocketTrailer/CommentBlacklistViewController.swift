import UIKit

final class CommentBlacklistViewController: UITableViewController {
    enum Mode {
        case commentAuthors, labels, itemAuthors

        var title: String {
            switch self {
            case .commentAuthors: "Block Commenters"
            case .labels: "Block Labels"
            case .itemAuthors: "Block Authors"
            }
        }

        var placeholder: String {
            switch self {
            case .commentAuthors: "Username"
            case .labels: "Label"
            case .itemAuthors: "Username"
            }
        }

        var inputTitle: String {
            switch self {
            case .commentAuthors: "Block commenter"
            case .labels: "Block label"
            case .itemAuthors: "Block author"
            }
        }

        var inputText: String {
            switch self {
            case .commentAuthors: "Comments from this user will not produce notifications"
            case .labels: "Items containing this label will be hidden"
            case .itemAuthors: "Items by this author will be hidden"
            }
        }
    }

    var mode = Mode.commentAuthors

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = mode.title
    }

    override func numberOfSections(in _: UITableView) -> Int {
        getBlacklist().isEmpty ? 0 : 1
    }

    override func tableView(_: UITableView, canEditRowAt _: IndexPath) -> Bool {
        true
    }

    override func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        getBlacklist().count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "UsernameCell", for: indexPath)
        cell.textLabel?.text = getBlacklist()[indexPath.row]
        return cell
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            var blackList = getBlacklist()
            blackList.remove(at: indexPath.row)
            storeBlacklist(blackList)
            if blackList.isEmpty { // last delete
                tableView.deleteSections(IndexSet(integer: 0), with: .fade)
            } else {
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
        }
    }

    private func getBlacklist() -> [String] {
        switch mode {
        case .commentAuthors:
            Settings.commentAuthorBlacklist
        case .labels:
            Settings.labelBlacklist
        case .itemAuthors:
            Settings.itemAuthorBlacklist
        }
    }

    private func storeBlacklist(_ newList: [String]) {
        switch mode {
        case .commentAuthors:
            Settings.commentAuthorBlacklist = newList
        case .labels:
            Settings.labelBlacklist = newList
        case .itemAuthors:
            Settings.itemAuthorBlacklist = newList
        }
        Task {
            await DataManager.postProcessAllItems(in: DataManager.main, settings: Settings.cache)
        }
    }

    @IBAction private func addSelected() {
        let a = UIAlertController(title: mode.inputTitle, message: mode.inputText, preferredStyle: .alert)
        a.addTextField { textField in
            textField.placeholder = self.mode.placeholder
        }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        a.addAction(UIAlertAction(title: "Block", style: .default) { _ in
            guard let tf = a.textFields?.first, let n = tf.text?.trim else {
                return
            }

            let name = n.hasPrefix("@") ? String(n.dropFirst()) : n

            Task { @MainActor [weak self] in
                guard let self else { return }
                var blackList = getBlacklist()
                if !name.isEmpty, !blackList.contains(name) {
                    blackList.append(name)
                    storeBlacklist(blackList)
                    let ip = IndexPath(row: blackList.count - 1, section: 0)
                    if blackList.count == 1 { // first insert
                        tableView.insertSections(IndexSet(integer: 0), with: .fade)
                    } else {
                        tableView.insertRows(at: [ip], with: .fade)
                    }
                }
            }
        })

        present(a, animated: true)
    }
}
