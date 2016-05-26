
import UIKit

let popupManager = PopupManager()

final class PopupManager: NSObject, UISplitViewControllerDelegate {

	/////////////// Popovers

	func showPopoverFromViewController(parentViewController: UIViewController, fromItem: UIBarButtonItem, viewController: UIViewController) {
		if UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Pad {
			viewController.modalPresentationStyle = UIModalPresentationStyle.Popover
			parentViewController.presentViewController(viewController, animated: true, completion: nil)
			viewController.popoverPresentationController?.barButtonItem = fromItem
		} else {
			viewController.modalPresentationStyle = UIModalPresentationStyle.CurrentContext
			let v = (parentViewController.tabBarController ?? parentViewController.navigationController) ?? parentViewController
			v.presentViewController(viewController, animated: true, completion: nil)
		}
	}

	/////////////// Sharing

	func shareFromView(view: UIViewController, buttonItem: UIBarButtonItem, url: NSURL) {
		let a = OpenInSafariActivity()
		let v = UIActivityViewController(activityItems: [url], applicationActivities:[a])
		showPopoverFromViewController(view, fromItem: buttonItem, viewController: v)
	}

	////////////// Master view

	func getMasterController() -> MasterViewController {
		let s = app.window!.rootViewController as! UISplitViewController
		return (s.viewControllers.first as! UINavigationController).viewControllers.first as! MasterViewController
	}

	func splitViewController(splitViewController: UISplitViewController, collapseSecondaryViewController secondaryViewController: UIViewController, ontoPrimaryViewController primaryViewController: UIViewController) -> Bool {
		let d = (secondaryViewController as! UINavigationController).viewControllers.first as! DetailViewController
		return d.detailItem==nil
	}

	func splitViewController(splitViewController: UISplitViewController, separateSecondaryViewControllerFromPrimaryViewController primaryViewController: UIViewController) -> UIViewController? {
		return nil
	}
}

func showMessage(title: String, _ message: String?) {
	var viewController = app.window?.rootViewController
	while viewController?.presentedViewController != nil {
		viewController = viewController?.presentedViewController
	}

	let a = UIAlertController(title: title, message: message, preferredStyle: .Alert)
	a.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
	viewController?.presentViewController(a, animated: true, completion: nil)
}
