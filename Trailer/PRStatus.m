
@implementation PRStatus

@dynamic state;
@dynamic targetUrl;
@dynamic descriptionText;
@dynamic createdAt;
@dynamic serverId;
@dynamic updatedAt;
@dynamic url;
@dynamic userId;
@dynamic userName;
@dynamic pullRequestId;

+ (PRStatus *)statusWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PRStatus *s = [DataItem itemWithInfo:info type:@"PRStatus" moc:moc];
	if(s.postSyncAction.integerValue != kPostSyncDoNothing)
	{
		s.url = [info ofk:@"url"];
		s.state = [info ofk:@"state"];
		s.targetUrl = [info ofk:@"target_url"];
		s.descriptionText = [info ofk:@"description"];

		NSDictionary *userInfo = [info ofk:@"creator"];
		s.userName = [userInfo ofk:@"login"];
		s.userId = [userInfo ofk:@"id"];
	}
	return s;
}

+ (NSArray *)statusesForPullRequestId:(NSNumber *)pullRequestId inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRStatus"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestId = %@",pullRequestId];
	return [moc executeFetchRequest:f error:nil];
}

- (COLOR_CLASS *)colorForDisplay
{
	static COLOR_CLASS *STATUS_RED, *STATUS_YELLOW, *STATUS_GREEN;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		STATUS_RED = MAKECOLOR(0.5, 0.2, 0.2, 1.0);
		STATUS_YELLOW = MAKECOLOR(0.6, 0.5, 0.0, 1.0);
		STATUS_GREEN = MAKECOLOR(0.3, 0.5, 0.3, 1.0);
	});

	if([self.state isEqualToString:@"pending"])
		return STATUS_YELLOW;
	else if([self.state isEqualToString:@"success"])
		return STATUS_GREEN;
	else
		return STATUS_RED;
}

- (NSString *)displayText
{
	static NSDateFormatter *dateFormatter;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dateFormatter = [[NSDateFormatter alloc] init];
		dateFormatter.dateStyle = NSDateFormatterShortStyle;
		dateFormatter.timeStyle = NSDateFormatterShortStyle;
	});
	NSString *desc = self.descriptionText;
	if(!desc) desc = @"(No description)";
	return [NSString stringWithFormat:@"%@ %@",[dateFormatter stringFromDate:self.createdAt],desc];
}

+ (void)removeStatusesWithPullRequestId:(NSNumber *)pullRequestId inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRStatus"];
	f.includesPropertyValues = NO;
	f.includesSubentities = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestId = %@",pullRequestId];
	for(PRStatus *s in [moc executeFetchRequest:f error:nil])
	{
		DLog(@"  Deleting status ID %@",s.serverId);
		[moc deleteObject:s];
	}
}

@end
