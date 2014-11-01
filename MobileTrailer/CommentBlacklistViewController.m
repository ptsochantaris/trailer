
@implementation CommentBlacklistViewController

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return settings.commentAuthorBlacklist.count == 0 ? 0 : 1; }

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return settings.commentAuthorBlacklist.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"UsernameCell" forIndexPath:indexPath];
	cell.textLabel.text = settings.commentAuthorBlacklist[indexPath.row];
	return cell;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	if(editingStyle==UITableViewCellEditingStyleDelete)
	{
		NSMutableArray *blackList = [settings.commentAuthorBlacklist mutableCopy];
		[blackList removeObjectAtIndex:indexPath.row];
		settings.commentAuthorBlacklist = blackList;
		if(blackList.count==0) // last delete
			[tableView deleteSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
		else
			[tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
	}
}

- (IBAction)addSelected:(UIBarButtonItem *)sender
{
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Block commenter"
															   message:@"Enter the username of the poster whose comments you don't want to be notified about"
														preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *textField) {
		textField.placeholder = @"Username";
	}];
	[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"Block" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *name = [[a.textFields[0] text] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if([name rangeOfString:@"@"].location==0) name = [name substringFromIndex:1];
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			if(name.length>0 && ![settings.commentAuthorBlacklist containsObject:name])
			{
				NSMutableArray *blackList = [settings.commentAuthorBlacklist mutableCopy];
				[blackList addObject:name];
				settings.commentAuthorBlacklist = blackList;
				NSIndexPath *ip = [NSIndexPath indexPathForRow:blackList.count-1 inSection:0];
				if(blackList.count==1) // first insert
					[self.tableView insertSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationAutomatic];
				else
					[self.tableView insertRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationAutomatic];
			}
		});
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

@end
