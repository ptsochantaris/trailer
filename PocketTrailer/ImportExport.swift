import UIKit
import UniformTypeIdentifiers

final class ImportExport: NSObject, UIDocumentPickerDelegate {

	private var tempUrl: URL?
	private let parentVC: UIViewController

	init(parent: UIViewController) {
		parentVC = parent
		super.init()
	}

	@objc func importSelected(sender: UIBarButtonItem) {
		tempUrl = nil

        let menu = UIDocumentPickerViewController(forOpeningContentTypes: [UTType("com.housetrip.mobile.trailer.ios.settings")!])
		menu.delegate = self
		popupManager.showPopoverFromViewController(parentViewController: parentVC, fromItem: sender, viewController: menu)
	}

	@objc func exportSelected(sender: UIBarButtonItem) {
		let tempFilePath = NSTemporaryDirectory().appending(pathComponent: "Trailer Settings (iOS).trailerSettings")
		tempUrl = URL(fileURLWithPath: tempFilePath)
		Settings.writeToURL(tempUrl!)

        let menu = UIDocumentPickerViewController(forExporting: [tempUrl!])
		menu.delegate = self
		popupManager.showPopoverFromViewController(parentViewController: parentVC, fromItem: sender, viewController: menu)
	}

	func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
		if tempUrl == nil {
			DLog("Will import settings from %@", url.absoluteString)
			settingsManager.loadSettingsFrom(url: url, confirmFromView: parentVC) { confirmed in
				if confirmed {
					self.parentVC.dismiss(animated: false)
				}
				self.documentInteractionCleanup()
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
