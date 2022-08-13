import UIKit

@MainActor
let settingsManager = SettingsManager()

@MainActor
final class SettingsManager {
    private func loadSettingsFrom(url: URL) async {
        if await Settings.readFromURL(url) {
            DataManager.saveDB()

            Task {
                await popupManager.masterController.resetView(becauseOfChanges: true)

                preferencesDirty = true
                Settings.lastSuccessfulRefresh = nil

                Task {
                    await app.startRefreshIfItIsDue()
                }
            }
        } else {
            Task {
                showMessage("Error", "These settings could not be imported due to an error")
            }
        }
    }

    func loadSettingsFrom(url: URL, confirmFromView: UIViewController?) async -> Bool {
        if let v = confirmFromView {
            var continuation: CheckedContinuation<Bool, Never>?
            let a = UIAlertController(title: "Import these settings?", message: "This will overwrite all your current settings, are you sure?", preferredStyle: .alert)
            a.addAction(UIAlertAction(title: "Yes", style: .destructive) { _ in
                continuation?.resume(returning: true)
            })
            a.addAction(UIAlertAction(title: "No", style: .cancel) { _ in
                continuation?.resume(returning: false)
            })
            Task { @MainActor in
                v.present(a, animated: true)
            }
            let decision = await withCheckedContinuation { c in
                continuation = c
            }
            if !decision {
                return false
            }
        }
        await loadSettingsFrom(url: url)
        return true
    }
}
