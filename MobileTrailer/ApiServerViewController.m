
@interface ApiServerViewController () <UITextFieldDelegate>
{
	__weak UITextField *focusedField;
	__weak IBOutlet UIScrollView *_scrollView;
}
@end

@implementation ApiServerViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	[self loadSettings];

	NSNotificationCenter *n = [NSNotificationCenter defaultCenter];
	[n addObserver:self selector:@selector(keyboardWasShown:) name:UIKeyboardWillShowNotification object:nil];
	[n addObserver:self selector:@selector(keyboardWillBeHidden:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)keyboardWasShown:(NSNotification*)aNotification
{
	NSDictionary* info = [aNotification userInfo];
	CGSize kbSize = [[info objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue].size;
	UIEdgeInsets contentInsets = UIEdgeInsetsMake(0.0, 0.0, kbSize.height, 0.0);
	_scrollView.contentInset = contentInsets;
	_scrollView.scrollIndicatorInsets = contentInsets;

	CGRect aRect = self.view.frame;
	aRect.size.height -= kbSize.height;
	if(!CGRectContainsPoint(aRect, focusedField.frame.origin))
	{
		CGPoint scrollPoint = CGPointMake(0.0, focusedField.frame.origin.y-kbSize.height);
		[_scrollView setContentOffset:scrollPoint animated:YES];
	}
}

- (void)keyboardWillBeHidden:(NSNotification*)aNotification
{
	UIEdgeInsets contentInsets = UIEdgeInsetsZero;
	_scrollView.contentInset = contentInsets;
	_scrollView.scrollIndicatorInsets = contentInsets;
}

- (void)keyboardWillHide:(NSNotification *)n
{
	self.view.transform = CGAffineTransformIdentity;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
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
	self.apiFrontEnd.text = settings.apiFrontEnd;
	self.apiBackEnd.text = settings.apiBackEnd;
	self.apiPath.text = settings.apiPath;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	if([string isEqualToString:@"\n"])
	{
		[textField resignFirstResponder];
		return NO;
	}
	return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	focusedField = textField;
	return YES;
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
	focusedField = nil;

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

	settings.apiFrontEnd = frontEnd;
	settings.apiBackEnd = backEnd;
	settings.apiPath = path;

	app.preferencesDirty = YES;

	return YES;
}

- (IBAction)iPadTestSelected:(UIBarButtonItem *)sender
{
	self.testApiButton.enabled = NO;
	self.restoreDefaultsButton.enabled = NO;
	[app.api testApiAndCallback:^(NSError *error) {

		self.testApiButton.enabled = YES;
		self.restoreDefaultsButton.enabled = YES;

		if(error)
		{
			[[[UIAlertView alloc] initWithTitle:@"Failed"
										message:[NSString stringWithFormat:@"The test failed for https://%@/%@",settings.apiBackEnd,settings.apiPath]
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
- (IBAction)iPadDefaultsSelected:(UIBarButtonItem *)sender
{
	settings.apiBackEnd = nil;
	settings.apiFrontEnd = nil;
	settings.apiPath = nil;
	[self loadSettings];
}

@end
