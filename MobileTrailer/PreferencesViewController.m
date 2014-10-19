
@interface PreferencesViewController () <UITextFieldDelegate,
NSFetchedResultsControllerDelegate, UIActionSheetDelegate>
{
	NSString *targetUrl;

	// Filtering
    UITextField *searchField;
    HTPopTimer *searchTimer;
}
@end

@implementation PreferencesViewController

- (IBAction)ipadDone:(UIBarButtonItem *)sender {
	if(app.preferencesDirty) [app startRefresh];
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

    UIView *searchHolder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 41)];
	[searchHolder addSubview:searchField];
	searchHolder.autoresizesSubviews = YES;
	searchHolder.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.repositories.tableHeaderView = searchHolder;

    self.repositories.contentOffset = CGPointMake(0, searchHolder.frame.size.height);

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiUsageUpdate) name:API_USAGE_UPDATE object:nil];

	self.githubApiToken.text = settings.authToken;
	self.refreshRepoList.enabled = (settings.authToken.length>0);

	[self.repositories reloadData];

	[self apiUsageUpdate];

	[self updateInstructionMode];
}

- (void)instructionMode:(BOOL)instructionMode
{
	self.repositories.hidden = instructionMode;
	self.instructionLabel.hidden = !instructionMode;
	self.createTokenButton.hidden = !instructionMode;
	self.viewTokensButton.hidden = !instructionMode;
	self.watchListButton.enabled = (self.fetchedResultsController.fetchedObjects.count>0);
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)apiUsageUpdate
{
	API *api = app.api;
	if(api.requestsLimit==0 && api.requestsRemaining==0)
		[self.apiLoad setProgress:0.0];
	else
		[self.apiLoad setProgress:(api.requestsLimit-api.requestsRemaining)/api.requestsLimit];
}

- (void)commitToken
{
	settings.authToken = [self.githubApiToken.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	self.refreshRepoList.enabled = (settings.authToken.length>0);
	[self.githubApiToken resignFirstResponder];
}

- (void)resetData
{
	if([Repo countItemsOfType:@"Repo" inMoc:app.dataManager.managedObjectContext])
	{
		CGRect frame = self.githubApiToken.frame;
		frame = CGRectOffset(frame, 0, frame.size.height);
		UILabel *pleaseWaitLabel = [[UILabel alloc] initWithFrame:frame];
		pleaseWaitLabel.text = @"Clearing database - Just a moment...";
		pleaseWaitLabel.backgroundColor = [UIColor whiteColor];
		pleaseWaitLabel.font = [UIFont systemFontOfSize:16.0];
		pleaseWaitLabel.textAlignment = NSTextAlignmentCenter;
		pleaseWaitLabel.textColor = [UIColor redColor];
		[self.view addSubview:pleaseWaitLabel];

		double delayInSeconds = 0.01;
		dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
		dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
			app.preferencesDirty = YES;
			app.lastSuccessfulRefresh = nil;
			[app.dataManager deleteEverything];
			app.api.requestsLimit = 0;
			app.api.requestsRemaining = 0;
			[self apiUsageUpdate];
			[pleaseWaitLabel removeFromSuperview];
		});
	}
}

- (IBAction)ipadLoadRepos:(UIBarButtonItem *)sender
{
	if(self.githubApiToken.isFirstResponder)
	{
		[self commitToken];
	}

	NSString *originalName = self.refreshRepoList.title;
	self.refreshRepoList.title = @"Loading...";
	[self instructionMode:NO];
	self.refreshRepoList.enabled = NO;
	self.repositories.hidden = YES;
	self.githubApiToken.hidden = YES;

	[app.api fetchRepositoriesAndCallback:^(BOOL success) {

		self.refreshRepoList.title = originalName;
		self.refreshRepoList.enabled = YES;
		self.repositories.hidden = NO;
		self.githubApiToken.hidden = NO;

		app.preferencesDirty = YES;

		[self updateInstructionMode];

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
	BOOL hideNow = !repo.hidden.boolValue;
	repo.hidden = @(hideNow);
	repo.dirty = @(!hideNow);
	[app.dataManager saveDB];
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	app.preferencesDirty = YES;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	NSString *title;
	if(settings.localUser)
		title = settings.localUser;
	else
		title = @"";

	if(section==1)
	{
		title = [title stringByAppendingString:@" - Forked Repos"];
	}
	else
	{
		Repo *repo = [self.fetchedResultsController objectAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
		if(repo.fork.boolValue)
		{
			title = [title stringByAppendingString:@" - Forked Repos"];
		}
		else
		{
			title = [title stringByAppendingString:@" - Parent Repos"];
		}
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
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Repo" inManagedObjectContext:app.dataManager.managedObjectContext];
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
																								managedObjectContext:app.dataManager.managedObjectContext
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

		default:
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
	cell.textLabel.text = repo.inaccessible.boolValue ? [repo.fullName stringByAppendingString:@" (inaccessible)"] : repo.fullName;
	if(repo.hidden.boolValue)
	{
		cell.accessoryView = [self makeX];
		cell.textLabel.textColor = [UIColor lightGrayColor];
		cell.accessibilityLabel = [NSString stringWithFormat:@"Hidden: %@", cell.textLabel.text];
	}
	else
	{
		cell.accessoryView = nil;
		cell.textLabel.textColor = [UIColor darkTextColor];
		cell.accessibilityLabel = cell.textLabel.text;
	}
}

- (UIView *)makeX
{
	UILabel *x = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 16, 16)];
	x.textColor = [UIColor redColor];
	x.font = [UIFont systemFontOfSize:14.0];
	x.text = @"X";
	return x;
}

- (IBAction)ipadCreateToken:(UIButton *)sender
{
	targetUrl = [NSString stringWithFormat:@"https://%@/settings/tokens/new",settings.apiFrontEnd];
	[self performSegueWithIdentifier:@"openGithub" sender:self];
}

- (IBAction)ipadViewTokens:(UIButton *)sender
{
	targetUrl = [NSString stringWithFormat:@"https://%@/settings/applications",settings.apiFrontEnd];
	[self performSegueWithIdentifier:@"openGithub" sender:self];
}

- (IBAction)ipadWatchlistSelected:(UIBarButtonItem *)sender {
	UIActionSheet *a = [[UIActionSheet alloc] initWithTitle:@"Watchlist"
												   delegate:self
										  cancelButtonTitle:@"Cancel"
									 destructiveButtonTitle:@"Visit Watchlist"
										  otherButtonTitles:@"Hide All",@"Show All",nil];
	[a showFromBarButtonItem:self.watchListButton animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if(buttonIndex==3) return;

	switch (buttonIndex)
	{
		case 0:
		{
			targetUrl = [NSString stringWithFormat:@"https://%@/watching",settings.apiFrontEnd];
			[self performSegueWithIdentifier:@"openGithub" sender:self];
			break;
		}
		case 1:
		{
			NSArray *allRepos = self.fetchedResultsController.fetchedObjects;
			for(Repo *r in allRepos) { r.hidden = @YES; r.dirty = @NO; }
			break;
		}
		case 2:
		{
			NSArray *allRepos = self.fetchedResultsController.fetchedObjects;
			for(Repo *r in allRepos) { r.hidden = @NO; r.dirty = @YES; r.lastDirtied = [NSDate date]; }
			break;
		}
	}

	app.preferencesDirty = YES;
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
	NSIndexSet *currentIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _fetchedResultsController.sections.count)];

	_fetchedResultsController = nil;
	self.watchListButton.enabled = (self.fetchedResultsController.fetchedObjects.count>0);

	NSIndexSet *dataIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _fetchedResultsController.sections.count)];

	NSIndexSet *removedIndexes = [currentIndexes indexesPassingTest:^BOOL(NSUInteger idx, BOOL *stop) {
		return ![dataIndexes containsIndex:idx];
	}];
	NSIndexSet *addedIndexes = [dataIndexes indexesPassingTest:^BOOL(NSUInteger idx, BOOL *stop) {
		return ![currentIndexes containsIndex:idx];
	}];

	NSIndexSet *untouchedIndexes = [dataIndexes indexesPassingTest:^BOOL(NSUInteger idx, BOOL *stop) {
		return !([removedIndexes containsIndex:idx] || [addedIndexes containsIndex:idx]);
	}];

	[self.repositories beginUpdates];

	if(removedIndexes.count)
		[self.repositories deleteSections:removedIndexes withRowAnimation:UITableViewRowAnimationAutomatic];

	if(untouchedIndexes.count)
		[self.repositories reloadSections:untouchedIndexes withRowAnimation:UITableViewRowAnimationAutomatic];

	if(addedIndexes.count)
		[self.repositories insertSections:addedIndexes withRowAnimation:UITableViewRowAnimationAutomatic];

	[self.repositories endUpdates];
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
	[searchTimer push];
	return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	if(textField==self.githubApiToken)
	{
		self.repositories.hidden = YES;
	}
	return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
	if(textField==self.githubApiToken)
	{
		[self updateInstructionMode];
	}
}

- (void)updateInstructionMode
{
	[self instructionMode:([Repo countItemsOfType:@"Repo" inMoc:app.dataManager.managedObjectContext]==0 || self.githubApiToken.text.length==0)];
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
			app.preferencesDirty = YES;
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
