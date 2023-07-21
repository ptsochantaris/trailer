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
        _ = Settings.writeToURL(tempUrl!)

        let menu = UIDocumentPickerViewController(forExporting: [tempUrl!])
        menu.delegate = self
        popupManager.showPopoverFromViewController(parentViewController: parentVC, fromItem: sender, viewController: menu)
    }

    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        if tempUrl == nil {
            Logging.log("Will import settings from \(url.absoluteString)")
            Task {
                if await settingsManager.loadSettingsFrom(url: url, confirmFromView: parentVC) {
                    await parentVC.dismiss(animated: false)
                }
                documentInteractionCleanup()
            }
        } else {
            Logging.log("Saved settings to \(url.absoluteString)")
            documentInteractionCleanup()
        }
    }

    func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
        Logging.log("Document picker cancelled")
        documentInteractionCleanup()
    }

    func documentInteractionCleanup() {
        if let t = tempUrl {
            do {
                try FileManager.default.removeItem(at: t)
            } catch {
                Logging.log("Temporary file cleanup error: \(error.localizedDescription)")
            }
            tempUrl = nil
        }
    }
}
