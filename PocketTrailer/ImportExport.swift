
import Foundation
import UIKit

final class ImportExport: NSObject, UIDocumentPickerDelegate {

	private var tempUrl: URL?
	private let parentVC: UIViewController

	init(parent: UIViewController) {
		parentVC = parent
		super.init()
	}

	func importSelected(sender: UIBarButtonItem) {
		tempUrl = nil

		let menu = UIDocumentPickerViewController(documentTypes: ["com.housetrip.mobile.trailer.ios.settings"], in: .import)
		menu.delegate = self
		popupManager.showPopoverFromViewController(parentViewController: parentVC, fromItem: sender, viewController: menu)
	}

	func exportSelected(sender: UIBarButtonItem) {
		let tempFilePath = NSTemporaryDirectory().appending(pathComponent: "Trailer Settings (iOS).trailerSettings")
		tempUrl = URL(fileURLWithPath: tempFilePath)
		Settings.writeToURL(tempUrl!)

		let menu = UIDocumentPickerViewController(url: tempUrl!, in: .exportToService)
		menu.delegate = self
		popupManager.showPopoverFromViewController(parentViewController: parentVC, fromItem: sender, viewController: menu)
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
		if tempUrl == nil {
			DLog("Will import settings from %@", url.absoluteString)
			settingsManager.loadSettingsFrom(url: url, confirmFromView: parentVC) { [weak self] confirmed in
				if confirmed {
					self?.parentVC.dismiss(animated: false, completion: nil)
				}
				self?.documentInteractionCleanup()
			}
		} else {
			DLog("Saved settings to %@", url.absoluteString)
			documentInteractionCleanup()
		}
	}

	func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
		DLog("Document picker cancelled")
		documentInteractionCleanup()
	}

	func documentInteractionCleanup() {
		if let t = tempUrl {
			do {
				try FileManager.default.removeItem(at: t)
			} catch {
				DLog("Temporary file cleanup error: %@", error.localizedDescription)
			}
			tempUrl = nil
		}
	}

}
