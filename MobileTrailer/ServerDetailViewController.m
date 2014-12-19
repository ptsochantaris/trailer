#import "ServerDetailViewController.h"

@implementation ServerDetailViewController
{
	NSString *targetUrl;
	UITextField *focusedField;
}

- (void)viewDidLoad
{
	[super viewDidLoad];
	ApiServer *a;
	if(self.serverId)
	{
		a = (ApiServer *)[DataManager.managedObjectContext existingObjectWithID:self.serverId error:nil];
	}
	else
	{
		a = [ApiServer addDefaultGithubInMoc:DataManager.managedObjectContext];
		[DataManager.managedObjectContext save:nil];
		self.serverId = a.objectID;
	}
	self.name.text = a.label;
	self.apiPath.text = a.apiPath;
	self.webFrontEnd.text = a.webPath;
	self.authToken.text = a.authToken;
	self.reportErrors.on = a.reportRefreshFailures.boolValue;

	if(UI_USER_INTERFACE_IDIOM()!=UIUserInterfaceIdiomPad)
	{
		NSNotificationCenter *n = [NSNotificationCenter defaultCenter];
		[n addObserver:self selector:@selector(keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
		[n addObserver:self selector:@selector(keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
	}
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self.navigationController setToolbarHidden:NO animated:YES];
	[self processTokenStateFrom:self.authToken.text];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.navigationController setToolbarHidden:YES animated:YES];
}

- (IBAction)testConnectionSelected:(UIButton *)sender
{
	sender.enabled = NO;
	[api testApiToServer:[self updateServerFromForm]
			 andCallback:^(NSError *error) {
				 sender.enabled = YES;
				 [[[UIAlertView alloc] initWithTitle:error ? @"Failed" : @"Success"
											 message:error ? error.localizedDescription : nil
											delegate:nil
								   cancelButtonTitle:@"OK"
								   otherButtonTitles:nil] show];
			 }];
}

- (ApiServer *)updateServerFromForm
{
	ApiServer *a = (ApiServer *)[DataManager.managedObjectContext existingObjectWithID:self.serverId error:nil];
	a.label = [self.name.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	a.apiPath = [self.apiPath.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	a.webPath = [self.webFrontEnd.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	a.authToken = [self.authToken.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	a.reportRefreshFailures = @(self.reportErrors.on);
	a.lastSyncSucceeded = @YES;
	app.preferencesDirty = YES;

	[self processTokenStateFrom:a.authToken];
	return a;
}

- (void)processTokenStateFrom:(NSString *)tokenText
{
	if(tokenText.length==0)
	{
		self.authTokenLabel.textColor =  [UIColor redColor];
		self.testButton.enabled = NO;
		self.testButton.alpha = 0.6;
	}
	else
	{
		self.authTokenLabel.textColor =  [UIColor blackColor];
		self.testButton.enabled = YES;
		self.testButton.alpha = 1.0;
	}
}

- (IBAction)reportChanged:(UISwitch *)sender
{
	[self updateServerFromForm];
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
	[self updateServerFromForm];
	return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	focusedField = textField;
	return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	if([string isEqualToString:@"\n"])
	{
		[textField resignFirstResponder];
		return NO;
	}
	if(textField==self.authToken)
	{
		NSString *newToken = [textField.text stringByReplacingCharactersInRange:range withString:string];
		[self processTokenStateFrom:newToken];
	}
	return YES;
}

- (IBAction)watchListSelected:(UIBarButtonItem *)sender
{
	NSURL *u = [self checkForValidPath];
	if(u)
	{
		targetUrl = [NSString stringWithFormat:@"%@/watching",u.absoluteString];
		[self performSegueWithIdentifier:@"openGithub" sender:self];
	}
}

- (IBAction)createTokenSelected:(UIBarButtonItem *)sender
{
	NSURL *u = [self checkForValidPath];
	if(u)
	{
		targetUrl = [NSString stringWithFormat:@"%@/settings/tokens/new",u.absoluteString];
		[self performSegueWithIdentifier:@"openGithub" sender:self];
	}
}

- (IBAction)existingTokensSelected:(UIBarButtonItem *)sender
{
	NSURL *u = [self checkForValidPath];
	if(u)
	{
		targetUrl = [NSString stringWithFormat:@"%@/settings/applications",u.absoluteString];
		[self performSegueWithIdentifier:@"openGithub" sender:self];
	}
}

- (NSURL *)checkForValidPath
{
	NSURL *u = [NSURL URLWithString:self.webFrontEnd.text];
	if(u)
	{
		return u;
	}
	else
	{
		[[[UIAlertView alloc] initWithTitle:@"Need a valid web server"
									message:@"Please specify a valid URL for the 'Web Front End' for this server in order to visit it"
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
		return nil;
	}
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	if([segue.destinationViewController isKindOfClass:[GithubViewController class]])
	{
		((GithubViewController *)segue.destinationViewController).pathToLoad = targetUrl;
	}
	else if([segue.destinationViewController isKindOfClass:[UINavigationController class]])
	{
		((GithubViewController *)[segue.destinationViewController topViewController]).pathToLoad = targetUrl;
	}
	targetUrl = nil;
}

- (IBAction)deleteSelected:(UIBarButtonItem *)sender
{
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Delete API Server"
																message:@"Are you sure you want to remove this API server from your list?"
														 preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"Cancel"
										  style:UIAlertActionStyleCancel
										handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"Delete"
										  style:UIAlertActionStyleDestructive
										handler:^(UIAlertAction *action) {
											[self deleteServer];
										}]];

	[self presentViewController:a animated:YES completion:nil];
}

- (void)deleteServer
{
	ApiServer *a = (ApiServer *)[DataManager.managedObjectContext existingObjectWithID:self.serverId error:nil];
	if(a) [DataManager.managedObjectContext deleteObject:a];
	[DataManager saveDB];
	[self.navigationController popViewControllerAnimated:YES];
}

///////////////////////// keyboard

- (void)keyboardWillShow:(NSNotification *)notification
{
	CGRect keyboardFrame = [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGFloat keyboardHeight = MAX(0, self.view.bounds.size.height-keyboardFrame.origin.y);
	CGRect firstResponderFrame = [self.view convertRect:focusedField.frame fromView:focusedField.superview];
	CGFloat bottomOfFirstResponder = firstResponderFrame.origin.y+firstResponderFrame.size.height;
	bottomOfFirstResponder += 36.0;

	CGFloat topOfKeyboard = self.view.bounds.size.height-keyboardHeight;
	if(bottomOfFirstResponder>topOfKeyboard)
	{
		CGFloat distance = (bottomOfFirstResponder-topOfKeyboard);
		_scrollView.contentOffset = CGPointMake(0, _scrollView.contentOffset.y+distance);
	}
}

- (void)keyboardWillHide:(NSNotification *)notification
{
	if(!_scrollView.isDragging)
	{
		[_scrollView scrollRectToVisible:CGRectMake(0,
													MIN(_scrollView.contentOffset.y, _scrollView.contentSize.height-_scrollView.bounds.size.height),
													_scrollView.bounds.size.width,
													_scrollView.bounds.size.height)
								animated:NO];
	}
}

@end
