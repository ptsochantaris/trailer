
@interface ServersViewController ()
{
	NSManagedObjectID *selectedServerId;
	NSMutableArray *allServers;
	NSDateFormatter *resetFormatter;
}
@end

@implementation ServersViewController

- (IBAction)done:(UIBarButtonItem *)sender
{
	if(app.preferencesDirty) [app startRefresh];
	[self dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.clearsSelectionOnViewWillAppear = YES;
	resetFormatter = [[NSDateFormatter alloc] init];
	resetFormatter.doesRelativeDateFormatting = YES;
	resetFormatter.timeStyle = NSDateFormatterShortStyle;
	resetFormatter.dateStyle = NSDateFormatterShortStyle;

	[[NSNotificationCenter defaultCenter] addObserver:self.tableView
											 selector:@selector(reloadData)
												 name:REFRESH_ENDED_NOTIFICATION
											   object:nil];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self.tableView];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];
	allServers = [[ApiServer allApiServersInMoc:app.dataManager.managedObjectContext] mutableCopy];
	[self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	return allServers.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"ServerCell" forIndexPath:indexPath];
	ApiServer *a = allServers[indexPath.row];
	if(a.authToken.length==0)
	{
		cell.textLabel.textColor = [UIColor redColor];
		cell.textLabel.text = [a.label stringByAppendingString:@" (needs token!)"];
	}
	else if(!a.lastSyncSucceeded.boolValue)
	{
		cell.textLabel.textColor = [UIColor redColor];
		cell.textLabel.text = [a.label stringByAppendingString:@" (last sync failed)"];
	}
	else
	{
		cell.textLabel.textColor = [UIColor darkTextColor];
		cell.textLabel.text = a.label;
	}
	if(a.requestsLimit.doubleValue==0.0)
	{
		cell.detailTextLabel.text = nil;
	}
	else
	{
		double total = a.requestsLimit.doubleValue;
		double used = total-a.requestsRemaining.doubleValue;
		if(a.resetDate)
		{
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%.01f%% API used (%.0f / %.0f requests)\nNext reset: %@",
										 100*used/total, used, total, [resetFormatter stringFromDate:a.resetDate]];
		}
		else
		{
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%.01f%% API used (%.0f / %.0f requests)",
										 100*used/total, used, total];
		}
	}
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete)
	{
		ApiServer *a = allServers[indexPath.row];
		[allServers removeObjectAtIndex:indexPath.row];
		[app.dataManager.managedObjectContext deleteObject:a];
		[app.dataManager saveDB];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	ApiServer *a = allServers[indexPath.row];
	selectedServerId = a.objectID;
	[self performSegueWithIdentifier:@"editServer" sender:self];
}

- (IBAction)newServer:(UIBarButtonItem *)sender
{
	[self performSegueWithIdentifier:@"editServer" sender:self];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
	ServerDetailViewController *sd = [segue destinationViewController];
	sd.serverId = selectedServerId;
	selectedServerId = nil;
}

@end
