//
//  PreferencesViewController.m
//  Trailer
//
//  Created by Paul Tsochantaris on 4/1/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

#import "PreferencesViewController.h"

@interface PreferencesViewController () <UITextFieldDelegate, NSFetchedResultsControllerDelegate>
{
	BOOL thereWereChanges;
}
@end

@implementation PreferencesViewController

- (IBAction)ipadDone:(UIBarButtonItem *)sender {
	[[self valueForKey:@"popoverController"] dismissPopoverAnimated:YES];
	if(thereWereChanges)
	{
		[[AppDelegate shared] startRefresh];
	}
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.apiLoad.progress = 0.0;
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiUsageUpdate:) name:RATE_UPDATE_NOTIFICATION object:nil];

	NSString *currentAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	currentAppVersion = [@"Version " stringByAppendingString:currentAppVersion];
	self.versionNumber.text = currentAppVersion;

	self.githubApiToken.text = [AppDelegate shared].api.authToken;
	self.refreshRepoList.enabled = ([AppDelegate shared].api.authToken.length>0);
	[self.repositories reloadData];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)apiUsageUpdate:(NSNotification *)n
{
	API *api = [AppDelegate shared].api;
	[self.apiLoad setProgress:(api.requestsLimit-api.requestsRemaining)/api.requestsRemaining];
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
	if([string isEqualToString:@"\n"])
	{
		[AppDelegate shared].api.authToken = [self.githubApiToken.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		self.refreshRepoList.enabled = ([AppDelegate shared].api.authToken.length>0);
		[textField resignFirstResponder];
		return NO;
	}
	return YES;
}

- (IBAction)ipadLoadRepositories:(UIButton *)sender {
	[self updateRepositories];
}
- (IBAction)iphoneLoadRepositories:(UIButton *)sender {
	[self updateRepositories];
}
- (void)updateRepositories
{
	NSString *originalName = [self.refreshRepoList titleForState:UIControlStateNormal];
	[self.refreshRepoList setTitle:@"Loading..." forState:UIControlStateNormal];
	self.refreshRepoList.enabled = NO;
	self.repositories.hidden = YES;
	self.githubApiToken.hidden = YES;

	[[AppDelegate shared].api fetchRepositoriesAndCallback:^(BOOL success) {
		[self.repositories reloadData];
		[self.refreshRepoList setTitle:originalName forState:UIControlStateNormal];
		self.refreshRepoList.enabled = YES;
		self.repositories.hidden = NO;
		self.githubApiToken.hidden = NO;

		thereWereChanges = YES;

		if(!success)
		{
			[[[UIAlertView alloc] initWithTitle:@"Error"
										message:@"Could not refresh repository list, please try again later"
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
	thereWereChanges = YES;
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

@end
