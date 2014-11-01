
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
		a = (ApiServer *)[app.dataManager.managedObjectContext existingObjectWithID:self.serverId error:nil];
	}
	else
	{
		a = [ApiServer addDefaultGithubInMoc:app.dataManager.managedObjectContext];
		[app.dataManager.managedObjectContext save:nil];
		self.serverId = a.objectID;
	}
	self.name.text = a.label;
	self.apiPath.text = a.apiPath;
	self.webFrontEnd.text = a.webPath;
	self.authToken.text = a.authToken;
	self.reportErrors.on = a.reportRefreshFailures.boolValue;

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

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	[self.navigationController setToolbarHidden:NO animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
	[self.navigationController setToolbarHidden:YES animated:YES];
}

- (IBAction)testConnectionSelected:(UIButton *)sender
{
	sender.enabled = NO;
	[app.api testApiToServer:[self updateServerFromForm]
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
	ApiServer *a = (ApiServer *)[app.dataManager.managedObjectContext existingObjectWithID:self.serverId error:nil];
	a.label = [self.name.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	a.apiPath = [self.apiPath.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	a.webPath = [self.webFrontEnd.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	a.authToken = [self.authToken.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	a.reportRefreshFailures = @(self.reportErrors.on);
	a.lastSyncSucceeded = @YES;
	app.preferencesDirty = YES;
	return a;
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
	ApiServer *a = (ApiServer *)[app.dataManager.managedObjectContext existingObjectWithID:self.serverId error:nil];
	if(a) [app.dataManager.managedObjectContext deleteObject:a];
	[app.dataManager saveDB];
	[self.navigationController popViewControllerAnimated:YES];
}

@end
