//
//  MasterViewController.m
//  MobileTrailer
//
//  Created by Paul Tsochantaris on 4/1/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

@interface MasterViewController ()
{
	NSDateFormatter *itemDateFormatter;
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
	[[AppDelegate shared] startRefresh];
}
- (IBAction)ipadRefreshSelected:(id)sender {
	[[AppDelegate shared] startRefresh];
}


- (void)viewDidLoad
{
    [super viewDidLoad];

	self.detailViewController = (DetailViewController *)[[self.splitViewController.viewControllers lastObject] topViewController];
	itemDateFormatter = [[NSDateFormatter alloc] init];
	itemDateFormatter.dateStyle = NSDateFormatterShortStyle;
	itemDateFormatter.timeStyle = NSDateFormatterShortStyle;

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(refreshStarted)
												 name:REFRESH_STARTED_NOTIFICATION
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(refreshEnded)
												 name:REFRESH_ENDED_NOTIFICATION
											   object:nil];
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
        self.detailViewController.detailItem = object;
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
	return [pr.title sizeWithFont:[UIFont boldSystemFontOfSize:[UIFont labelFontSize]]
				constrainedToSize:CGSizeMake(225, 5000)
					lineBreakMode:NSLineBreakByWordWrapping].height+38;
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
        [[segue destinationViewController] setDetailItem:object];
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
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"PullRequest" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    // Set the batch size to a suitable number.
    [fetchRequest setFetchBatchSize:20];
    
    // Edit the sort key as appropriate.
    [fetchRequest setSortDescriptors:@[ [[NSSortDescriptor alloc] initWithKey:@"sectionIndex" ascending:YES],
									    [[NSSortDescriptor alloc] initWithKey:@"createdAt" ascending:NO] ]];
    
    // Edit the section name key path and cache name if appropriate.
    // nil for section name key path means "no sections".
    NSFetchedResultsController *aFetchedResultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
																								managedObjectContext:self.managedObjectContext
																								  sectionNameKeyPath:@"sectionName"
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

/*- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
	[self.tableView reloadData];
}*/

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
    cell.textLabel.text = pr.title;
	cell.textLabel.numberOfLines = 0;
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ - %@",pr.userLogin,[itemDateFormatter stringFromDate:pr.updatedAt]];
	cell.imageView.image = [UIImage imageNamed:@"avatarPlaceHolder"];
	cell.detailTextLabel.textColor = [UIColor grayColor];
	NSString *imagePath = pr.userAvatarUrl;
	if(imagePath)
	{
		[[AppDelegate shared].api getImage:imagePath
								   success:^(NSHTTPURLResponse *response, NSData *imageData) {
									   cell.imageView.image = [[UIImage imageWithData:imageData] scaleToFillSize:CGSizeMake(40, 40)];
									   [cell setNeedsLayout];
									   [cell setNeedsDisplay];
								   } failure:^(NSHTTPURLResponse *response, NSError *error) {
									   cell.imageView.image = nil;
								   }];
	}
}

@end
