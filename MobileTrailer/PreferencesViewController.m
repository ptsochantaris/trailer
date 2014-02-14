
@interface PreferencesViewController () <UITextFieldDelegate,
NSFetchedResultsControllerDelegate, UIActionSheetDelegate>
{
	NSString *targetUrl;
	BOOL refreshStartedWithEmpty;

	// Filtering
    UITextField *searchField;
    HTPopTimer *searchTimer;
}
@end

@implementation PreferencesViewController

- (IBAction)ipadDone:(UIBarButtonItem *)sender {
	[self done];
}
- (IBAction)iphoneDone:(UIBarButtonItem *)sender {
	[self done];
}
- (void)done
{
	[[AppDelegate shared].dataManager postProcessAllPrs]; // apply any view option changes
	if([AppDelegate shared].preferencesDirty) [[AppDelegate shared] startRefresh];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    searchTimer = [[HTPopTimer alloc] initWithTimeInterval:0.5 target:self selector:@selector(reloadData)];

    searchField = [[UITextField alloc] initWithFrame:CGRectMake(10, 10, self.view.bounds.size.width-20, 31)];
	searchField.placeholder = @"Filter...";
	searchField.returnKeyType = UIReturnKeySearch;
	searchField.font = [UIFont systemFontOfSize:18.0];
	searchField.borderStyle = UITextBorderStyleRoundedRect;
	searchField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	searchField.clearButtonMode = UITextFieldViewModeAlways;
	searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    searchField.delegate = self;
	searchField.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIView *searchHolder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 50)];
	[searchHolder addSubview:searchField];
	searchHolder.autoresizesSubviews = YES;
	searchHolder.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.repositories.tableHeaderView = searchHolder;

    self.repositories.contentOffset = CGPointMake(0, 50);

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiUsageUpdate) name:RATE_UPDATE_NOTIFICATION object:nil];

	self.githubApiToken.text = [Settings shared].authToken;
	self.refreshRepoList.enabled = ([Settings shared].authToken.length>0);

	[self.repositories reloadData];

	[self apiUsageUpdate];

	[self instructionMode:(self.fetchedResultsController.fetchedObjects.count==0
						   || self.githubApiToken.text.length==0)];
}

- (void)instructionMode:(BOOL)instructionMode
{
	self.repositories.hidden = instructionMode;
	self.instructionLabel.hidden = !instructionMode;
	self.createTokenButton.hidden = !instructionMode;
	self.viewTokensButton.hidden = !instructionMode;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)apiUsageUpdate
{
	API *api = [AppDelegate shared].api;
	[self.apiLoad setProgress:(api.requestsLimit-api.requestsRemaining)/api.requestsLimit];
}

- (void)commitToken
{
	[Settings shared].authToken = [self.githubApiToken.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	self.refreshRepoList.enabled = ([Settings shared].authToken.length>0);
	[self.githubApiToken resignFirstResponder];
}

- (void)resetData
{
	[AppDelegate shared].preferencesDirty = YES;
	[AppDelegate shared].lastSuccessfulRefresh = nil;
	[[AppDelegate shared].dataManager deleteEverything];
}

- (IBAction)ipadLoadRepos:(UIBarButtonItem *)sender
{
	[self updateRepositories];
}
- (IBAction)iphoneLoadRepos:(UIBarButtonItem *)sender
{
	[self updateRepositories];
}
- (void)updateRepositories
{
	if(self.githubApiToken.isFirstResponder)
	{
		[self commitToken];
	}

	refreshStartedWithEmpty = (self.fetchedResultsController.fetchedObjects.count==0);

	NSString *originalName = self.refreshRepoList.title;
	self.refreshRepoList.title = @"Loading...";
	[self instructionMode:NO];
	self.refreshRepoList.enabled = NO;
	self.repositories.hidden = YES;
	self.githubApiToken.hidden = YES;

	[[AppDelegate shared].api fetchRepositoriesAndCallback:^(BOOL success) {

		if(refreshStartedWithEmpty)
			for(Repo *r in self.fetchedResultsController.fetchedObjects)
				r.active = @YES;

		[self.repositories reloadData];
		self.refreshRepoList.title = originalName;
		self.refreshRepoList.enabled = YES;
		self.repositories.hidden = NO;
		self.githubApiToken.hidden = NO;

		[AppDelegate shared].preferencesDirty = YES;

		[self instructionMode:(self.fetchedResultsController.fetchedObjects.count==0
							   || self.githubApiToken.text.length==0)];

		if(!success)
		{
			[[[UIAlertView alloc] initWithTitle:@"Error"
										message:@"Could not refresh repository list, please ensure that the token you are using is valid"
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];
		}
	}];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	return [[self.fetchedResultsController sections] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedResultsController sections][section];
	return [sectionInfo numberOfObjects];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
	[self configureCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	Repo *repo = [self.fetchedResultsController objectAtIndexPath:indexPath];
	repo.active = @(!repo.active.boolValue);
	[[AppDelegate shared].dataManager saveDB];
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	[AppDelegate shared].preferencesDirty = YES;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	NSString *title;
	if([Settings shared].localUser)
		title = [Settings shared].localUser;
	else
		title = @"";

	switch (section) {
		case 0:
			title = [title stringByAppendingString:@" - Parent Repos"];
			break;
		default:
			title = [title stringByAppendingString:@" - Forked Repos"];
			break;
	}

	return title;
}

#pragma mark - Fetched results controller

- (NSFetchedResultsController *)fetchedResultsController
{
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    // Edit the entity name as appropriate.
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Repo" inManagedObjectContext:[AppDelegate shared].dataManager.managedObjectContext];
    [fetchRequest setEntity:entity];

	if(searchField.text.length)
		fetchRequest.predicate = [NSPredicate predicateWithFormat:@"fullName contains [cd] %@",searchField.text];

    // Set the batch size to a suitable number.
    [fetchRequest setFetchBatchSize:20];

    // Edit the sort key as appropriate.
    [fetchRequest setSortDescriptors:@[[[NSSortDescriptor alloc] initWithKey:@"fork" ascending:YES],
									   [[NSSortDescriptor alloc] initWithKey:@"fullName" ascending:YES]]];

    // Edit the section name key path and cache name if appropriate.
    // nil for section name key path means "no sections".
    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
																								managedObjectContext:[AppDelegate shared].dataManager.managedObjectContext
																								  sectionNameKeyPath:@"fork"
																										   cacheName:nil];
    aFetchedResultsController.delegate = self;
    self.fetchedResultsController = aFetchedResultsController;

	NSError *error = nil;
	if (![self.fetchedResultsController performFetch:&error]) {
		// Replace this implementation with code to handle the error appropriately.
		// abort() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
	    NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
	    abort();
	}

    return _fetchedResultsController;
}

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    [self.repositories beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type
{
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [self.repositories insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeDelete:
            [self.repositories deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath
{
    UITableView *tableView = self.repositories;

    switch(type) {
        case NSFetchedResultsChangeInsert:
            [tableView insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeDelete:
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeUpdate:
			if(newIndexPath)
				[self configureCell:[tableView cellForRowAtIndexPath:indexPath] atIndexPath:newIndexPath];
			else
				[self configureCell:[tableView cellForRowAtIndexPath:indexPath] atIndexPath:indexPath];
            break;

        case NSFetchedResultsChangeMove:
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            [tableView insertRowsAtIndexPaths:@[newIndexPath] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
    [self.repositories endUpdates];
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    Repo *repo = [self.fetchedResultsController objectAtIndexPath:indexPath];
    cell.textLabel.text = repo.fullName;
	if(repo.active.boolValue)
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	else
		cell.accessoryType = UITableViewCellAccessoryNone;
}

- (IBAction)iphoneSelection:(UIBarButtonItem *)sender {
	[self showSelectionOptions:sender];
}
- (IBAction)ipadSelection:(UIBarButtonItem *)sender {
	[self showSelectionOptions:sender];
}
- (void)showSelectionOptions:(UIBarButtonItem *)sender
{
	UIActionSheet *selectionSheet = [[UIActionSheet alloc] initWithTitle:self.title
																delegate:self
													   cancelButtonTitle:@"Cancel"
												  destructiveButtonTitle:nil
													   otherButtonTitles:@"Select All", @"Select All Parents", @"Unselect All", nil];
	[selectionSheet showFromBarButtonItem:sender animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet willDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if(buttonIndex==3) return;
	NSArray *allRepos = self.fetchedResultsController.fetchedObjects;
	switch (buttonIndex) {
		case 0:
		{
			for(Repo *r in allRepos) r.active = @YES;
			break;
		}
		case 1:
		{
			for(Repo *r in allRepos) if(!r.fork.boolValue) r.active = @YES;
			break;
		}
		case 2:
		{
			for(Repo *r in allRepos) r.active = @NO;
			break;
		}
	}
	[AppDelegate shared].preferencesDirty = YES;
}

- (IBAction)iphoneCreateToken:(UIButton *)sender {
	[self createToken];
}
- (IBAction)iphoneVieTokens:(UIButton *)sender {
	[self viewTokens];
}
- (IBAction)ipadCreateToken:(UIButton *)sender {
	[self createToken];
}
- (IBAction)ipadViewTokens:(UIButton *)sender {
	[self viewTokens];
}

- (void)viewTokens
{
	targetUrl = [NSString stringWithFormat:@"https://%@/settings/applications",[Settings shared].apiFrontEnd];
	[self performSegueWithIdentifier:@"openGithub" sender:self];
}

- (void)createToken
{
	targetUrl = [NSString stringWithFormat:@"https://%@/settings/tokens/new",[Settings shared].apiFrontEnd];
	[self performSegueWithIdentifier:@"openGithub" sender:self];
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

///////////////////////////// filtering

- (void)reloadData
{
	self.fetchedResultsController = nil;
	[self.repositories reloadData];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if(searchField.isFirstResponder)
    {
        [searchField resignFirstResponder];
    }
}

- (BOOL)textFieldShouldClear:(UITextField *)textField
{
	textField.text = nil;
	[self reloadData];
	return NO;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	if(textField==self.githubApiToken)
	{
		self.repositories.hidden = YES;
	}
	return YES;
}

-(void)textFieldDidEndEditing:(UITextField *)textField
{
	if(textField==self.githubApiToken)
	{
		[self instructionMode:(self.fetchedResultsController.fetchedObjects.count==0
							   || self.githubApiToken.text.length==0)];
	}
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	if(textField==self.githubApiToken)
	{
		if([string isEqualToString:@"\n"])
		{
			[self commitToken];
			return NO;
		}
		else
		{
			[AppDelegate shared].preferencesDirty = YES;
			[self resetData];
			return YES;
		}
	}
	else
	{
		if([string isEqualToString:@"\n"])
		{
			[textField resignFirstResponder];
		}
		else
		{
			[searchTimer push];
		}
		return YES;
	}
}

@end
