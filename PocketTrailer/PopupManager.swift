
import UIKit

let popupManager = PopupManager()

final class PopupManager: NSObject, UISplitViewControllerDelegate {

	/////////////// Popovers

	func showPopoverFromViewController(parentViewController: UIViewController, fromItem: UIBarButtonItem, viewController: UIViewController) {
		if UIDevice.current.userInterfaceIdiom == .pad {
			viewController.modalPresentationStyle = .popover
			parentViewController.present(viewController, animated: true, completion: nil)
			viewController.popoverPresentationController?.barButtonItem = fromItem
		} else {
			viewController.modalPresentationStyle = .currentContext
			let v = (parentViewController.tabBarController ?? parentViewController.navigationController) ?? parentViewController
			v.present(viewController, animated: true, completion: nil)
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

func showMessage(_ title: String, _ message: String?) {
	var viewController = app.window?.rootViewController
	while viewController?.presentedViewController != nil {
		viewController = viewController?.presentedViewController
	}

	let a = UIAlertController(title: title, message: message, preferredStyle: .alert)
	a.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
	viewController?.present(a, animated: true, completion: nil)
}
