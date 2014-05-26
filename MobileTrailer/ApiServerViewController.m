
@interface ApiServerViewController () <UITextFieldDelegate>

@end

@implementation ApiServerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	[self loadSettings];
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	[self.navigationController setToolbarHidden:NO animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.navigationController setToolbarHidden:YES animated:YES];
}

- (void)loadSettings
{
	self.apiFrontEnd.text = [Settings shared].apiFrontEnd;
	self.apiBackEnd.text = [Settings shared].apiBackEnd;
	self.apiPath.text = [Settings shared].apiPath;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	if([string isEqualToString:@"\n"])
	{
		if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
		{
			[UIView animateWithDuration:0.3
								  delay:0.0
								options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionBeginFromCurrentState
							 animations:^{
								 for(UIView *v in self.view.subviews)
									 v.transform = CGAffineTransformIdentity;
							 } completion:^(BOOL finished) {

							 }];
		}
		[textField resignFirstResponder];
		return NO;
	}
	return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
	NSString *frontEnd = self.apiFrontEnd.text;
	NSString *backEnd = self.apiBackEnd.text;
	NSString *path = self.apiPath.text;

	NSCharacterSet *cs = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	frontEnd = [frontEnd stringByTrimmingCharactersInSet:cs];
	backEnd = [backEnd stringByTrimmingCharactersInSet:cs];
	path = [path stringByTrimmingCharactersInSet:cs];

	if(frontEnd.length==0) frontEnd = nil;
	if(backEnd.length==0) backEnd = nil;
	if(path.length==0) path = nil;

	[Settings shared].apiFrontEnd = frontEnd;
	[Settings shared].apiBackEnd = backEnd;
	[Settings shared].apiPath = path;

	[AppDelegate shared].preferencesDirty = YES;

	return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone)
	{
		[UIView animateWithDuration:0.3
							  delay:0.0
							options:UIViewAnimationOptionCurveEaseInOut|UIViewAnimationOptionBeginFromCurrentState
						 animations:^{
							 for(UIView *v in self.view.subviews)
								 v.transform = CGAffineTransformMakeTranslation(0, -100);
						 } completion:^(BOOL finished) {

						 }];
	}
	return YES;
}

- (IBAction)iPadTestSelected:(UIBarButtonItem *)sender { [self testApi]; }
- (IBAction)iPadDefaultsSelected:(UIBarButtonItem *)sender { [self restoreDefaults]; }
- (IBAction)iPhoneTestSelected:(UIBarButtonItem *)sender { [self testApi]; }
- (IBAction)iPhoneDefaultsSelected:(UIBarButtonItem *)sender { [self restoreDefaults]; }

- (void)restoreDefaults
{
	[Settings shared].apiBackEnd = nil;
	[Settings shared].apiFrontEnd = nil;
	[Settings shared].apiPath = nil;
	[self loadSettings];
}

- (void)testApi
{
	self.testApiButton.enabled = NO;
	self.restoreDefaultsButton.enabled = NO;
	[[AppDelegate shared].api testApiAndCallback:^(NSError *error) {

		self.testApiButton.enabled = YES;
		self.restoreDefaultsButton.enabled = YES;

		if(error)
		{
			[[[UIAlertView alloc] initWithTitle:@"Failed"
										message:[NSString stringWithFormat:@"The test failed for https://%@/%@",[Settings shared].apiBackEnd,[Settings shared].apiPath]
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
		}
		else
		{
			[[[UIAlertView alloc] initWithTitle:@"Success"
										message:@"The API server is OK!"
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
		}
	}];
}

@end
