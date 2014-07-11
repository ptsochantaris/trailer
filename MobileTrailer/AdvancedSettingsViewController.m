
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
																 target:[AppDelegate shared].dataManager
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
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f seconds",[Settings shared].refreshPeriod];
				break;
			}
			case 1:
			{
				cell.textLabel.text = B(@"Background refresh\ninterval (minimum)");
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f minutes",[Settings shared].backgroundRefreshPeriod/60.0];
				break;
			}
			case 2:
			{
				cell.textLabel.text = B(@"Watchlist refresh\ninterval");
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f hours",[Settings shared].newRepoCheckPeriod];
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
				if([Settings shared].showCreatedInsteadOfUpdated) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 1:
            {
				cell.textLabel.text = @"Don't report refresh failures";
				if([Settings shared].dontReportRefreshFailures) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 2:
            {
				cell.textLabel.text = @"Hide 'All PRs' section";
				if([Settings shared].hideAllPrsSection) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 3:
            {
				cell.textLabel.text = @"Move assigned PRs to 'Mine'";
				if([Settings shared].moveAssignedPrsToMySection) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 4:
			{
				cell.textLabel.text = B(@"Announce unmergeable PRs only\nin 'Mine'/'Participated'");
				if([Settings shared].markUnmergeableOnUserSectionsOnly) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
				if([Settings shared].showCommentsEverywhere) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 1:
			{
				cell.textLabel.text = B(@"Only display PRs\nwith unread comments");
				if([Settings shared].shouldHideUncommentedRequests) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 2:
			{
				cell.textLabel.text = B(@"Move PRs that mention me\nto 'Participated'");
				if([Settings shared].autoParticipateInMentions) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
			}
			case 3:
			{
				cell.textLabel.text = B(@"Open PRs at first unread\ncomment");
				if([Settings shared].openPrAtFirstUnreadComment) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
				if([Settings shared].showReposInName) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 1:
            {
				cell.textLabel.text = B(@"Include repositories in\nfiltering");
				if([Settings shared].includeReposInFilter) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
			case 2:
			{
				cell.textLabel.text = B(@"Hide new repositories\nby default");
				if([Settings shared].hideNewRepositories) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
				cell.detailTextLabel.text = PR_HANDLING_POLICY[[Settings shared].mergeHandlingPolicy];
				break;
			}
			case 1:
			{
				cell.textLabel.text = B(@"When a PR is closed");
				cell.detailTextLabel.text = PR_HANDLING_POLICY[[Settings shared].closeHandlingPolicy];
				break;
			}
			case 2:
			{
				cell.textLabel.text = B(@"Don't keep PRs merged\nby me");
				if([Settings shared].dontKeepPrsMergedByMe) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
				if([Settings shared].dontAskBeforeWipingMerged) cell.accessoryType = UITableViewCellAccessoryCheckmark;
				break;
            }
            case 1:
            {
				cell.textLabel.text = @"Removing all closed PRs";
				if([Settings shared].dontAskBeforeWipingClosed) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
				if([Settings shared].sortDescending)
					cell.detailTextLabel.text = @"Reverse";
				else
					cell.detailTextLabel.text = @"Normal";
				break;
			}
			case 1:
			{
				cell.textLabel.text = @"Criterion";
				if([Settings shared].sortDescending)
					cell.detailTextLabel.text = SORT_REVERSE[[Settings shared].sortMethod];
				else
					cell.detailTextLabel.text = SORT_NORMAL[[Settings shared].sortMethod];
				break;
			}
			case 2:
			{
				cell.textLabel.text = @"Group by repository";
				if([Settings shared].groupByRepo) cell.accessoryType = UITableViewCellAccessoryCheckmark;
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
					if(f==[Settings shared].refreshPeriod) previousValue = count;
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
					if(f==[Settings shared].backgroundRefreshPeriod/60.0) previousValue = count;
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
					if(f==[Settings shared].newRepoCheckPeriod) previousValue = count;
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
				[Settings shared].showCreatedInsteadOfUpdated = ![Settings shared].showCreatedInsteadOfUpdated;
				break;
			}
			case 1:
			{
				[Settings shared].dontReportRefreshFailures = ![Settings shared].dontReportRefreshFailures;
				break;
			}
			case 2:
			{
				[Settings shared].hideAllPrsSection = ![Settings shared].hideAllPrsSection;
				break;
			}
			case 3:
			{
				[Settings shared].moveAssignedPrsToMySection = ![Settings shared].moveAssignedPrsToMySection;
				break;
			}
			case 4:
			{
				[Settings shared].markUnmergeableOnUserSectionsOnly = ![Settings shared].markUnmergeableOnUserSectionsOnly;
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
				[Settings shared].showCommentsEverywhere = ![Settings shared].showCommentsEverywhere;
				break;
			}
			case 1:
			{
				[Settings shared].shouldHideUncommentedRequests = ![Settings shared].shouldHideUncommentedRequests;
				break;
			}
			case 2:
			{
				[Settings shared].autoParticipateInMentions = ![Settings shared].autoParticipateInMentions;
				break;
			}
			case 3:
			{
				[Settings shared].openPrAtFirstUnreadComment = ![Settings shared].openPrAtFirstUnreadComment;
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
				[Settings shared].showReposInName = ![Settings shared].showReposInName;
				break;
			}
			case 1:
			{
				[Settings shared].includeReposInFilter = ![Settings shared].includeReposInFilter;
				break;
			}
			case 2:
			{
				[Settings shared].hideNewRepositories = ![Settings shared].hideNewRepositories;
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
				previousValue = [Settings shared].mergeHandlingPolicy;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
                valuesToPush = PR_HANDLING_POLICY;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 1:
			{
                selectedIndexPath = indexPath;
				previousValue = [Settings shared].closeHandlingPolicy;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
                valuesToPush = PR_HANDLING_POLICY;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 2:
			{
				[Settings shared].dontKeepPrsMergedByMe = ![Settings shared].dontKeepPrsMergedByMe;
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
				[Settings shared].dontAskBeforeWipingMerged = ![Settings shared].dontAskBeforeWipingMerged;
				break;
			}
			case 1:
			{
				[Settings shared].dontAskBeforeWipingClosed = ![Settings shared].dontAskBeforeWipingClosed;
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
				[Settings shared].sortDescending = ![Settings shared].sortDescending;
				[settingsChangedTimer push];
				[self.tableView reloadData];
				break;
			}
			case 1:
			{
				selectedIndexPath = indexPath;
				previousValue = [Settings shared].sortMethod;
				pickerName = [self.tableView cellForRowAtIndexPath:indexPath].textLabel.text;
				if([Settings shared].sortDescending)
					valuesToPush = SORT_REVERSE;
				else
					valuesToPush = SORT_NORMAL;
				[self performSegueWithIdentifier:@"showPicker" sender:self];
				break;
			}
			case 2:
			{
				[Settings shared].groupByRepo = ![Settings shared].groupByRepo;
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
			[Settings shared].refreshPeriod = indexPath.row*10+60;
		}
		else if(selectedIndexPath.row==1)
		{
			[Settings shared].backgroundRefreshPeriod = (indexPath.row*10+10)*60.0;
		}
		else if(selectedIndexPath.row==2)
		{
			[Settings shared].newRepoCheckPeriod = indexPath.row+1;
		}
	}
	else if(selectedIndexPath.section==SORT_SECTION_INDEX)
	{
		[Settings shared].sortMethod = indexPath.row;
		[settingsChangedTimer push];
	}
	else if(selectedIndexPath.section==HISTORY_SECTION_INDEX)
	{
		if(selectedIndexPath.row==0)
		{
			[Settings shared].mergeHandlingPolicy = indexPath.row;
		}
		else if(selectedIndexPath.row==1)
		{
			[Settings shared].closeHandlingPolicy = indexPath.row;
		}
	}
	[self.tableView reloadData];
	selectedIndexPath = nil;
}

@end
