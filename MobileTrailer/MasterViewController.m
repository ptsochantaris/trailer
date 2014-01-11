
@interface MasterViewController () <UITextFieldDelegate, UIActionSheetDelegate>
{
    // Filtering
    UITextField *searchField;
    HTPopTimer *searchTimer;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;

@end

@implementation MasterViewController

- (void)awakeFromNib
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
	    self.clearsSelectionOnViewWillAppear = NO;
	    self.preferredContentSize = CGSizeMake(320.0, 600.0);
	}
    [super awakeFromNib];
}

- (IBAction)phoneRefreshSelected:(UIBarButtonItem *)sender {
	[self showAction];
}
- (IBAction)ipadRefreshSelected:(id)sender {
	[self showAction];
}

- (void)showAction
{
	UIActionSheet *a = [[UIActionSheet alloc] initWithTitle:@"Action"
												   delegate:self
										  cancelButtonTitle:@"Cancel"
									 destructiveButtonTitle:@"Mark all as read"
										  otherButtonTitles:@"Refresh Now", nil];
	[a showFromBarButtonItem:self.navigationItem.rightBarButtonItem animated:YES];
}

- (void)actionSheet:(UIActionSheet *)actionSheet willDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if(buttonIndex==0)
	{
		[self markAllAsRead];
	}
	else if(buttonIndex==1)
	{
		[self tryRefresh];
	}
}

- (void)tryRefresh
{
	if([[AppDelegate shared].api.reachability currentReachabilityStatus]==NotReachable)
	{
		[[[UIAlertView alloc] initWithTitle:@"No Network"
									message:@"There is no network connectivity, please try again later"
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
	}
	else
	{
		[[AppDelegate shared] startRefresh];
	}
}

- (void)markAllAsRead
{
	for(PullRequest *p in self.fetchedResultsController.fetchedObjects) [p catchUpWithComments];
	[[AppDelegate shared] updateBadge];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    searchTimer = [[HTPopTimer alloc] initWithTimeInterval:0.5 target:self selector:@selector(reloadData)];

    searchField = [[UITextField alloc] initWithFrame:CGRectMake(10, 10, 300, 31)];
	searchField.placeholder = @"Filter...";
	searchField.returnKeyType = UIReturnKeySearch;
	searchField.font = [UIFont systemFontOfSize:18.0];
	searchField.borderStyle = UITextBorderStyleRoundedRect;
	searchField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	searchField.clearButtonMode = UITextFieldViewModeAlways;
	searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    searchField.delegate = self;

    UIView *searchHolder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 50)];
	[searchHolder addSubview:searchField];
	self.tableView.tableHeaderView = searchHolder;

    self.tableView.contentOffset = CGPointMake(0, 50);

	self.detailViewController = (DetailViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(refreshStarted)
												 name:REFRESH_STARTED_NOTIFICATION
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(refreshEnded)
												 name:REFRESH_ENDED_NOTIFICATION
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(localNotification:)
												 name:RECEIVED_NOTIFICATION_KEY
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(reloadData)
												 name:DISPLAY_OPTIONS_UPDATED_KEY
											   object:nil];
}

- (void)reloadData
{
	_fetchedResultsController = nil;
	[self.tableView reloadData];
}

- (void)localNotification:(NSNotification *)notification
{
	//DLog(@"local notification: %@",notification.userInfo);

	NSManagedObjectContext *mainMoc = [AppDelegate shared].dataManager.managedObjectContext;

	NSString *urlToOpen = notification.userInfo[NOTIFICATION_URL_KEY];
	if(!urlToOpen)
	{
		NSNumber *itemId = notification.userInfo[PULL_REQUEST_ID_KEY];
		PullRequest *pullRequest = nil;
		if(itemId) // it's a pull request
		{
			pullRequest = [PullRequest itemOfType:@"PullRequest" serverId:itemId moc:mainMoc];
			urlToOpen = pullRequest.webUrl;
		}
		else // it's a comment
		{
			itemId = notification.userInfo[COMMENT_ID_KEY];
			PRComment *c = [PRComment itemOfType:@"PRComment" serverId:itemId moc:mainMoc];
			urlToOpen = c.webUrl;
			pullRequest = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:mainMoc];
		}
		double delayInSeconds = 0.1;
		dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
		dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
			[pullRequest catchUpWithComments];
			[[AppDelegate shared] updateBadge];
		});

        searchField.text = nil;
        [self reloadData];
		NSIndexPath *ip = [_fetchedResultsController indexPathForObject:pullRequest];
		if(ip)
		{
			[self.tableView selectRowAtIndexPath:ip animated:YES scrollPosition:UITableViewScrollPositionMiddle];
		}
	}

	if(urlToOpen) self.detailViewController.detailItem = [NSURL URLWithString:urlToOpen];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refreshStarted
{
	self.refreshButton.enabled = NO;
	self.title = @"Refreshing...";
}

- (void)refreshEnded
{
	self.refreshButton.enabled = YES;
	self.title = @"Pull Requests";
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
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        PullRequest *object = [[self fetchedResultsController] objectAtIndexPath:indexPath];
        self.detailViewController.detailItem = [NSURL URLWithString:object.webUrl];
		double delayInSeconds = 0.1;
		dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
		dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
			[object catchUpWithComments];
			[[AppDelegate shared] updateBadge];
		});
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedResultsController sections][section];
	return sectionInfo.name;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    PullRequest *pr = [self.fetchedResultsController objectAtIndexPath:indexPath];
	CGFloat w = 208;
	if([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) w = 227;

	return [pr.title boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
								  options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
							   attributes:@{ NSFontAttributeName:[UIFont systemFontOfSize:[UIFont labelFontSize]] }
								  context:nil].size.height+40;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedResultsController sections][indexPath.section];
	NSString *sectionName = [sectionInfo name];
	NSString *mergedName = kPullRequestSectionNames[kPullRequestSectionMerged];
	return [sectionName isEqualToString:mergedName];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return UITableViewCellEditingStyleDelete;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(editingStyle==UITableViewCellEditingStyleDelete)
	{
		PullRequest *pr = [self.fetchedResultsController objectAtIndexPath:indexPath];
		[[AppDelegate shared].dataManager.managedObjectContext deleteObject:pr];
		[[AppDelegate shared].dataManager saveDB];
	}
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"showDetail"]) {
        NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
        PullRequest *object = [[self fetchedResultsController] objectAtIndexPath:indexPath];
        [[segue destinationViewController] setDetailItem:[NSURL URLWithString:object.webUrl]];
    }
}

#pragma mark - Fetched results controller

- (NSFetchedResultsController *)fetchedResultsController
{
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }

    NSFetchRequest *fetchRequest = [PullRequest requestForPullRequestsWithFilter:searchField.text];
    [fetchRequest setFetchBatchSize:20];

    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
																								managedObjectContext:self.managedObjectContext
																								  sectionNameKeyPath:@"sectionName"
																										   cacheName:nil];
    aFetchedResultsController.delegate = self;
    self.fetchedResultsController = aFetchedResultsController;

	NSError *error = nil;
	if (![self.fetchedResultsController performFetch:&error]) {
	    NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
	    abort();
	}

    return _fetchedResultsController;
}    

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller
{
    [self.tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type
{
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;
    }
}

- (void)controller:(NSFetchedResultsController *)controller didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath
{
    UITableView *tableView = self.tableView;

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
    [self.tableView endUpdates];
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    PullRequest *pr = [self.fetchedResultsController objectAtIndexPath:indexPath];
	[((PRCell *)cell) setPullRequest:pr];
}

///////////////////////////// filtering

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

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
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

@end
