
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
@dynamic condition;
@dynamic userAvatarUrl;
@dynamic userLogin;
@dynamic sectionIndex;
@dynamic totalComments;
@dynamic unreadComments;

+ (PullRequest *)pullRequestWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PullRequest *p = [DataItem itemWithInfo:info type:@"PullRequest" moc:moc];

	p.url = [info ofk:@"url"];
	p.webUrl = [info ofk:@"html_url"];
	p.number = [info ofk:@"number"];
	p.state = [info ofk:@"state"];
	p.title = [info ofk:@"title"];
	p.body = [info ofk:@"body"];

	NSDictionary *userInfo = [info ofk:@"user"];
	p.userId = [userInfo ofk:@"id"];
	p.userLogin = [userInfo ofk:@"login"];
	p.userAvatarUrl = [userInfo ofk:@"avatar_url"];

	p.repoId = [[[info ofk:@"base"] ofk:@"repo"] ofk:@"id"];

	NSDictionary *linkInfo = [info ofk:@"_links"];
	p.issueCommentLink = [[linkInfo ofk:@"comments"] ofk:@"href"];
	p.reviewCommentLink = [[linkInfo ofk:@"review_comments"] ofk:@"href"];
	
	p.condition = @kPullRequestConditionOpen;

	return p;
}

- (void)postProcess
{
	if(self.condition.integerValue==kPullRequestConditionMerged) self.sectionIndex = @kPullRequestSectionMerged;
	else if(self.condition.integerValue==kPullRequestConditionClosed) self.sectionIndex = @kPullRequestSectionClosed;
	else if(self.isMine) self.sectionIndex = @kPullRequestSectionMine;
	else if(self.commentedByMe) self.sectionIndex = @kPullRequestSectionParticipated;
	else self.sectionIndex = @kPullRequestSectionAll;

	if(!self.latestReadCommentDate) self.latestReadCommentDate = [NSDate distantPast];

	NSInteger unreadCount = 0;
	BOOL autoParticipateInMentions = [Settings shared].autoParticipateInMentions && (self.condition.integerValue==kPullRequestConditionOpen);

	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	NSNumber *localUserId = @([Settings shared].localUserId.longLongValue);
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl == %@ and createdAt > %@ and userId != %@",
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
	f.predicate = [NSPredicate predicateWithFormat:@"condition == %@",@kPullRequestConditionMerged];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)allClosedRequestsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.predicate = [NSPredicate predicateWithFormat:@"condition == %@",@kPullRequestConditionClosed];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSUInteger)countOpenRequestsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.predicate = [NSPredicate predicateWithFormat:@"condition == %@ or condition == nil",@kPullRequestConditionOpen];
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
		NSDate *commentCreation = c.createdAt;
		if(!self.latestReadCommentDate || [self.latestReadCommentDate compare:commentCreation]==NSOrderedAscending)
		{
			self.latestReadCommentDate = commentCreation;
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
