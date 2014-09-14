
@interface AdvancedSettingsViewController () <PickerViewControllerDelegate>
{
	HTPopTimer *settingsChangedTimer;

	// showing the picker
	NSArray *valuesToPush;
	NSString *pickerName;
	NSIndexPath *selectedIndexPath;
	NSInteger previousValue;
}
@end

@implementation AdvancedSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	settingsChangedTimer = [[HTPopTimer alloc] initWithTimeInterval:1.0
															 target:app.dataManager
														   selector:@selector(postProcessAllPrs)];
}

#define REFRESH_SECTION_INDEX 0
#define DISPLAY_SECTION_INDEX 1
#define COMMENTS_SECTION_INDEX 2
#define REPOS_SECTION_INDEX 3
#define HISTORY_SECTION_INDEX 4
#define CONFIRM_SECTION_INDEX 5
#define SORT_SECTION_INDEX 6
#define MISC_SECTION_INDEX 7

#define TOTAL_SECTIONS 8

#define SORT_REVERSE @[@"Youngest first",@"Most recently active",@"Reverse alphabetically"]
#define SORT_NORMAL @[@"Oldest first",@"Inactive for longest",@"Alphabetically"]
#define PR_HANDLING_POLICY @[@"Keep My Own",@"Keep All",@"Don't Keep"]

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
	cell.accessoryType = UITableViewCellAccessoryNone;
	if(indexPath.section==REFRESH_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Foreground refresh interval";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f seconds",settings.refreshPeriod];
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Background refresh interval (minimum)";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f minutes",settings.backgroundRefreshPeriod/60.0];
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Watchlist refresh interval";
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f hours",settings.newRepoCheckPeriod];
				break;
			}
		}
	}
	else if(indexPath.section==DISPLAY_SECTION_INDEX)
	{
		cell.detailTextLabel.text = nil;
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Display creation instead of activity times";
				if(settings.showCreatedInsteadOfUpdated) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 1:
            {
				cell.textLabel.text = @"Don't report refresh failures";
				if(settings.dontReportRefreshFailures) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 2:
            {
				cell.textLabel.text = @"Hide 'All PRs' section";
				if(settings.hideAllPrsSection) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 3:
            {
				cell.textLabel.text = @"Move assigned PRs to 'Mine'";
				if(settings.moveAssignedPrsToMySection) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 4:
			{
				cell.textLabel.text = @"Announce unmergeable PRs only in 'Mine'/'Participated'";
				if(settings.markUnmergeableOnUserSectionsOnly) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 5:
            {
				cell.textLabel.text = @"Display repository names";
				if(settings.showReposInName) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 6:
            {
				cell.textLabel.text = @"Include repository names in filtering";
				if(settings.includeReposInFilter) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }

		}
	}
	else if(indexPath.section==COMMENTS_SECTION_INDEX)
	{
		cell.detailTextLabel.text = nil;
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Display comment badges and alerts for all PRs";
				if(settings.showCommentsEverywhere) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Only display PRs with unread comments";
				if(settings.shouldHideUncommentedRequests) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Move PRs that mention me to 'Participated'";
				if(settings.autoParticipateInMentions) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 3:
			{
				cell.textLabel.text = @"Open PRs at first unread comment";
				if(settings.openPrAtFirstUnreadComment) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
		cell.detailTextLabel.text = nil;
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Auto-hide new repositories in your watchlist";
				if(settings.hideNewRepositories) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
		}
	}
	else if(indexPath.section==HISTORY_SECTION_INDEX)
	{
		cell.detailTextLabel.text = nil;
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"When a PR is merged";
				cell.detailTextLabel.text = PR_HANDLING_POLICY[settings.mergeHandlingPolicy];
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"When a PR is closed";
				cell.detailTextLabel.text = PR_HANDLING_POLICY[settings.closeHandlingPolicy];
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Don't keep PRs merged by me";
				if(settings.dontKeepPrsMergedByMe) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
		}
	}
	else if(indexPath.section==CONFIRM_SECTION_INDEX)
	{
		cell.detailTextLabel.text = nil;
		switch (indexPath.row)
		{
			case 0:
            {
				cell.textLabel.text = @"Removing all merged PRs";
				if(settings.dontAskBeforeWipingMerged) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
            case 1:
            {
				cell.textLabel.text = @"Removing all closed PRs";
				if(settings.dontAskBeforeWipingClosed) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
		}
	}
	else if(indexPath.section==SORT_SECTION_INDEX)
	{
		cell.detailTextLabel.text = nil;
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"Direction";
				if(settings.sortDescending)
					cell.detailTextLabel.text = @"Reverse";
				else
					cell.detailTextLabel.text = @"Normal";
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Criterion";
				if(settings.sortDescending)
					cell.detailTextLabel.text = SORT_REVERSE[settings.sortMethod];
				else
					cell.detailTextLabel.text = SORT_NORMAL[settings.sortMethod];
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Group by repository";
				if(settings.groupByRepo) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
		}
	}
	else if(indexPath.section==MISC_SECTION_INDEX)
	{
		cell.detailTextLabel.text = nil;
		switch (indexPath.row)
		{
			case 0:
			{
				cell.textLabel.text = @"API Server";
				cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Log activity to console";
				if(settings.logActivityToConsole) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
					if(f==settings.refreshPeriod) previousValue = count;
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
					if(f==settings.backgroundRefreshPeriod/60.0) previousValue = count;
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
					if(f==settings.newRepoCheckPeriod) previousValue = count;
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
				settings.showCreatedInsteadOfUpdated = !settings.showCreatedInsteadOfUpdated;
				break;
			}
			case 1:
			{
				settings.dontReportRefreshFailures = !settings.dontReportRefreshFailures;
				break;
			}
			case 2:
			{
				settings.hideAllPrsSection = !settings.hideAllPrsSection;
				break;
			}
			case 3:
			{
				settings.moveAssignedPrsToMySection = !settings.moveAssignedPrsToMySection;
				break;
			}
			case 4:
			{
				settings.markUnmergeableOnUserSectionsOnly = !settings.markUnmergeableOnUserSectionsOnly;
				break;
			}
			case 5:
			{
				settings.showReposInName = !settings.showReposInName;
				break;
			}
			case 6:
			{
				settings.includeReposInFilter = !settings.includeReposInFilter;
				break;
			}
		}
		[settingsChangedTimer push];
	}
	else if(indexPath.section==COMMENTS_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				settings.showCommentsEverywhere = !settings.showCommentsEverywhere;
				break;
			}
			case 1:
			{
				settings.shouldHideUncommentedRequests = !settings.shouldHideUncommentedRequests;
				break;
			}
			case 2:
			{
				settings.autoParticipateInMentions = !settings.autoParticipateInMentions;
				break;
			}
			case 3:
			{
				settings.openPrAtFirstUnreadComment = !settings.openPrAtFirstUnreadComment;
			}
			case 4:
			{
				[self performSegueWithIdentifier:@"showBlacklist" sender:self];
				return;
			}
		}
		[settingsChangedTimer push];
	}
	else if(indexPath.section==REPOS_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				settings.hideNewRepositories = !settings.hideNewRepositories;
				break;
			}
		}
		[settingsChangedTimer push];
	}
	else if(indexPath.section==HISTORY_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
                selectedIndexPath = indexPath;
				previousValue = settings.mergeHandlingPolicy;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
                valuesToPush = PR_HANDLING_POLICY;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 1:
			{
                selectedIndexPath = indexPath;
				previousValue = settings.closeHandlingPolicy;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
                valuesToPush = PR_HANDLING_POLICY;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 2:
			{
				settings.dontKeepPrsMergedByMe = !settings.dontKeepPrsMergedByMe;
				[settingsChangedTimer push];
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
				settings.dontAskBeforeWipingMerged = !settings.dontAskBeforeWipingMerged;
				break;
			}
			case 1:
			{
				settings.dontAskBeforeWipingClosed = !settings.dontAskBeforeWipingClosed;
				break;
			}
		}
		[settingsChangedTimer push];
	}
	else if(indexPath.section==SORT_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				settings.sortDescending = !settings.sortDescending;
				[settingsChangedTimer push];
				[self.tableView reloadData];
				break;
			}
			case 1:
			{
				selectedIndexPath = indexPath;
				previousValue = settings.sortMethod;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
				if(settings.sortDescending)
					valuesToPush = SORT_REVERSE;
				else
					valuesToPush = SORT_NORMAL;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 2:
			{
				settings.groupByRepo = !settings.groupByRepo;
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
				[self performSegueWithIdentifier:@"apiServer" sender:self];
				break;
			}
			case 1:
			{
				settings.logActivityToConsole = !settings.logActivityToConsole;
				[self.tableView reloadData];
				if(settings.logActivityToConsole)
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
		case DISPLAY_SECTION_INDEX: return 7;
		case COMMENTS_SECTION_INDEX: return 5;
		case REPOS_SECTION_INDEX: return 1;
		case HISTORY_SECTION_INDEX: return 3;
		case CONFIRM_SECTION_INDEX: return 2;
		case SORT_SECTION_INDEX: return 3;
		case MISC_SECTION_INDEX: return 2;
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
			settings.refreshPeriod = indexPath.row*10+60;
		}
		else if(selectedIndexPath.row==1)
		{
			settings.backgroundRefreshPeriod = (indexPath.row*10+10)*60.0;
		}
		else if(selectedIndexPath.row==2)
		{
			settings.newRepoCheckPeriod = indexPath.row+1;
		}
	}
	else if(selectedIndexPath.section==SORT_SECTION_INDEX)
	{
		settings.sortMethod = indexPath.row;
		[settingsChangedTimer push];
	}
	else if(selectedIndexPath.section==HISTORY_SECTION_INDEX)
	{
		if(selectedIndexPath.row==0)
		{
			settings.mergeHandlingPolicy = indexPath.row;
		}
		else if(selectedIndexPath.row==1)
		{
			settings.closeHandlingPolicy = indexPath.row;
		}
	}
	[self.tableView reloadData];
	selectedIndexPath = nil;
}

@end
