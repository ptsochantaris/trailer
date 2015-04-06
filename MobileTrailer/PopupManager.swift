
import UIKit

let popupManager = PopupManager()

class PopupManager: NSObject, UIPopoverControllerDelegate, UISplitViewControllerDelegate {

	private var currentPopover: UIPopoverController?

	/////////////// Popovers

	func showPopoverFromViewController(parentViewController: UIViewController, fromItem: UIBarButtonItem, viewController: UIViewController) {
		if UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Pad {
			viewController.modalPresentationStyle = UIModalPresentationStyle.Popover
			currentPopover = UIPopoverController(contentViewController: viewController)
			currentPopover!.delegate = self
			currentPopover!.presentPopoverFromBarButtonItem(fromItem, permittedArrowDirections: UIPopoverArrowDirection.Any, animated: true)
		} else {
			viewController.modalPresentationStyle = UIModalPresentationStyle.CurrentContext
			var v = parentViewController.tabBarController ?? (parentViewController.navigationController ?? parentViewController)
			v.presentViewController(viewController, animated: true, completion: nil)
		}
	}

	/////////////// Sharing

	func shareFromView(view: UIViewController, buttonItem: UIBarButtonItem, url: NSURL) {
		let a = OpenInSafariActivity()
		let v = UIActivityViewController(activityItems: [url], applicationActivities:[a])
		showPopoverFromViewController(view, fromItem: buttonItem, viewController: v)
	}

	func popoverControllerDidDismissPopover(popoverController: UIPopoverController) {
		currentPopover = nil
	}

	////////////// Master view

	func getMasterController() -> MasterViewController {
		let s = app.window!.rootViewController as! UISplitViewController
		return (s.viewControllers.first as! UINavigationController).viewControllers.first as! MasterViewController
	}

	func splitViewController(splitViewController: UISplitViewController, collapseSecondaryViewController secondaryViewController: UIViewController!, ontoPrimaryViewController primaryViewController: UIViewController!) -> Bool {
		let m = (primaryViewController as! UINavigationController).viewControllers.first as! MasterViewController
		m.clearsSelectionOnViewWillAppear = true
		let d = (secondaryViewController as! UINavigationController).viewControllers.first as! DetailViewController
		return d.detailItem==nil
	}

	func splitViewController(splitViewController: UISplitViewController, separateSecondaryViewControllerFromPrimaryViewController primaryViewController: UIViewController!) -> UIViewController? {
		let m = (primaryViewController as! UINavigationController).viewControllers.first as! MasterViewController
		m.clearsSelectionOnViewWillAppear = false
		return nil
	}
}