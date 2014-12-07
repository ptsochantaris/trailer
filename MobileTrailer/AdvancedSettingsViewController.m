#import "PickerViewController.h"
#import "AdvancedSettingsViewController.h"

@interface AdvancedSettingsViewController () <PickerViewControllerDelegate>
{
	PopTimer *settingsChangedTimer;

	// showing the picker
	NSArray *valuesToPush;
	NSString *pickerName;
	NSIndexPath *selectedIndexPath;
	NSInteger previousValue;
}
@end

@implementation AdvancedSettingsViewController

- (IBAction)done:(UIBarButtonItem *)sender
{
	if(app.preferencesDirty) [app startRefresh];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	settingsChangedTimer = [[PopTimer alloc] initWithTimeInterval:1.0
														 callback:^{
															 [app refreshMainList];
														 }];
}

#define REFRESH_SECTION_INDEX 0
#define DISPLAY_SECTION_INDEX 1
#define COMMENTS_SECTION_INDEX 2
#define REPOS_SECTION_INDEX 3
#define LABEL_SECTION_INDEX 4
#define HISTORY_SECTION_INDEX 5
#define CONFIRM_SECTION_INDEX 6
#define SORT_SECTION_INDEX 7
#define MISC_SECTION_INDEX 8

#define TOTAL_SECTIONS 9

#define SORT_REVERSE @[@"Youngest first",@"Most recently active",@"Reverse alphabetically"]
#define SORT_NORMAL @[@"Oldest first",@"Inactive for longest",@"Alphabetically"]
#define PR_HANDLING_POLICY @[@"Keep My Own",@"Keep All",@"Don't Keep"]

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
	cell.accessoryType = UITableViewCellAccessoryNone;
	cell.detailTextLabel.text = @" ";
	if(indexPath.section==REFRESH_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Foreground refresh interval";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f seconds",Settings.refreshPeriod];
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Background refresh interval (minimum)";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f minutes",Settings.backgroundRefreshPeriod/60.0];
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Watchlist refresh interval";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f hours",Settings.newRepoCheckPeriod];
				break;
			}
		}
	}
	else if(indexPath.section==DISPLAY_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Display creation instead of activity times";
				if(Settings.showCreatedInsteadOfUpdated) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 1:
            {
				cell.textLabel.text = @"Hide 'All PRs' section";
				if(Settings.hideAllPrsSection) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 2:
            {
				cell.textLabel.text = @"Move assigned PRs to 'Mine'";
				if(Settings.moveAssignedPrsToMySection) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 3:
			{
				cell.textLabel.text = @"Announce unmergeable PRs only in 'Mine'/'Participated'";
				if(Settings.markUnmergeableOnUserSectionsOnly) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 4:
            {
				cell.textLabel.text = @"Display repository names";
				if(Settings.showReposInName) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 5:
            {
				cell.textLabel.text = @"Include repository names in filtering";
				if(Settings.includeReposInFilter) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }

		}
	}
	else if(indexPath.section==COMMENTS_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Display comment badges and alerts for all PRs";
				if(Settings.showCommentsEverywhere) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Only display PRs with unread comments";
				if(Settings.shouldHideUncommentedRequests) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Move PRs that mention me to 'Participated'";
				if(Settings.autoParticipateInMentions) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 3:
			{
				cell.textLabel.text = @"Open PRs at first unread comment";
				if(Settings.openPrAtFirstUnreadComment) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 4:
			{
				cell.textLabel.text = @"Block comment notifications from usernames...";
				cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
				break;
			}
		}
	}
	else if(indexPath.section==REPOS_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Auto-hide new repositories in your watchlist";
				if(Settings.hideNewRepositories) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
		}
	}
	else if(indexPath.section==LABEL_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Show labels";
				if(Settings.showLabels) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Re-query labels";
				if(Settings.labelRefreshInterval==1)
					cell.detailTextLabel.text = @"Every refresh";
				else
					cell.detailTextLabel.text = [NSString stringWithFormat:@"Every %ld refreshes",(long)Settings.labelRefreshInterval];
			}
		}
	}
	else if(indexPath.section==HISTORY_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"When a PR is merged";
				cell.detailTextLabel.text = PR_HANDLING_POLICY[Settings.mergeHandlingPolicy];
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"When a PR is closed";
				cell.detailTextLabel.text = PR_HANDLING_POLICY[Settings.closeHandlingPolicy];
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Don't keep PRs merged by me";
				if(Settings.dontKeepPrsMergedByMe) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
		}
	}
	else if(indexPath.section==CONFIRM_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
            {
				cell.textLabel.text = @"Removing all merged PRs";
				if(Settings.dontAskBeforeWipingMerged) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
            case 1:
            {
				cell.textLabel.text = @"Removing all closed PRs";
				if(Settings.dontAskBeforeWipingClosed) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
		}
	}
	else if(indexPath.section==SORT_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Direction";
				if(Settings.sortDescending)
					cell.detailTextLabel.text = @"Reverse";
				else
					cell.detailTextLabel.text = @"Normal";
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Criterion";
				if(Settings.sortDescending)
					cell.detailTextLabel.text = SORT_REVERSE[Settings.sortMethod];
				else
					cell.detailTextLabel.text = SORT_NORMAL[Settings.sortMethod];
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Group by repository";
				if(Settings.groupByRepo) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
		}
	}
	else if(indexPath.section==MISC_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Log activity to console";
				if(Settings.logActivityToConsole) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
		}
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(indexPath.section==REFRESH_SECTION_INDEX)
	{
		pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
		selectedIndexPath = indexPath;
		NSMutableArray *values = [[NSMutableArray alloc] init];
		switch (indexPath.row)
		{
			case 0:
			{
				// seconds
				NSInteger count=0;
				for(NSInteger f=60;f<3600;f+=10)
				{
					if(f==Settings.refreshPeriod) previousValue = count;
					[values addObject:[NSString stringWithFormat:@"%ld seconds",(long)f]];
					count++;
				}
				break;
			}
			case 1:
			{
				// minutes
				NSInteger count=0;
				for(NSInteger f=10;f<10000;f+=10)
				{
					if(f==Settings.backgroundRefreshPeriod/60.0) previousValue = count;
					[values addObject:[NSString stringWithFormat:@"%ld minutes",(long)f]];
					count++;
				}
				break;
			}
			case 2:
			{
				// hours
				NSInteger count=0;
				for(NSInteger f=1;f<100;f+=1)
				{
					if(f==Settings.newRepoCheckPeriod) previousValue = count;
					[values addObject:[NSString stringWithFormat:@"%ld hours",(long)f]];
					count++;
				}
				break;
			}
		}
		valuesToPush = values;
		[self performSegueWithIdentifier:@"showPicker" sender:self];
	}
	else if(indexPath.section==DISPLAY_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				Settings.showCreatedInsteadOfUpdated = !Settings.showCreatedInsteadOfUpdated;
				[settingsChangedTimer push];
				break;
			}
			case 1:
			{
				Settings.hideAllPrsSection = !Settings.hideAllPrsSection;
				[settingsChangedTimer push];
				break;
			}
			case 2:
			{
				Settings.moveAssignedPrsToMySection = !Settings.moveAssignedPrsToMySection;
				[settingsChangedTimer push];
				break;
			}
			case 3:
			{
				Settings.markUnmergeableOnUserSectionsOnly = !Settings.markUnmergeableOnUserSectionsOnly;
				[settingsChangedTimer push];
				break;
			}
			case 4:
			{
				Settings.showReposInName = !Settings.showReposInName;
				[settingsChangedTimer push];
				break;
			}
			case 5:
			{
				Settings.includeReposInFilter = !Settings.includeReposInFilter;
				break;
			}
		}
	}
	else if(indexPath.section==COMMENTS_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				Settings.showCommentsEverywhere = !Settings.showCommentsEverywhere;
				[settingsChangedTimer push];
				break;
			}
			case 1:
			{
				Settings.shouldHideUncommentedRequests = !Settings.shouldHideUncommentedRequests;
				[settingsChangedTimer push];
				break;
			}
			case 2:
			{
				Settings.autoParticipateInMentions = !Settings.autoParticipateInMentions;
				[settingsChangedTimer push];
				break;
			}
			case 3:
			{
				Settings.openPrAtFirstUnreadComment = !Settings.openPrAtFirstUnreadComment;
				break;
			}
			case 4:
			{
				[self performSegueWithIdentifier:@"showBlacklist" sender:self];
				return;
			}
		}
	}
	else if(indexPath.section==REPOS_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				Settings.hideNewRepositories = !Settings.hideNewRepositories;
				break;
			}
		}
	}
	else if(indexPath.section==LABEL_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				Settings.showLabels = !Settings.showLabels;
				app.api.successfulRefreshesSinceLastLabelCheck = 0;
				if(Settings.showLabels)
				{
					for(Repo *r in [Repo allItemsOfType:@"Repo" inMoc:DataManager.managedObjectContext])
					{
						r.dirty = @YES;
						r.lastDirtied = [NSDate distantPast];
					}
					app.preferencesDirty = YES;
					[settingsChangedTimer push];
				}
				break;
			}
			case 1:
			{
				selectedIndexPath = indexPath;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;

				NSMutableArray *values = [[NSMutableArray alloc] init];
				NSInteger count=1;
				[values addObject:@"Every refresh"];
				previousValue = 0;
				for(NSInteger f=2;f<100;f++)
				{
					if(f==Settings.labelRefreshInterval) previousValue = count;
					[values addObject:[NSString stringWithFormat:@"Every %ld refreshes",(long)f]];
					count++;
				}
				valuesToPush = values;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
			}
		}
	}
	else if(indexPath.section==HISTORY_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
                selectedIndexPath = indexPath;
				previousValue = Settings.mergeHandlingPolicy;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
                valuesToPush = PR_HANDLING_POLICY;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 1:
			{
                selectedIndexPath = indexPath;
				previousValue = Settings.closeHandlingPolicy;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
                valuesToPush = PR_HANDLING_POLICY;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 2:
			{
				Settings.dontKeepPrsMergedByMe = !Settings.dontKeepPrsMergedByMe;
				break;
			}
		}
	}
	else if(indexPath.section==CONFIRM_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				Settings.dontAskBeforeWipingMerged = !Settings.dontAskBeforeWipingMerged;
				break;
			}
			case 1:
			{
				Settings.dontAskBeforeWipingClosed = !Settings.dontAskBeforeWipingClosed;
				break;
			}
		}
	}
	else if(indexPath.section==SORT_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				Settings.sortDescending = !Settings.sortDescending;
				[settingsChangedTimer push];
				[self.tableView reloadData];
				break;
			}
			case 1:
			{
				selectedIndexPath = indexPath;
				previousValue = Settings.sortMethod;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
				if(Settings.sortDescending)
					valuesToPush = SORT_REVERSE;
				else
					valuesToPush = SORT_NORMAL;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 2:
			{
				Settings.groupByRepo = !Settings.groupByRepo;
				[settingsChangedTimer push];
				break;
			}
		}
	}
	else if(indexPath.section==MISC_SECTION_INDEX)
	{
		switch (indexPath.row) {
			case 0:
			{
				Settings.logActivityToConsole = !Settings.logActivityToConsole;
				[self.tableView reloadData];
				if(Settings.logActivityToConsole)
				{
					[[[UIAlertView alloc] initWithTitle:@"Warning"
												message:@"Logging is a feature meant for error reporting, having it constantly enabled will cause this app to be less responsive and use more battery"
											   delegate:nil
									  cancelButtonTitle:@"OK"
									  otherButtonTitles:nil] show];
				}
				break;
			}
		}
	}
	[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
		case REFRESH_SECTION_INDEX: return 3;
		case DISPLAY_SECTION_INDEX: return 6;
		case COMMENTS_SECTION_INDEX: return 5;
		case REPOS_SECTION_INDEX: return 1;
		case LABEL_SECTION_INDEX: return 2;
		case HISTORY_SECTION_INDEX: return 3;
		case CONFIRM_SECTION_INDEX: return 2;
		case SORT_SECTION_INDEX: return 3;
		case MISC_SECTION_INDEX: return 1;
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
		case REFRESH_SECTION_INDEX: return @"Auto Refresh";
		case DISPLAY_SECTION_INDEX: return @"Display";
		case COMMENTS_SECTION_INDEX: return @"Comments";
		case REPOS_SECTION_INDEX: return @"Repositories";
		case LABEL_SECTION_INDEX: return @"PR Labels";
		case HISTORY_SECTION_INDEX: return @"History";
		case CONFIRM_SECTION_INDEX: return @"Don't confirm when";
		case SORT_SECTION_INDEX: return @"Sorting";
		case MISC_SECTION_INDEX: return @"Misc";
	}
	return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return TOTAL_SECTIONS;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	if([segue.destinationViewController isKindOfClass:[PickerViewController class]])
	{
		PickerViewController *p = (PickerViewController *)segue.destinationViewController;
		p.delegate = self;
		p.title = pickerName;
		p.values = valuesToPush;
		p.previousValue = previousValue;
		pickerName = nil;
		valuesToPush = nil;
	}
}

- (void)pickerViewController:(PickerViewController *)picker selectedIndexPath:(NSIndexPath *)indexPath
{
	if(selectedIndexPath.section==REFRESH_SECTION_INDEX)
	{
		if(selectedIndexPath.row==0)
		{
			Settings.refreshPeriod = indexPath.row*10+60;
		}
		else if(selectedIndexPath.row==1)
		{
			Settings.backgroundRefreshPeriod = (indexPath.row*10+10)*60.0;
		}
		else if(selectedIndexPath.row==2)
		{
			Settings.newRepoCheckPeriod = indexPath.row+1;
		}
	}
	else if(selectedIndexPath.section==SORT_SECTION_INDEX)
	{
		Settings.sortMethod = indexPath.row;
		[settingsChangedTimer push];
	}
	else if(selectedIndexPath.section==HISTORY_SECTION_INDEX)
	{
		if(selectedIndexPath.row==0)
		{
			Settings.mergeHandlingPolicy = indexPath.row;
		}
		else if(selectedIndexPath.row==1)
		{
			Settings.closeHandlingPolicy = indexPath.row;
		}
	}
	else if(selectedIndexPath.section==LABEL_SECTION_INDEX)
	{
		Settings.labelRefreshInterval = indexPath.row+1;
	}
	[self.tableView reloadData];
	selectedIndexPath = nil;
}

@end
