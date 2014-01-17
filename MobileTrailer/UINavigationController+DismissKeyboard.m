
@implementation UINavigationController (DismissKeyboard)

- (BOOL)disablesAutomaticKeyboardDismissal
{
	return [self.topViewController disablesAutomaticKeyboardDismissal];
}

@end
