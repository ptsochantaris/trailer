
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
@dynamic repoName;
@dynamic mergeable;
@dynamic statusesLink;
@dynamic assignedToMe;
@dynamic issueUrl;
@dynamic reopened;

static NSDateFormatter *itemDateFormatter;

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		itemDateFormatter = [[NSDateFormatter alloc] init];
		itemDateFormatter.dateStyle = NSDateFormatterShortStyle;
		itemDateFormatter.timeStyle = NSDateFormatterShortStyle;
	});
}

+ (PullRequest *)pullRequestWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PullRequest *p = [DataItem itemWithInfo:info type:@"PullRequest" moc:moc];
	if(p.postSyncAction.integerValue != kPostSyncDoNothing)
	{
		p.url = [info ofk:@"url"];
		p.webUrl = [info ofk:@"html_url"];
		p.number = [info ofk:@"number"];
		p.state = [info ofk:@"state"];
		p.title = [info ofk:@"title"];
		p.body = [info ofk:@"body"];

		NSNumber *m = [info ofk:@"mergeable"];
		if(!m) m = @YES;
		p.mergeable = m;

		NSDictionary *userInfo = [info ofk:@"user"];
		p.userId = [userInfo ofk:@"id"];
		p.userLogin = [userInfo ofk:@"login"];
		p.userAvatarUrl = [userInfo ofk:@"avatar_url"];

		p.repoId = [[[info ofk:@"base"] ofk:@"repo"] ofk:@"id"];

		NSDictionary *linkInfo = [info ofk:@"_links"];
		p.issueCommentLink = [[linkInfo ofk:@"comments"] ofk:@"href"];
		p.reviewCommentLink = [[linkInfo ofk:@"review_comments"] ofk:@"href"];
		p.statusesLink = [[linkInfo ofk:@"statuses"] ofk:@"href"];
		p.issueUrl = [[linkInfo ofk:@"issue"] ofk:@"href"];
	}

	p.reopened = @(p.condition.integerValue == kPullRequestConditionClosed);
	p.condition = @kPullRequestConditionOpen;

	return p;
}

- (void)postProcess
{
	NSInteger section;
	NSInteger condition = self.condition.integerValue;

	if(condition==kPullRequestConditionMerged)		section = kPullRequestSectionMerged;
	else if(condition==kPullRequestConditionClosed) section = kPullRequestSectionClosed;
	else if(self.isMine)							section = kPullRequestSectionMine;
	else if(self.commentedByMe)						section = kPullRequestSectionParticipated;
	else if([Settings shared].hideAllPrsSection)	section = kPullRequestSectionNone;
	else											section = kPullRequestSectionAll;

	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.returnsObjectsAsFaults = NO;

	NSDate *latestDate = self.latestReadCommentDate;

	if(((section == kPullRequestSectionAll) || (section == kPullRequestSectionNone))
	   && [Settings shared].autoParticipateInMentions)
	{
		if(self.refersToMe)
		{
			section = kPullRequestSectionParticipated;
			f.predicate = [self predicateForOthersCommentsSinceDate:latestDate];
			self.unreadComments = @([self.managedObjectContext countForFetchRequest:f error:nil]);
		}
		else
		{
			f.predicate = [self predicateForOthersCommentsSinceDate:nil];
			NSUInteger unreadCommentCount = 0;
			NSArray *allOthersComments = [self.managedObjectContext executeFetchRequest:f error:nil];
			for(PRComment *c in allOthersComments)
			{
				if(c.refersToMe)
				{
					section = kPullRequestSectionParticipated;
				}
				if([c.createdAt compare:latestDate]==NSOrderedDescending)
				{
					unreadCommentCount++;
				}
			}
			self.unreadComments = @(unreadCommentCount);
		}
	}
	else
	{
		f.predicate = [self predicateForOthersCommentsSinceDate:latestDate];
		self.unreadComments = @([self.managedObjectContext countForFetchRequest:f error:nil]);
	}

	self.sectionIndex = @(section);

	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",self.url];
	self.totalComments = @([self.managedObjectContext countForFetchRequest:f error:nil]);

	if(self.repoId)
		self.repoName = [[Repo itemOfType:@"Repo" serverId:self.repoId moc:self.managedObjectContext] fullName];
	else
		self.repoName = @"Unknown repository";

	if(!self.title) self.title = @"(No title)";
}

- (BOOL)markUnmergeable
{
	if(!self.mergeable.boolValue)
	{
		NSInteger section = self.sectionIndex.integerValue;

		if(section == kPullRequestSectionClosed || section == kPullRequestSectionMerged)
			return NO;

		if(section == kPullRequestSectionAll &&
		   [Settings shared].markUnmergeableOnUserSectionsOnly)
			return NO;

		return YES;
	}
	return NO;
}

- (BOOL)refersToMe
{
	NSString *myHandle = [NSString stringWithFormat:@"@%@",[Settings shared].localUser];
	NSRange rangeOfHandle = [self.body rangeOfString:myHandle options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch];
	return rangeOfHandle.location != NSNotFound;
}

- (NSString *)sectionName
{
	return [kPullRequestSectionNames objectAtIndex:self.sectionIndex.integerValue];
}

- (NSString *)subtitle
{
	NSString *_subtitle;

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
	#define SEPARATOR @"\n"
#else
	#define SEPARATOR @" - "
#endif

	if(self.userLogin.length)
		_subtitle = [NSString stringWithFormat:@"%@%@",self.userLogin,SEPARATOR];
	else
		_subtitle = @"";

	if([Settings shared].showCreatedInsteadOfUpdated)
		_subtitle = [_subtitle stringByAppendingString:[itemDateFormatter stringFromDate:self.createdAt]];
	else
		_subtitle = [_subtitle stringByAppendingString:[itemDateFormatter stringFromDate:self.updatedAt]];

	if([Settings shared].showReposInName)
		_subtitle = [_subtitle stringByAppendingFormat:@"%@%@",SEPARATOR,self.repoName];

#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
	if(!self.mergeable.boolValue)
		_subtitle = [_subtitle stringByAppendingString:@"\nCannot be merged!"];
#endif

	return _subtitle;
}

+ (NSFetchRequest *)requestForPullRequestsWithFilter:(NSString *)filter
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.returnsObjectsAsFaults = NO;

	NSMutableArray *predicateSegments = [NSMutableArray arrayWithObject:@"(sectionIndex > 0)"];

	if(filter.length)
	{
		if([Settings shared].includeReposInFilter)
			[predicateSegments addObject:[NSString stringWithFormat:@"(title contains[cd] '%@' or userLogin contains[cd] '%@' or repoName contains[cd] '%@')",filter,filter,filter]];
		else
			[predicateSegments addObject:[NSString stringWithFormat:@"(title contains[cd] '%@' or userLogin contains[cd] '%@')",filter,filter]];
	}

	if([Settings shared].shouldHideUncommentedRequests)
	{
		[predicateSegments addObject:@"(unreadComments > 0)"];
	}

	if(predicateSegments.count) f.predicate = [NSPredicate predicateWithFormat:[predicateSegments componentsJoinedByString:@" and "]];

	NSMutableArray *sortDescriptors = [NSMutableArray arrayWithObject:[[NSSortDescriptor alloc] initWithKey:@"sectionIndex" ascending:YES]];

	if([Settings shared].groupByRepo)
	{
		[sortDescriptors addObject:[NSSortDescriptor sortDescriptorWithKey:@"repoName" ascending:YES selector:@selector(caseInsensitiveCompare:)]];
	}

	BOOL ascending = ![Settings shared].sortDescending;
	NSString *fieldName = [Settings shared].sortField;
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
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"condition == %d",kPullRequestConditionMerged];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)allClosedRequestsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"condition == %d",kPullRequestConditionClosed];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSUInteger)countOpenRequestsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.predicate = [NSPredicate predicateWithFormat:@"condition == %d or condition == nil",kPullRequestConditionOpen];
	return [moc countForFetchRequest:f error:nil];
}

+ (NSInteger)badgeCountInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [PullRequest requestForPullRequestsWithFilter:nil];
	NSArray *allPRs = [moc executeFetchRequest:f error:nil];
	NSInteger count = 0;
	BOOL showCommentsEverywhere = [Settings shared].showCommentsEverywhere;
	for(PullRequest *r in allPRs)
	{
		NSInteger sectionIndex = r.sectionIndex.integerValue;
		if(showCommentsEverywhere ||
		   sectionIndex==kPullRequestSectionMine ||
		   sectionIndex==kPullRequestSectionParticipated)
		{
			count += r.unreadComments.integerValue;
		}
	}
	return count;
}

- (void)prepareForDeletion
{
    NSNumber *sid = self.serverId;
    if(sid)
    {
        NSManagedObjectContext *moc = self.managedObjectContext;
        [PRComment removeCommentsWithPullRequestURL:self.url inMoc:moc];
        [PRStatus removeStatusesWithPullRequestId:sid inMoc:moc];
    }
	[super prepareForDeletion];
}

+ (PullRequest *)pullRequestWithUrl:(NSString *)url moc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.returnsObjectsAsFaults = NO;
	f.fetchLimit = 1;
	f.predicate = [NSPredicate predicateWithFormat:@"url == %@",url];
	return [[moc executeFetchRequest:f error:nil] lastObject];
}

+ (NSArray *)pullRequestsForRepoId:(NSNumber *)repoId inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"repoId == %@",repoId];
	return [moc executeFetchRequest:f error:nil];
}

- (void)catchUpWithComments
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.returnsObjectsAsFaults = NO;
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

- (BOOL)isMine
{
	if(self.assignedToMe.boolValue && [Settings shared].moveAssignedPrsToMySection) return YES;
	return [self.userId.stringValue isEqualToString:[Settings shared].localUserId];
}

- (BOOL)commentedByMe
{
	for(PRComment *c in [PRComment commentsForPullRequestUrl:self.url inMoc:self.managedObjectContext])
		if(c.isMine)
			return YES;
	return NO;

}

- (NSArray *)displayedStatuses
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRStatus"];
	f.returnsObjectsAsFaults = NO;

	NSString *predicate = [NSString stringWithFormat:@"pullRequestId = %@",self.serverId];

	NSInteger mode = [Settings shared].statusFilteringMode;
	if(mode!=kStatusFilterAll)
	{
		NSArray *terms = [Settings shared].statusFilteringTerms;
		if(terms.count)
		{
			NSMutableArray *ors = [NSMutableArray arrayWithCapacity:terms.count];
			for(NSString *term in terms)
			{
				[ors addObject:[NSString stringWithFormat:@"descriptionText contains[cd] '%@'",term]];
			}
			if(mode==kStatusFilterInclude)
				predicate = [predicate stringByAppendingFormat:@" and (%@)",[ors componentsJoinedByString:@" or "]];
			else
				predicate = [predicate stringByAppendingFormat:@" and (not (%@))",[ors componentsJoinedByString:@" or "]];
		}
	}

	f.predicate = [NSPredicate predicateWithFormat:predicate];
	f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
	NSArray *ret = [self.managedObjectContext executeFetchRequest:f error:nil];
	NSMutableArray *result = [NSMutableArray array];
	NSMutableSet *targetUrls = [NSMutableSet set];
	NSMutableSet *descriptions = [NSMutableSet set];
	for(PRStatus *s in ret)
	{
		NSString *targetUrl = s.targetUrl;
		if(!targetUrl) targetUrl = @"";

		NSString *desc = s.descriptionText;
		if(!desc) desc = @"(No status description)";

		if(![descriptions containsObject:desc])
		{
			[descriptions addObject:desc];
			if(![targetUrls containsObject:targetUrl])
			{
				[targetUrls addObject:targetUrl];
				[result addObject:s];
			}
		}
	}
	return result;
}

- (NSString *)urlForOpening
{
	if (self.unreadComments.integerValue != 0 && [Settings shared].openPrAtFirstUnreadComment)
	{
		NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
		f.returnsObjectsAsFaults = NO;
		f.fetchLimit = 1;
		f.predicate = [self predicateForOthersCommentsSinceDate:self.latestReadCommentDate];
		f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]];
		NSArray *ret = [self.managedObjectContext executeFetchRequest:f error:nil];
		if (ret.count > 0)
		{
			PRComment *comment = (PRComment *)ret[0];
			return comment.webUrl;
		}
	}
	return self.webUrl;
}

- (NSPredicate *)predicateForOthersCommentsSinceDate:(NSDate *)date
{
	if(date)
	{
		return [NSPredicate predicateWithFormat:@"userId != %lld and pullRequestUrl == %@ and createdAt > %@",
				[Settings shared].localUserId.longLongValue,
				self.url,
				date];
	}
	else
	{
		return [NSPredicate predicateWithFormat:@"userId != %lld and pullRequestUrl == %@",
				[Settings shared].localUserId.longLongValue,
				self.url];
	}
}

@end
