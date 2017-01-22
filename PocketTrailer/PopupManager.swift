
import UIKit

let popupManager = PopupManager()

final class PopupManager: NSObject, UISplitViewControllerDelegate {

	/////////////// Popovers

	func showPopoverFromViewController(parentViewController: UIViewController, fromItem: UIBarButtonItem, viewController: UIViewController) {
		if UIDevice.current.userInterfaceIdiom == .pad {
			viewController.modalPresentationStyle = .popover
			parentViewController.present(viewController, animated: true)
			viewController.popoverPresentationController?.barButtonItem = fromItem
		} else {
			viewController.modalPresentationStyle = .currentContext
			let v = (parentViewController.tabBarController ?? parentViewController.navigationController) ?? parentViewController
			v.present(viewController, animated: true)
		}
	}

	/////////////// Sharing

	func shareFromView(view: UIViewController, buttonItem: UIBarButtonItem, url: URL) {
		let a = OpenInSafariActivity()
		let v = UIActivityViewController(activityItems: [url], applicationActivities: [a])
		showPopoverFromViewController(parentViewController: view, fromItem: buttonItem, viewController: v)
	}

	////////////// Master view

	var masterController: MasterViewController {
		let s = app.window!.rootViewController as! UISplitViewController
		return (s.viewControllers.first as! UINavigationController).viewControllers.first as! MasterViewController
	}

	func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
		let d = (secondaryViewController as! UINavigationController).viewControllers.first as! DetailViewController
		return d.detailItem==nil
	}

	func splitViewController(_ splitViewController: UISplitViewController, separateSecondaryFrom primaryViewController: UIViewController) -> UIViewController? {
		return nil
	}
}

