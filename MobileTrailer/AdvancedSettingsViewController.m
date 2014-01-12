
@interface AdvancedSettingsViewController () <PickerViewControllerDelegate>
{
	HTPopTimer *settingsChangedAnnounceTimer;

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
	settingsChangedAnnounceTimer = [[HTPopTimer alloc] initWithTimeInterval:1.0 target:self selector:@selector(postChangeNotification)];
}

- (void)postChangeNotification
{
	[[NSNotificationCenter defaultCenter] postNotificationName:DISPLAY_OPTIONS_UPDATED_KEY object:nil];
}

#define SORT_REVERSE @[@"Newest first",@"Most recently active",@"Reverse alphabetically"]
#define SORT_NORMAL @[@"Oldest first",@"Inactive for longest",@"Alphabetically"]

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
	if(indexPath.section==0)
	{
		switch (indexPath.row) {
			case 0:
			{
				if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
					cell.textLabel.text = [NSString stringWithFormat:@"Foreground refresh interval"];
				else
					cell.textLabel.text = [NSString stringWithFormat:@"Foreground refresh\ninterval"];

				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f seconds",[Settings shared].refreshPeriod];
				break;
			}
			case 1:
			{
				if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
					cell.textLabel.text = [NSString stringWithFormat:@"Background refresh interval (minimum)"];
				else
					cell.textLabel.text = [NSString stringWithFormat:@"Background refresh\ninterval (minimum)"];
				cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f minutes",[Settings shared].backgroundRefreshPeriod/60.0];
				break;
			}
		}
	}
	else if(indexPath.section==1)
	{
		switch (indexPath.row) {
			case 0:
			{
				if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
					cell.textLabel.text = [NSString stringWithFormat:@"Display creation instead of activity times"];
				else
					cell.textLabel.text = [NSString stringWithFormat:@"Display creation instead\nof activity times"];
				cell.detailTextLabel.text = [self yesNo:[Settings shared].showCreatedInsteadOfUpdated];
				break;
			}
			case 1:
			{
				if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
					cell.textLabel.text = [NSString stringWithFormat:@"Display new badges and alerts for all PRs"];
				else
					cell.textLabel.text = [NSString stringWithFormat:@"Display new badges\nand alerts for all PRs"];
				cell.detailTextLabel.text = [self yesNo:[Settings shared].showCommentsEverywhere];
				break;
			}
			case 2:
			{
				if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
					cell.textLabel.text = [NSString stringWithFormat:@"Only display PRs with unread comments"];
				else
					cell.textLabel.text = [NSString stringWithFormat:@"Only display PRs\nwith unread comments"];
				cell.detailTextLabel.text = [self yesNo:[Settings shared].shouldHideUncommentedRequests];
				break;
			}
			case 3:
			{
				if(UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
					cell.textLabel.text = [NSString stringWithFormat:@"Don't keep PRs merged by me"];
				else
					cell.textLabel.text = [NSString stringWithFormat:@"Don't keep PRs\nmerged by me"];
				cell.detailTextLabel.text = [self yesNo:[Settings shared].dontKeepMyPrs];
				break;
			}
		}
	}
	else if(indexPath.section==2)
	{
		switch (indexPath.row) {
			case 0:
			{
				cell.textLabel.text = [NSString stringWithFormat:@"Sort by"];
				if([Settings shared].sortDescending)
					cell.detailTextLabel.text = SORT_REVERSE[[Settings shared].sortMethod];
				else
					cell.detailTextLabel.text = SORT_NORMAL[[Settings shared].sortMethod];
				break;
			}
			case 1:
			{
				cell.textLabel.text = [NSString stringWithFormat:@"Sort direction"];
				if([Settings shared].sortDescending)
					cell.detailTextLabel.text = @"Reverse";
				else
					cell.detailTextLabel.text = @"Normal";
				break;
			}
		}
	}
	return cell;
}

- (NSString *)yesNo:(BOOL)option
{
	if(option) return @"YES"; else return @"NO";
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(indexPath.section==0)
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
				for(NSInteger f=30;f<3600;f+=10)
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
					if(f==[Settings shared].backgroundRefreshPeriod/60) previousValue = count;
					[values addObject:[NSString stringWithFormat:@"%ld minutes",(long)f]];
					count++;
				}
				break;
			}
		}
		valuesToPush = values;
		[self performSegueWithIdentifier:@"showPicker" sender:self];
	}
	else if(indexPath.section==1)
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
				[Settings shared].showCommentsEverywhere = ![Settings shared].showCommentsEverywhere;
				break;
			}
			case 2:
			{
				[Settings shared].shouldHideUncommentedRequests = ![Settings shared].shouldHideUncommentedRequests;
				break;
			}
			case 3:
			{
				[Settings shared].dontKeepMyPrs = ![Settings shared].dontKeepMyPrs;
				break;
			}
		}
		[settingsChangedAnnounceTimer push];
	}
	else if(indexPath.section==2)
	{
		switch (indexPath.row)
		{
			case 1:
			{
				[Settings shared].sortDescending = ![Settings shared].sortDescending;
				[settingsChangedAnnounceTimer push];
				[self.tableView reloadData];
				break;
			}
			case 0:
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
		}
	}
	[tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    switch (section) {
		case 0: return 2; // refresh period, background refresh
		case 1: return 4; // toggled options (4)
		case 2: return 2; // sorting category, sorting direction
	}
	return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    switch (section) {
		case 0: return @"Auto Refresh"; // refresh period, background refresh
		case 1: return @"Options"; // toggled options (4)
		case 2: return @"Sorting"; // sorting category, sorting direction
	}
	return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 3;
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
	if(selectedIndexPath.section==0)
	{
		if(selectedIndexPath.row==0)
		{
			[Settings shared].refreshPeriod = indexPath.row*10+30;
		}
		else if(selectedIndexPath.row==1)
		{
			[Settings shared].backgroundRefreshPeriod = (indexPath.row*10+10)*60.0;
		}
	}
	else if(selectedIndexPath.section==2)
	{
		[Settings shared].sortMethod = indexPath.row;
		[settingsChangedAnnounceTimer push];
	}
	[self.tableView reloadData];
	selectedIndexPath = nil;
}

@end
