
@implementation PRComment

@dynamic serverId;
@dynamic postSyncAction;
@dynamic updatedAt;
@dynamic position;
@dynamic body;
@dynamic userName;
@dynamic avatarUrl;
@dynamic path;
@dynamic pullRequestUrl;
@dynamic url;
@dynamic userId;
@dynamic webUrl;

+ (PRComment *)commentWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PRComment *c = [DataItem itemWithInfo:info type:@"PRComment" moc:moc];
	if(c.postSyncAction.integerValue != kPostSyncDoNothing)
	{
		c.body = [info ofk:@"body"];
		c.position = [info ofk:@"position"];
		c.path = [info ofk:@"path"];
		c.url = [info ofk:@"url"];
		c.webUrl = [info ofk:@"html_url"];

		NSDictionary *userInfo = [info ofk:@"user"];
		c.userName = [userInfo ofk:@"userName"];
		c.userId = [userInfo ofk:@"id"];
		c.avatarUrl = [userInfo ofk:@"avatar_url"];

		NSDictionary *links = [info ofk:@"links"];
		c.url = [[links ofk:@"self"] ofk:@"href"];
		c.pullRequestUrl = [[links ofk:@"pull_request"] ofk:@"href"];
		if(!c.webUrl) c.webUrl = [[links ofk:@"html"] ofk:@"href"];
	}
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

+ (void)removeCommentsWithPullRequestURL:(NSString *)url inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",url];
	f.includesPropertyValues = NO;
	f.includesSubentities = NO;
	for(PRComment *c in [moc executeFetchRequest:f error:nil])
	{
		DLog(@"  Deleting comment ID %@",c.serverId);
		[moc deleteObject:c];
	}
}

+ (NSArray *)commentsForPullRequestUrl:(NSString *)url inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",url];
	return [moc executeFetchRequest:f error:nil];
}

@end
