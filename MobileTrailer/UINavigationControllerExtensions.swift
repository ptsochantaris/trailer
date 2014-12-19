
extension UINavigationController {
	override public func disablesAutomaticKeyboardDismissal() -> Bool {
		return self.topViewController.disablesAutomaticKeyboardDismissal()
	}
}
