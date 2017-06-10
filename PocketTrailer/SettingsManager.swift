
import UIKit

let settingsManager = SettingsManager()

final class SettingsManager {

	private func loadSettingsFrom(url: URL) {
		if Settings.readFromURL(url) {
			atNextEvent {

				popupManager.masterController.resetView(becauseOfChanges: true)

				preferencesDirty = true
				Settings.lastSuccessfulRefresh = nil

				atNextEvent {
					app.startRefreshIfItIsDue()
				}
			}
		} else {
			atNextEvent {
				showMessage("Error", "These settings could not be imported due to an error")
			}
		}
	}

	func loadSettingsFrom(url: URL, confirmFromView: UIViewController?, withCompletion: ((Bool)->Void)?) {
		if let v = confirmFromView {
			let a = UIAlertController(title: "Import these settings?", message: "This will overwrite all your current settings, are you sure?", preferredStyle: .alert)
			a.addAction(UIAlertAction(title: "Yes", style: .destructive) { action in
				self.loadSettingsFrom(url: url)
				withCompletion?(true)
			})
			a.addAction(UIAlertAction(title: "No", style: .cancel) { action in
				withCompletion?(false)
			})
			atNextEvent {
				v.present(a, animated: true)
			}
		} else {
			loadSettingsFrom(url: url)
			withCompletion?(true)
		}
	}
}
