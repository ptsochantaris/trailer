#import "PickerViewController.h"

@implementation PickerViewController
{
	BOOL layoutDone;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.values.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier forIndexPath:indexPath];
    cell.textLabel.text = self.values[indexPath.row];
	if(indexPath.row==self.previousValue)
		cell.accessoryType = UITableViewCellAccessoryCheckmark;
	else
		cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	self.view.userInteractionEnabled = NO;
	self.previousValue = indexPath.row;
	[self.tableView reloadData];
	double delayInSeconds = 0.1;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		[self.navigationController popViewControllerAnimated:YES];
		[self.delegate pickerViewController:self selectedIndexPath:indexPath];
	});
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return @"Please select an option";
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	if(!layoutDone)
	{
		[self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.previousValue inSection:0] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
		layoutDone = YES;
	}
}

@end
