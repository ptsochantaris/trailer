
import UIKit

let settingsManager = SettingsManager()

final class SettingsManager {

	private func loadSettingsFrom(url: NSURL) {
		if Settings.readFromURL(url) {
			atNextEvent {

				let m = popupManager.getMasterController()
				m.reloadDataWithAnimation(false)

				app.preferencesDirty = true
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

	func loadSettingsFrom(url: NSURL, confirmFromView: UIViewController?, withCompletion: ((Bool)->Void)?) {
		if let v = confirmFromView {
			let a = UIAlertController(title: "Import these settings?", message: "This will overwrite all your current settings, are you sure?", preferredStyle: UIAlertControllerStyle.Alert)
			a.addAction(UIAlertAction(title: "Yes", style: UIAlertActionStyle.Destructive, handler: { [weak self] action in
				self!.loadSettingsFrom(url)
				withCompletion?(true)
			}))
			a.addAction(UIAlertAction(title: "No", style: UIAlertActionStyle.Cancel, handler: { action in
				withCompletion?(false)
			}))
			atNextEvent {
				v.presentViewController(a, animated: true, completion: nil)
			}
		} else {
			loadSettingsFrom(url)
			withCompletion?(true)
		}
	}
}
