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

+(NSArray *)sortedPullRequestsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PullRequest"];
	f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:NO]];
	return [moc executeFetchRequest:f error:nil];
}

-(void)prepareForDeletion
{
	Repo *parent = [Repo itemOfType:@"Repo" serverId:self.repoId moc:self.managedObjectContext];
	if(parent && parent.postSyncAction.integerValue!=kTouchedDelete && self.isMine)
	{
		[[AppDelegate shared] postNotificationOfType:kPrMerged forPr:self infoText:nil];
	}
	[PRComment removeCommentsWithPullRequestURL:self.url inMoc:self.managedObjectContext];
}

-(NSInteger)unreadCommentCount
{
	if(!self.latestReadCommentDate) return [PRComment countCommentsForPullRequestUrl:self.url inMoc:self.managedObjectContext];
	
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl == %@ and updatedAt > %@",self.url,self.latestReadCommentDate];
	NSArray *res = [self.managedObjectContext executeFetchRequest:f error:nil];
	return res.count;
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
	long long localUserId = [AppDelegate shared].api.localUserId.longLongValue;
	if(self.userId.longLongValue == localUserId) return YES;
	for(PRComment *c in [PRComment commentsForPullRequestUrl:self.url inMoc:self.managedObjectContext])
	{
		if(c.userId.longLongValue == localUserId) return YES;
	}
	return NO;
}

@end
