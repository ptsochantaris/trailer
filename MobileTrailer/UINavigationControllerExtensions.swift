
extension UINavigationController {
	func disablesAutomaticKeyboardDismissal -> Bool {
		return self.topViewController.disablesAutomaticKeyboardDismissal()
	}
}
