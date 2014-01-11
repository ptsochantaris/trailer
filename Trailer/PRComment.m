
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

+(PRComment *)commentWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
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

-(BOOL)isMine
{
	return [self.userId.stringValue isEqualToString:[Settings shared].localUserId];
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

+(NSInteger)countCommentsForPullRequestUrl:(NSString *)url inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",url];
	return [moc countForFetchRequest:f error:nil];
}

+(NSArray *)commentsForPullRequestUrl:(NSString *)url inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",url];
	return [moc executeFetchRequest:f error:nil];
}

@end
