//
//  PullRequest.m
//  Trailer
//
//  Created by Paul Tsochantaris on 27/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

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

+(PullRequest *)pullRequestWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PullRequest *p = [DataItem itemWithInfo:info type:@"PullRequest" moc:moc];

	p.url = info[@"url"];
	p.webUrl = info[@"html_url"];
	p.number = info[@"number"];
	p.state = info[@"state"];
	p.title = info[@"title"];
	p.body = info[@"body"];
	p.userId = info[@"user"][@"id"];
	p.repoId = info[@"base"][@"repo"][@"id"];

	p.issueCommentLink = info[@"_links"][@"comments"][@"href"];
	p.reviewCommentLink = info[@"_links"][@"review_comments"][@"href"];
	return p;
}

+(NSArray *)pullRequestsSortedByField:(NSString *)fieldName
							   filter:(NSString *)filter
							ascending:(BOOL)ascending
								inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	if(filter.length)
	{
		f.predicate = [NSPredicate predicateWithFormat:@"title contains[cd] %@",filter];
	}
	if([fieldName isEqualToString:@"title"])
	{
		f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:fieldName ascending:ascending selector:@selector(caseInsensitiveCompare:)]];
	}
	else
	{
		f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:fieldName ascending:ascending]];
	}
	return [moc executeFetchRequest:f error:nil];
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
	f.predicate = [NSPredicate predicateWithFormat:@"merged != YES"];
	return [moc countForFetchRequest:f error:nil];
}

-(void)prepareForDeletion
{
	[PRComment removeCommentsWithPullRequestURL:self.url inMoc:self.managedObjectContext];
}

-(NSInteger)unreadCommentCount
{
	if(!self.latestReadCommentDate) self.latestReadCommentDate = [NSDate distantPast];
	
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl == %@ and updatedAt > %@",self.url,self.latestReadCommentDate];
	NSArray *res = [self.managedObjectContext executeFetchRequest:f error:nil];

	NSInteger unreadCount = 0;
	for(PRComment *c in res)
		if(!c.isMine) // don't count my comments
			unreadCount++;

	return unreadCount;
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
}

-(BOOL)isMine
{
	return [self.userId.stringValue isEqualToString:[AppDelegate shared].api.localUserId];
}

-(BOOL)commentedByMe
{
	for(PRComment *c in [PRComment commentsForPullRequestUrl:self.url inMoc:self.managedObjectContext])
		if(c.isMine)
			return YES;
	return NO;

}

@end
