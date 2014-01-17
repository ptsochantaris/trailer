
@implementation PullRequest

@dynamic url;
@dynamic number;
@dynamic state;
@dynamic title;
@dynamic body;
@dynamic issueCommentLink;
@dynamic reviewCommentLink;
@dynamic updatedAt;
@dynamic serverId;
@dynamic postSyncAction;
@dynamic webUrl;
@dynamic userId;
@dynamic latestReadCommentDate;
@dynamic repoId;
@dynamic merged;
@dynamic userAvatarUrl;
@dynamic userLogin;
@dynamic sectionIndex;
@dynamic totalComments;
@dynamic unreadComments;

+ (PullRequest *)pullRequestWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PullRequest *p = [DataItem itemWithInfo:info type:@"PullRequest" moc:moc];

	p.url = info[@"url"];
	p.webUrl = info[@"html_url"];
	p.number = info[@"number"];
	p.state = info[@"state"];
	p.title = info[@"title"];
	p.body = info[@"body"];
	p.userId = info[@"user"][@"id"];
	p.userLogin = info[@"user"][@"login"];
	p.userAvatarUrl = info[@"user"][@"avatar_url"];
	p.repoId = info[@"base"][@"repo"][@"id"];

	p.issueCommentLink = info[@"_links"][@"comments"][@"href"];
	p.reviewCommentLink = info[@"_links"][@"review_comments"][@"href"];

	return p;
}

- (void)postProcess
{
	if(self.merged.boolValue) self.sectionIndex = @kPullRequestSectionMerged;
	else if(self.isMine) self.sectionIndex = @kPullRequestSectionMine;
	else if(self.commentedByMe) self.sectionIndex = @kPullRequestSectionParticipated;
	else self.sectionIndex = @kPullRequestSectionAll;

	if(!self.latestReadCommentDate) self.latestReadCommentDate = [NSDate distantPast];

	NSInteger unreadCount = 0;
	BOOL autoParticipateInMentions = [Settings shared].autoParticipateInMentions && (!self.merged.boolValue);

	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	NSNumber *localUserId = @([Settings shared].localUserId.longLongValue);
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl == %@ and updatedAt > %@ and userId != %@",
				   self.url,
				   self.latestReadCommentDate,
				   localUserId];

	NSArray *unreadComments = [self.managedObjectContext executeFetchRequest:f error:nil];
	for(PRComment *c in unreadComments)
	{
		unreadCount++;
		if(autoParticipateInMentions && c.refersToMe)
			self.sectionIndex = @kPullRequestSectionParticipated;
	}

	self.unreadComments = @(unreadCount);

	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",self.url];
	self.totalComments = @([self.managedObjectContext countForFetchRequest:f error:nil]);
}

- (NSString *)sectionName
{
	return [kPullRequestSectionNames objectAtIndex:self.sectionIndex.integerValue];
}

+ (NSFetchRequest *)requestForPullRequestsWithFilter:(NSString *)filter
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];

	NSMutableArray *predicateSegments = [NSMutableArray array];

	if(filter.length)
	{
		[predicateSegments addObject:[NSString stringWithFormat:@"(title contains[cd] '%@' or userLogin contains[cd] '%@')",filter,filter]];
	}

	if([Settings shared].shouldHideUncommentedRequests)
	{
		[predicateSegments addObject:@"(unreadComments > 0)"];
	}

	if(predicateSegments.count) f.predicate = [NSPredicate predicateWithFormat:[predicateSegments componentsJoinedByString:@" and "]];

	NSMutableArray *sortDescriptors = [NSMutableArray arrayWithObject:[[NSSortDescriptor alloc] initWithKey:@"sectionIndex" ascending:YES]];
	NSString *fieldName = [Settings shared].sortField;
	BOOL ascending = ![Settings shared].sortDescending;
	if([fieldName isEqualToString:@"title"])
	{
		[sortDescriptors addObject:[NSSortDescriptor sortDescriptorWithKey:fieldName ascending:ascending selector:@selector(caseInsensitiveCompare:)]];
	}
	else if(fieldName.length)
	{
		[sortDescriptors addObject:[NSSortDescriptor sortDescriptorWithKey:fieldName ascending:ascending]];
	}

	f.sortDescriptors = sortDescriptors;
	return f;
}

+ (NSArray *)allMergedRequestsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.predicate = [NSPredicate predicateWithFormat:@"merged == YES"];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSUInteger)countUnmergedRequestsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.predicate = [NSPredicate predicateWithFormat:@"merged == NO or merged == nil"];
	return [moc countForFetchRequest:f error:nil];
}

-(void)prepareForDeletion
{
	[PRComment removeCommentsWithPullRequestURL:self.url inMoc:self.managedObjectContext];
}

+(PullRequest *)pullRequestWithUrl:(NSString *)url moc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.predicate = [NSPredicate predicateWithFormat:@"url == %@",url];
	return [[moc executeFetchRequest:f error:nil] lastObject];
}

-(void)catchUpWithComments
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl == %@",self.url];
	NSArray *res = [self.managedObjectContext executeFetchRequest:f error:nil];
	for(PRComment *c in res)
	{
		if(!self.latestReadCommentDate) self.latestReadCommentDate = c.updatedAt;
		else if([self.latestReadCommentDate compare:c.updatedAt]==NSOrderedAscending)
		{
			self.latestReadCommentDate = c.updatedAt;
		}
	}
	[self postProcess];
}

-(BOOL)isMine
{
	return [self.userId.stringValue isEqualToString:[Settings shared].localUserId];
}

-(BOOL)commentedByMe
{
	for(PRComment *c in [PRComment commentsForPullRequestUrl:self.url inMoc:self.managedObjectContext])
		if(c.isMine)
			return YES;
	return NO;

}

@end
