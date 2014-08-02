
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
	if(UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad)
	{
		settingsChangedTimer = [[HTPopTimer alloc] initWithTimeInterval:1.0
																 target:app.dataManager
															   selector:@selector(postProcessAllPrs)];
	}
}

#define REFRESH_SECTION_INDEX 0
#define DISPLAY_SECTION_INDEX 1
#define COMMENTS_SECTION_INDEX 2
#define REPOS_SECTION_INDEX 3
#define HISTORY_SECTION_INDEX 4
#define CONFIRM_SECTION_INDEX 5
#define SORT_SECTION_INDEX 6
#define API_SECTION_INDEX 7

#define TOTAL_SECTIONS 8

#define SORT_REVERSE @[@"Youngest first",@"Most recently active",@"Reverse alphabetically"]
#define SORT_NORMAL @[@"Oldest first",@"Inactive for longest",@"Alphabetically"]
#define PR_HANDLING_POLICY @[@"Keep My Own",@"Keep All",@"Don't Keep"]

NSString *B(NSString *input)
{
	if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
		input = [input stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
	return input;
}

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
				cell.textLabel.text = B(@"Foreground refresh\ninterval");
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f seconds",settings.refreshPeriod];
				break;
			}
			case 1:
			{
				cell.textLabel.text = B(@"Background refresh\ninterval (minimum)");
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f minutes",settings.backgroundRefreshPeriod/60.0];
				break;
			}
			case 2:
			{
				cell.textLabel.text = B(@"Watchlist refresh\ninterval");
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
				cell.textLabel.text = B(@"Display creation instead\nof activity times");
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
				cell.textLabel.text = B(@"Announce unmergeable PRs only\nin 'Mine'/'Participated'");
				if(settings.markUnmergeableOnUserSectionsOnly) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
				cell.textLabel.text = B(@"Display comment badges\nand alerts for all PRs");
				if(settings.showCommentsEverywhere) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 1:
			{
				cell.textLabel.text = B(@"Only display PRs\nwith unread comments");
				if(settings.shouldHideUncommentedRequests) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 2:
			{
				cell.textLabel.text = B(@"Move PRs that mention me\nto 'Participated'");
				if(settings.autoParticipateInMentions) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 3:
			{
				cell.textLabel.text = B(@"Open PRs at first unread\ncomment");
				if(settings.openPrAtFirstUnreadComment) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
				cell.textLabel.text = @"Display repository names";
				if(settings.showReposInName) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 1:
            {
				cell.textLabel.text = B(@"Include repositories in\nfiltering");
				if(settings.includeReposInFilter) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 2:
			{
				cell.textLabel.text = B(@"Hide new repositories\nby default");
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
				cell.textLabel.text = B(@"When a PR is merged");
				cell.detailTextLabel.text = PR_HANDLING_POLICY[settings.mergeHandlingPolicy];
				break;
			}
			case 1:
			{
				cell.textLabel.text = B(@"When a PR is closed");
				cell.detailTextLabel.text = PR_HANDLING_POLICY[settings.closeHandlingPolicy];
				break;
			}
			case 2:
			{
				cell.textLabel.text = B(@"Don't keep PRs merged\nby me");
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
	else if(indexPath.section==API_SECTION_INDEX)
	{
		cell.textLabel.text = @"API Server";
		cell.detailTextLabel.text = nil;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
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
		}
		[settingsChangedTimer push];
	}
	else if(indexPath.section==REPOS_SECTION_INDEX)
	{
		switch (indexPath.row)
		{
			case 0:
			{
				settings.showReposInName = !settings.showReposInName;
				break;
			}
			case 1:
			{
				settings.includeReposInFilter = !settings.includeReposInFilter;
				break;
			}
			case 2:
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
	else if(indexPath.section==API_SECTION_INDEX)
	{
		[self performSegueWithIdentifier:@"apiServer" sender:self];
	}
	[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
		case REFRESH_SECTION_INDEX: return 3;
		case DISPLAY_SECTION_INDEX: return 5;
		case COMMENTS_SECTION_INDEX: return 4;
		case REPOS_SECTION_INDEX: return 3;
		case HISTORY_SECTION_INDEX: return 3;
		case CONFIRM_SECTION_INDEX: return 2;
		case SORT_SECTION_INDEX: return 3;
		case API_SECTION_INDEX: return 1;
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
		case API_SECTION_INDEX: return @"API";
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
