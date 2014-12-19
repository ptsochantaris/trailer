#import "RespositoriesViewController.h"

@interface RespositoriesViewController () <UITextFieldDelegate, NSFetchedResultsControllerDelegate>
{
	// Filtering
    UITextField *searchField;
    PopTimer *searchTimer;
}
@property (nonatomic) NSFetchedResultsController *fetchedResultsController;
@property (weak, nonatomic) IBOutlet UIBarButtonItem *actionsButton;
@end

@implementation RespositoriesViewController

- (IBAction)done:(UIBarButtonItem *)sender
{
	if(app.preferencesDirty) [app startRefresh];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	searchTimer = [[PopTimer alloc] initWithTimeInterval:0.5
												callback:^{
													[self reloadData];
												}];

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

    UIView *searchHolder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 51)];
	[searchHolder addSubview:searchField];
	searchHolder.autoresizesSubviews = YES;
	searchHolder.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	self.tableView.tableHeaderView = searchHolder;

	self.actionsButton.enabled = [ApiServer someServersHaveAuthTokensInMoc:DataManager.managedObjectContext];
}

- (IBAction)actionSelected:(UIBarButtonItem *)sender
{
	UIAlertController *a = [UIAlertController alertControllerWithTitle:nil
															   message:nil
														preferredStyle:UIAlertControllerStyleActionSheet];
	[a addAction:[UIAlertAction actionWithTitle:@"Refresh List"
										  style:UIAlertActionStyleDestructive
										handler:^(UIAlertAction *action) {
											[self refreshList];
										}]];
	[a addAction:[UIAlertAction actionWithTitle:@"Hide All"
										  style:UIAlertActionStyleDefault
										handler:^(UIAlertAction *action) {
											NSArray *allRepos = self.fetchedResultsController.fetchedObjects;
											for(Repo *r in allRepos) { r.hidden = @YES; r.dirty = @NO; }
											app.preferencesDirty = YES;
										}]];
	[a addAction:[UIAlertAction actionWithTitle:@"Show All"
										  style:UIAlertActionStyleDefault
										handler:^(UIAlertAction *action) {
											NSArray *allRepos = self.fetchedResultsController.fetchedObjects;
											for(Repo *r in allRepos) { r.hidden = @NO; r.dirty = @YES; r.lastDirtied = [NSDate date]; }
											app.preferencesDirty = YES;
										}]];
	[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	a.popoverPresentationController.barButtonItem = sender;
	[self presentViewController:a animated:YES completion:nil];
}

- (void)refreshList
{
	NSString *originalName = self.navigationItem.title;
	self.navigationItem.title = @"Loading...";
	self.actionsButton.enabled = NO;
	self.tableView.userInteractionEnabled = NO;
	self.tableView.alpha = 0.5;

	NSManagedObjectContext *tempContext = [DataManager tempContext];
	[api fetchRepositoriesToMoc:tempContext andCallback:^{
		if([ApiServer shouldReportRefreshFailureInMoc:tempContext])
		{
			NSMutableArray *errorServers = [NSMutableArray new];
			for(ApiServer *apiServer in [ApiServer allApiServersInMoc:tempContext])
			{
				if(apiServer.goodToGo && !apiServer.lastSyncSucceeded.boolValue)
				{
					[errorServers addObject:apiServer.label];
				}
			}

			NSString *serverNames = [errorServers componentsJoinedByString:@", "];
			NSString *message = [NSString stringWithFormat:@"Could not refresh repository list from %@, please ensure that the tokens you are using are valid",serverNames];

			[[[UIAlertView alloc] initWithTitle:@"Error"
										message:message
									   delegate:nil
							  cancelButtonTitle:@"OK"
							  otherButtonTitles:nil] show];

		}
		else
		{
			[tempContext save:nil];
		}
		self.navigationItem.title = originalName;
		self.actionsButton.enabled = YES;
		self.tableView.alpha = 1.0;
		self.tableView.userInteractionEnabled = YES;
		app.preferencesDirty = YES;
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
	[DataManager saveDB];
	[tableView deselectRowAtIndexPath:indexPath animated:NO];
	app.preferencesDirty = YES;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if(section==1)
	{
		return @"Forked Repos";
	}
	else
	{
		Repo *repo = [self.fetchedResultsController objectAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:section]];
		if(repo.fork.boolValue)
		{
			return @"Forked Repos";
		}
		else
		{
			return @"Parent Repos";
		}
	}
}

#pragma mark - Fetched results controller

- (NSFetchedResultsController *)fetchedResultsController
{
    if (_fetchedResultsController != nil) {
        return _fetchedResultsController;
    }

    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    // Edit the entity name as appropriate.
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Repo" inManagedObjectContext:DataManager.managedObjectContext];
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
																								managedObjectContext:DataManager.managedObjectContext
																								  sectionNameKeyPath:@"fork"
																										   cacheName:nil];
    aFetchedResultsController.delegate = self;
    self.fetchedResultsController = aFetchedResultsController;

	NSError *error = nil;
	if (![self.fetchedResultsController performFetch:&error]) {
	    DLog(@"Unresolved error %@, %@", error, [error userInfo]);
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

///////////////////////////// filtering

- (void)reloadData
{
	NSIndexSet *currentIndexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _fetchedResultsController.sections.count)];

	_fetchedResultsController = nil;

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
