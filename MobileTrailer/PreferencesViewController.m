
@interface PreferencesViewController () <UITextFieldDelegate,
NSFetchedResultsControllerDelegate, UIActionSheetDelegate>
{
	NSString *targetUrl;
	BOOL refreshStartedWithEmpty;
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
	if([AppDelegate shared].preferencesDirty) [[AppDelegate shared] startRefresh];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiUsageUpdate) name:RATE_UPDATE_NOTIFICATION object:nil];

	self.githubApiToken.text = [Settings shared].authToken;
	self.refreshRepoList.enabled = ([Settings shared].authToken.length>0);
	self.repositories.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];

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

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
	self.repositories.hidden = YES;
	return YES;
}

-(void)textFieldDidEndEditing:(UITextField *)textField
{
	[self instructionMode:(self.fetchedResultsController.fetchedObjects.count==0
						   || self.githubApiToken.text.length==0)];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
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
	[DataItem deleteAllObjectsInContext:[AppDelegate shared].dataManager.managedObjectContext
							 usingModel:[AppDelegate shared].dataManager.managedObjectModel];
	[[AppDelegate shared].dataManager saveDB];
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
	if([Settings shared].localUser) return [Settings shared].localUser;
	return nil;
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

    // Set the batch size to a suitable number.
    [fetchRequest setFetchBatchSize:20];

    // Edit the sort key as appropriate.
    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"fullName" ascending:YES];
    [fetchRequest setSortDescriptors:@[sortDescriptor]];

    // Edit the section name key path and cache name if appropriate.
    // nil for section name key path means "no sections".
    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
																								managedObjectContext:[AppDelegate shared].dataManager.managedObjectContext
																								  sectionNameKeyPath:nil
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

- (IBAction)iphoneSelection:(UIBarButtonItem *)sender
{
	[[self selectionSheet] showInView:self.view];
}
- (IBAction)ipadSelection:(UIBarButtonItem *)sender
{
	[[self selectionSheet] showFromBarButtonItem:sender animated:YES];
}
- (UIActionSheet *)selectionSheet
{
	return [[UIActionSheet alloc] initWithTitle:self.title
									   delegate:self
							  cancelButtonTitle:@"Cancel"
						 destructiveButtonTitle:nil
							  otherButtonTitles:@"Select All", @"Unselect All", nil];
}

- (void)actionSheet:(UIActionSheet *)actionSheet willDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if(buttonIndex==2) return;
	NSNumber *selection = @(buttonIndex==0);
	NSArray *allRepos = [Repo allReposSortedByField:nil withTitleFilter:nil inMoc:[AppDelegate shared].dataManager.managedObjectContext];
	for(Repo *r in allRepos) r.active = selection;
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
	targetUrl = @"https://github.com/settings/applications";
	[self performSegueWithIdentifier:@"openGithub" sender:self];
}

- (void)createToken
{
	targetUrl = @"https://github.com/settings/tokens/new";
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

@end
