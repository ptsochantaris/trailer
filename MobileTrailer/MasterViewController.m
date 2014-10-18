
@implementation MasterViewController
{
    // Filtering
    UITextField *searchField;
    HTPopTimer *searchTimer;

	// Refreshing
	BOOL refreshOnRelease;
}

- (IBAction)phoneRefreshSelected:(UIBarButtonItem *)sender
{
	if (self.traitCollection.userInterfaceIdiom==UIUserInterfaceIdiomPad && UIInterfaceOrientationIsPortrait([[UIApplication sharedApplication] statusBarOrientation]))
	{
		UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Action"
																	message:nil
															 preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:@"Cancel"
											  style:UIAlertActionStyleCancel
											handler:^(UIAlertAction *action) {
												[a dismissViewControllerAnimated:YES completion:nil];
											}]];
		[a addAction:[UIAlertAction actionWithTitle:@"Mark all as read"
											  style:UIAlertActionStyleDestructive
											handler:^(UIAlertAction *action) {
												[self markAllAsRead];
											}]];
		[a addAction:[UIAlertAction actionWithTitle:@"Remove all merged"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
												[self removeAllMerged];
											}]];
		[a addAction:[UIAlertAction actionWithTitle:@"Remove all closed"
											  style:UIAlertActionStyleDefault
											handler:^(UIAlertAction *action) {
												[self removeAllClosed];
											}]];
		[self presentViewController:a animated:YES completion:nil];
	}
	else
	{
		UIActionSheet *a = [[UIActionSheet alloc] initWithTitle:@"Action"
													   delegate:self
											  cancelButtonTitle:@"Cancel"
										 destructiveButtonTitle:@"Mark all as read"
											  otherButtonTitles:@"Remove all merged", @"Remove all closed", nil];
		
		[a showFromBarButtonItem:sender animated:YES];
	}
}

- (void)actionSheet:(UIActionSheet *)actionSheet willDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if(buttonIndex==0)
    {
		[self markAllAsRead];
    }
	else if(buttonIndex==1)
	{
        [self removeAllMerged];
	}
	else if(buttonIndex==2)
	{
        [self removeAllClosed];
	}
}

- (void)tryRefresh
{
	refreshOnRelease = NO;
	self.tableView.userInteractionEnabled = YES;

	if([app.api.reachability currentReachabilityStatus]==NotReachable)
	{
		[[[UIAlertView alloc] initWithTitle:@"No Network"
									message:@"There is no network connectivity, please try again later"
								   delegate:nil
						  cancelButtonTitle:@"OK"
						  otherButtonTitles:nil] show];
	}
	else
	{
		[app startRefresh];
	}
}

- (void)removeAllMerged
{
    if(settings.dontAskBeforeWipingMerged)
    {
        [self removeAllMergedConfirmed];
    }
    else
    {
        [[[UIAlertView alloc] initWithTitle:@"Sure?"
                                    message:@"Remove all PRs in the Merged section?"
                                   delegate:self
                          cancelButtonTitle:@"No"
                          otherButtonTitles:@"Yes", nil] show];
    }
}

- (void)removeAllClosed
{
    if(settings.dontAskBeforeWipingClosed)
    {
        [self removeAllClosedConfirmed];
    }
    else
    {
        [[[UIAlertView alloc] initWithTitle:@"Sure?"
                                    message:@"Remove all PRs in the Closed section?"
                                   delegate:self
                          cancelButtonTitle:@"No"
                          otherButtonTitles:@"Yes", nil] show];
    }
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if(buttonIndex==1)
    {
		if([alertView.message rangeOfString:@"Merged"].location!=NSNotFound)
		{
			[self removeAllMergedConfirmed];
		}
		else
		{
			[self removeAllClosedConfirmed];
		}
    }
}

- (void)removeAllClosedConfirmed
{
	NSManagedObjectContext *moc = app.dataManager.managedObjectContext;

	for(PullRequest *p in [PullRequest allClosedRequestsInMoc:moc])
		[moc deleteObject:p];
	
    [app.dataManager saveDB];
}

- (void)removeAllMergedConfirmed
{
	NSManagedObjectContext *moc = app.dataManager.managedObjectContext;

	for(PullRequest *p in [PullRequest allMergedRequestsInMoc:moc])
		[moc deleteObject:p];

    [app.dataManager saveDB];
}

- (void)markAllAsRead
{
	for(PullRequest *p in self.fetchedResultsController.fetchedObjects) [p catchUpWithComments];
    [app.dataManager saveDB];
}

- (void)refreshControlChanged
{
	if(!app.isRefreshing) refreshOnRelease = YES;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
	if(refreshOnRelease)
	{
		if(decelerate)
		{
			self.tableView.userInteractionEnabled = NO;
		}
		else
		{
			[self tryRefresh];
		}
	}
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
	if(refreshOnRelease) [self tryRefresh];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	[self.refreshControl addTarget:self action:@selector(refreshControlChanged) forControlEvents:UIControlEventValueChanged];

    searchTimer = [[HTPopTimer alloc] initWithTimeInterval:0.5 target:self selector:@selector(reloadData)];

    searchField = [[UITextField alloc] initWithFrame:CGRectMake(10, 10, 300, 31)];
	searchField.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	searchField.translatesAutoresizingMaskIntoConstraints = YES;
	searchField.placeholder = @"Filter...";
	searchField.returnKeyType = UIReturnKeySearch;
	searchField.font = [UIFont systemFontOfSize:17.0];
	searchField.borderStyle = UITextBorderStyleRoundedRect;
	searchField.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
	searchField.clearButtonMode = UITextFieldViewModeAlways;
	searchField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	searchField.autocorrectionType = UITextAutocorrectionTypeNo;
    searchField.delegate = self;

    UIView *searchHolder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 41)];
	[searchHolder addSubview:searchField];
	self.tableView.tableHeaderView = searchHolder;
    self.tableView.contentOffset = CGPointMake(0, searchHolder.frame.size.height);
	self.tableView.estimatedRowHeight = 125;
	self.tableView.rowHeight = UITableViewAutomaticDimension;

	self.detailViewController = (DetailViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateStatus)
												 name:REFRESH_STARTED_NOTIFICATION
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateStatus)
												 name:REFRESH_ENDED_NOTIFICATION
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(localNotification:)
												 name:RECEIVED_NOTIFICATION_KEY
											   object:nil];
}

- (void)reloadData
{
	[self reloadDataWithAnimation:YES];
}

- (void)reloadDataWithAnimation:(BOOL)animated
{
	if(animated)
	{
		NSIndexSet *currentIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _fetchedResultsController.sections.count)];

		_fetchedResultsController = nil;
		[self updateStatus];

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

		[self.tableView beginUpdates];

		if(removedIndexes.count)
			[self.tableView deleteSections:removedIndexes withRowAnimation:UITableViewRowAnimationAutomatic];

		if(untouchedIndexes.count)
			[self.tableView reloadSections:untouchedIndexes withRowAnimation:UITableViewRowAnimationAutomatic];

		if(addedIndexes.count)
			[self.tableView insertSections:addedIndexes withRowAnimation:UITableViewRowAnimationAutomatic];

		[self.tableView endUpdates];
	}
	else
	{
		[self.tableView reloadData];
	}
}

- (void)localNotification:(NSNotification *)notification
{
	//DLog(@"local notification: %@",notification.userInfo);
	NSString *urlToOpen = notification.userInfo[NOTIFICATION_URL_KEY];
    NSManagedObjectID *pullRequestId = [app.dataManager idForUriPath:notification.userInfo[PULL_REQUEST_ID_KEY]];
    NSManagedObjectID *commentId = [app.dataManager idForUriPath:notification.userInfo[COMMENT_ID_KEY]];

	PullRequest *pullRequest = nil;

	NSManagedObjectContext *moc = app.dataManager.managedObjectContext;

    if(commentId)
    {
        PRComment *c = (PRComment *)[moc existingObjectWithID:commentId error:nil];
        if(!urlToOpen) urlToOpen = c.webUrl;
        pullRequest = c.pullRequest;
    }
    else if(pullRequestId)
    {
        pullRequest = (PullRequest *)[moc existingObjectWithID:pullRequestId error:nil];
        if(!urlToOpen) urlToOpen = pullRequest.webUrl;

        if(!pullRequest)
        {
            [[[UIAlertView alloc] initWithTitle:@"PR not found"
                                        message:@"Could not locale the PR related to this notification"
                                       delegate:nil
                              cancelButtonTitle:@"OK"
                              otherButtonTitles:nil] show];
        }
    }

    if(urlToOpen && searchField.text.length)
    {
        searchField.text = nil;
		[searchField resignFirstResponder];
        [self reloadDataWithAnimation:NO];
    }

    if(pullRequest)
    {
        NSIndexPath *ip = [self.fetchedResultsController indexPathForObject:pullRequest];
		if(ip)
		{
			[self.tableView selectRowAtIndexPath:ip animated:NO scrollPosition:UITableViewScrollPositionMiddle];
		}

        [self catchUp:pullRequest];
    }

    if(urlToOpen)
    {
		self.detailViewController.detailItem = [NSURL URLWithString:urlToOpen];
		[self showDetailViewController:self.detailViewController.navigationController sender:self];
    }
}

- (void)catchUp:(PullRequest *)pullRequest
{
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [pullRequest catchUpWithComments];
        [app.dataManager saveDB];
    });
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
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
    PullRequest *pullRequest = [[self fetchedResultsController] objectAtIndexPath:indexPath];
	self.detailViewController.detailItem = [NSURL URLWithString:pullRequest.urlForOpening];
	[self showDetailViewController:self.detailViewController.navigationController sender:self];
    [self catchUp:pullRequest];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedResultsController sections][section];
	return sectionInfo.name;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
	id <NSFetchedResultsSectionInfo> sectionInfo = [self.fetchedResultsController sections][indexPath.section];

	NSString *sectionName = [sectionInfo name];
	NSString *mergedName = kPullRequestSectionNames[kPullRequestSectionMerged];
	NSString *closedName = kPullRequestSectionNames[kPullRequestSectionClosed];

	return [sectionName isEqualToString:mergedName]||[sectionName isEqualToString:closedName];
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
		[app.dataManager.managedObjectContext deleteObject:pr];
		[app.dataManager saveDB];
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
																								managedObjectContext:app.dataManager.managedObjectContext
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

- (void)controller:(NSFetchedResultsController *)controller
  didChangeSection:(id <NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
	 forChangeType:(NSFetchedResultsChangeType)type
{
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;

        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:UITableViewRowAnimationFade];
            break;

		default:
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
    [self.tableView endUpdates];
	[self updateStatus];
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath
{
    PullRequest *pr = [self.fetchedResultsController objectAtIndexPath:indexPath];
	[((PRCell *)cell) setPullRequest:pr];
}

- (void)updateStatus
{
	if(app.isRefreshing)
	{
		self.title = @"Refreshing...";
		EmptyView *label = [[EmptyView alloc] initWithMessage:[app.dataManager reasonForEmptyWithFilter:searchField.text]];
		self.tableView.tableFooterView = label;

		if(!self.refreshControl.isRefreshing)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.refreshControl beginRefreshing];
			});
		}
	}
	else
	{
		if(self.refreshControl.isRefreshing)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self.refreshControl endRefreshing];
			});
		}

		NSInteger count = self.fetchedResultsController.fetchedObjects.count;
		if(count>0)
		{
			if(count==1)
				self.title = @"1 Pull Request";
			else
				self.title = [NSString stringWithFormat:@"%ld Pull Requests",(long)count];
			self.tableView.tableFooterView = nil;
		}
		else
		{
			self.title = @"No PRs";
			EmptyView *label = [[EmptyView alloc] initWithMessage:[app.dataManager reasonForEmptyWithFilter:searchField.text]];
			self.tableView.tableFooterView = label;
		}
	}
	self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:[app.api lastUpdateDescription]
																		  attributes:@{ }];

	[UIApplication sharedApplication].applicationIconBadgeNumber = [PullRequest badgeCountInMoc:app.dataManager.managedObjectContext];

	if(self.splitViewController.displayMode != UISplitViewControllerDisplayModeAllVisible)
	{
		self.detailViewController.navigationItem.leftBarButtonItem.title = self.title;
	}
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
    [searchTimer push];
    return YES;
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
