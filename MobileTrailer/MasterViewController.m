
@interface MasterViewController () <UITextFieldDelegate, UIActionSheetDelegate, UIAlertViewDelegate>
{
    // Opening PRs
    NSString *urlToOpen;

    // Filtering
    UITextField *searchField;
    HTPopTimer *searchTimer;

	// Refreshing
	BOOL refreshOnRelease;
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
										  otherButtonTitles:@"Remove all merged", @"Remove all closed", nil];
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

- (void)removeAllMerged
{
    if([Settings shared].dontAskBeforeWipingMerged)
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
    if([Settings shared].dontAskBeforeWipingClosed)
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
	for(PullRequest *p in [PullRequest allClosedRequestsInMoc:self.managedObjectContext])
		[self.managedObjectContext deleteObject:p];
    [[AppDelegate shared].dataManager saveDB];
}

- (void)removeAllMergedConfirmed
{
	for(PullRequest *p in [PullRequest allMergedRequestsInMoc:self.managedObjectContext])
		[self.managedObjectContext deleteObject:p];
    [[AppDelegate shared].dataManager saveDB];
}

- (void)markAllAsRead
{
	for(PullRequest *p in self.fetchedResultsController.fetchedObjects) [p catchUpWithComments];
    [[AppDelegate shared].dataManager saveDB];
}

- (void)refreshControlChanged
{
	if(![AppDelegate shared].isRefreshing) refreshOnRelease = YES;
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
	searchField.placeholder = @"Filter...";
	searchField.returnKeyType = UIReturnKeySearch;
	searchField.font = [UIFont systemFontOfSize:18.0];
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

	urlToOpen = notification.userInfo[NOTIFICATION_URL_KEY];

    NSNumber *pullRequestId = notification.userInfo[PULL_REQUEST_ID_KEY];

    NSNumber *commentId = notification.userInfo[COMMENT_ID_KEY];

    PullRequest *pullRequest = nil;

    if(commentId)
    {
        PRComment *c = [PRComment itemOfType:@"PRComment" serverId:commentId moc:self.managedObjectContext];
        if(!urlToOpen) urlToOpen = c.webUrl;
        pullRequest = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:self.managedObjectContext];
    }
    else if(pullRequestId)
    {
        pullRequest = [PullRequest itemOfType:@"PullRequest" serverId:pullRequestId moc:self.managedObjectContext];
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
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
            self.detailViewController.detailItem = [NSURL URLWithString:urlToOpen];
        else
            [self performSegueWithIdentifier:@"showDetail" sender:self];
    }
}

- (void)catchUp:(PullRequest *)pullRequest
{
    double delayInSeconds = 0.1;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [pullRequest catchUpWithComments];
        [[AppDelegate shared].dataManager saveDB];
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
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    {
        self.detailViewController.detailItem = [NSURL URLWithString:pullRequest.urlForOpening];
    }
    else
    {
        urlToOpen = pullRequest.urlForOpening;
        [self performSegueWithIdentifier:@"showDetail" sender:self];
    }
    [self catchUp:pullRequest];
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

	CGFloat H = 30;

	H += [pr.title boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
								options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
							 attributes:@{ NSFontAttributeName:[UIFont systemFontOfSize:[UIFont labelFontSize]] }
								context:nil].size.height;

	H += [pr.subtitle boundingRectWithSize:CGSizeMake(w, CGFLOAT_MAX)
								   options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
								attributes:@{ NSFontAttributeName:[UIFont systemFontOfSize:[UIFont smallSystemFontSize]] }
								   context:nil].size.height;

	return MAX(65,H);
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
		[self.managedObjectContext deleteObject:pr];
		[[AppDelegate shared].dataManager saveDB];
	}
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"showDetail"])
    {
        [[segue destinationViewController] setDetailItem:[NSURL URLWithString:urlToOpen]];
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
	if([AppDelegate shared].isRefreshing)
	{
		self.title = @"Refreshing...";
		EmptyView *label = [[EmptyView alloc] initWithMessage:[[AppDelegate shared].dataManager reasonForEmptyWithFilter:searchField.text]];
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
			EmptyView *label = [[EmptyView alloc] initWithMessage:[[AppDelegate shared].dataManager reasonForEmptyWithFilter:searchField.text]];
			self.tableView.tableFooterView = label;
		}
	}
	self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:[[AppDelegate shared].api lastUpdateDescription]
																		  attributes:@{ }];

	[UIApplication sharedApplication].applicationIconBadgeNumber = [PullRequest badgeCountInMoc:self.managedObjectContext];
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
