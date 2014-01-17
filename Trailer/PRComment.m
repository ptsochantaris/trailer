
@implementation PRComment

@dynamic serverId;
@dynamic postSyncAction;
@dynamic updatedAt;
@dynamic position;
@dynamic body;
@dynamic userName;
@dynamic path;
@dynamic pullRequestUrl;
@dynamic url;
@dynamic userId;
@dynamic webUrl;

+ (PRComment *)commentWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PRComment *c = [DataItem itemWithInfo:info type:@"PRComment" moc:moc];

	c.body = info[@"body"];
	c.position = [info ofk:@"position"];
	c.body = info[@"body"];
	c.path = info[@"path"];
	c.url = info[@"url"];
	c.userName = info[@"user"][@"userName"];
	c.userId = info[@"user"][@"id"];
	c.url = info[@"_links"][@"self"][@"href"];
	c.pullRequestUrl = info[@"_links"][@"pull_request"][@"href"];
	c.webUrl = info[@"html_url"];
	if(!c.webUrl) c.webUrl = info[@"_links"][@"html"][@"href"];

	return c;
}

- (BOOL)isMine
{
	return [self.userId.stringValue isEqualToString:[Settings shared].localUserId];
}

- (BOOL)refersToMe
{
	NSString *myHandle = [NSString stringWithFormat:@"@%@",[Settings shared].localUser];
	NSRange rangeOfHandle = [self.body rangeOfString:myHandle options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch];
	return rangeOfHandle.location != NSNotFound;
}

+(void)removeCommentsWithPullRequestURL:(NSString *)url inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",url];
	for(PRComment *c in [moc executeFetchRequest:f error:nil])
	{
		DLog(@"  Deleting comment ID %@",c.serverId);
		[moc deleteObject:c];
	}
}

+(NSArray *)commentsForPullRequestUrl:(NSString *)url inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",url];
	return [moc executeFetchRequest:f error:nil];
}

@end
