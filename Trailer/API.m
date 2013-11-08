//
//  API.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface API ()
{
	AFHTTPClient *client;
	NSDateFormatter *dateFormatter;
}
@end

@implementation API

- (id)init
{
    self = [super init];
    if (self) {
		dateFormatter = [[NSDateFormatter alloc] initWithDateFormat:@"YYYY-MM-DDTHH:MM:SSZ" allowNaturalLanguage:NO];

		[[AFHTTPRequestOperationLogger sharedLogger] startLogging];

		client = [AFHTTPClient clientWithBaseURL:[NSURL URLWithString:@"https://api.github.com"]];
		[client setDefaultHeader:@"User-Agent" value:@"Trailer"];
		[client setDefaultHeader:@"Content-Type" value:@"application/x-www-form-urlencoded"];
		if(self.authToken) [client setDefaultHeader:@"Authorization" value:[@"token " stringByAppendingString:self.authToken]];
		client.operationQueue.maxConcurrentOperationCount = 8;
    }
    return self;
}

-(void)storeDefaultValue:(id)value forKey:(NSString *)key
{
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if(value)
		[d setObject:value forKey:key];
	else
		[d removeObjectForKey:key];
	[d synchronize];
}

#define REFRESH_PERIOD_KEY @"REFRESH_PERIOD_KEY"
-(float)refreshPeriod
{
	float period = [[NSUserDefaults standardUserDefaults] floatForKey:REFRESH_PERIOD_KEY];
	if(period==0)
	{
		period = 60.0;
		self.refreshPeriod = period;
	}
	return period;
}
-(void)setRefreshPeriod:(float)refreshPeriod { [[NSUserDefaults standardUserDefaults] setFloat:refreshPeriod forKey:REFRESH_PERIOD_KEY]; }

#define GITHUB_TOKEN_KEY @"GITHUB_AUTH_TOKEN"
-(NSString*)authToken { return [[NSUserDefaults standardUserDefaults] stringForKey:GITHUB_TOKEN_KEY]; }
-(void)setAuthToken:(NSString *)authToken
{
	[self storeDefaultValue:authToken forKey:GITHUB_TOKEN_KEY];
	if(authToken) [client setDefaultHeader:@"Authorization" value:[@"token " stringByAppendingString:authToken]];
}

#define USER_NAME_KEY @"USER_NAME_KEY"
-(NSString *)localUser { return [[NSUserDefaults standardUserDefaults] stringForKey:USER_NAME_KEY]; }
-(void)setLocalUser:(NSString *)localUser { [self storeDefaultValue:localUser forKey:USER_NAME_KEY]; }

#define USER_ID_KEY @"USER_ID_KEY"
-(NSString *)localUserId { return [[NSUserDefaults standardUserDefaults] stringForKey:USER_ID_KEY]; }
-(void)setLocalUserId:(NSString *)localUserId { [self storeDefaultValue:localUserId forKey:USER_ID_KEY]; }

-(void)error:(NSString*)errorString
{
	NSLog(@"Failed to fetch %@",errorString);
}

-(void)fetchCommentsForCurrentPullRequestsToMoc:(NSManagedObjectContext *)moc andCallback:(void (^)(BOOL))callback
{
	NSMutableArray *prs1 = [[DataItem newOrUpdatedItemsOfType:@"PullRequest" inMoc:moc] mutableCopy];
	for(PullRequest *r in prs1)
	{
		NSArray *comments = [PRComment commentsForPullRequestUrl:r.url inMoc:moc];
		for(PRComment *c in comments) c.postSyncAction = @(kTouchedDelete);
	}

	NSInteger totalOperations = 2;
	__block NSInteger succeded = 0;
	__block NSInteger failed = 0;

	typedef void (^completionBlockType)(BOOL);

	completionBlockType completionCallback = ^(BOOL success){
		if(success) succeded++; else failed++;
		if(succeded+failed==totalOperations)
		{
			[DataItem nukeDeletedItemsOfType:@"PRComment" inMoc:moc];
			if(callback) callback(success);
		}
	};

	[self _fetchCommentsForPullRequestIssues:YES toMoc:moc andCallback:completionCallback];

	[self _fetchCommentsForPullRequestIssues:NO toMoc:moc andCallback:completionCallback];

}

-(void)_fetchCommentsForPullRequestIssues:(BOOL)issues toMoc:(NSManagedObjectContext *)moc andCallback:(void(^)(BOOL success))callback
{
	NSArray *prs = [DataItem newOrUpdatedItemsOfType:@"PullRequest" inMoc:moc];
	if(!prs.count)
	{
		if(callback) callback(YES);
		return;
	}

	NSInteger total = prs.count;
	__block NSInteger succeeded = 0;
	__block NSInteger failed = 0;

	for(PullRequest *p in prs)
	{
		NSString *link;
		if(issues)
			link = p.issueCommentLink;
		else
			link = p.reviewCommentLink;

		[self getPagedDataInPath:link
						  params:nil
				 perPageCallback:^(id data, BOOL lastPage) {
					 NSArray *pageOfComments = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
					 for(NSDictionary *info in pageOfComments)
					 {
						 PRComment *c = [PRComment commentWithInfo:info moc:moc];
						 if(!c.pullRequestUrl) c.pullRequestUrl = p.url;

						 // check if we're assigned to a new pull request, in which case we want to "fast forward" its latest comment dates to our own if we're newer
						 if(p.postSyncAction.integerValue == kTouchedNew)
						 {
							 if(!p.latestReadCommentDate || [p.latestReadCommentDate compare:c.updatedAt]==NSOrderedAscending)
								 p.latestReadCommentDate = c.updatedAt;
						 }

					 }
				 } finalCallback:^(BOOL success) {
					 if(success) succeeded++; else failed++;
					 if(succeeded+failed==total)
					 {
						 callback(failed==0);
					 }
				 }];
	}
}

-(void)fetchRepositoriesAndCallback:(void(^)(BOOL success))callback
{
	[self syncUserDetailsAndCallback:^(BOOL success) {
		if(success)
		{
			NSManagedObjectContext *syncContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
			syncContext.parentContext = [AppDelegate shared].managedObjectContext;
			syncContext.undoManager = nil;

			[self syncOrgsToMoc:syncContext andCallback:^(BOOL success) {
				if(!success)
				{
					[self error:@"orgs"];
					callback(NO);
				}
				else
				{
					NSArray *orgs = [Org allItemsOfType:@"Org" inMoc:syncContext];
					__block NSInteger count=orgs.count;
					__block BOOL ok = YES;
					for(Org *r in orgs)
					{
						[self syncReposForOrg:r.login toMoc:syncContext andCallback:^(BOOL success) {
							count--;
							if(ok) ok = success;
							if(count==0)
							{
								[self syncReposForUserToMoc:syncContext andCallback:^(BOOL success) {
									if(ok) ok = success;
									if(callback)
									{
										if(ok && syncContext.hasChanges) [syncContext save:nil];
										callback(ok);
									}
								}];
							}
						}];
					}
				}
			}];
		}
		else if(callback) callback(NO);
	}];
}

-(void)fetchPullRequestsForActiveReposAndCallback:(void(^)(BOOL success))callback
{
	[self syncUserDetailsAndCallback:^(BOOL success) {
		if(success)
		{
			NSManagedObjectContext *syncContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSConfinementConcurrencyType];
			syncContext.parentContext = [AppDelegate shared].managedObjectContext;
			syncContext.undoManager = nil;

			[DataItem assumeWilldeleteItemsOfType:@"PullRequest" inMoc:syncContext];
			NSMutableArray *activeRepos = [[Repo activeReposInMoc:syncContext] mutableCopy];
			[self _fetchPullRequestsForRepos:activeRepos toMoc:syncContext andCallback:^(BOOL success) {
				if(success)
				{
					[self fetchCommentsForCurrentPullRequestsToMoc:syncContext andCallback:^(BOOL success) {
						[DataItem nukeDeletedItemsOfType:@"PullRequest" inMoc:syncContext];
						if(success && syncContext.hasChanges) [syncContext save:nil];
						if(callback) callback(success);
					}];
				}
				else if(callback) callback(NO);
			}];
		}
		else if(callback) callback(NO);
	}];
}

-(void)_fetchPullRequestsForRepos:(NSMutableArray *)repos toMoc:(NSManagedObjectContext *)moc andCallback:(void(^)(BOOL success))callback
{
	if(!repos.count)
	{
		if(callback) callback(YES);
		return;
	}
	NSInteger total = repos.count;
	__block NSInteger succeeded = 0;
	__block NSInteger failed = 0;
	for(Repo *r in repos)
	{
		[self getPagedDataInPath:[NSString stringWithFormat:@"/repos/%@/pulls",r.fullName]
						  params:nil
				 perPageCallback:^(id data, BOOL lastPage) {
					 NSArray *pageOfPRs = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
					 for(NSDictionary *info in pageOfPRs)
					 {
						 [PullRequest pullRequestWithInfo:info moc:moc];
					 }
				 } finalCallback:^(BOOL success) {
					 if(success) succeeded++; else failed++;
					 if(succeeded+failed==total)
					 {
						 callback(failed==0);
					 }
				 }];
	}
}

-(void)syncReposForUserToMoc:(NSManagedObjectContext *)moc andCallback:(void(^)(BOOL success))callback
{
	[self getPagedDataInPath:@"/user/repos"
					  params:nil
			 perPageCallback:^(id data, BOOL lastPage) {
				 NSArray *pageOfRepos = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
				 for(NSDictionary *info in pageOfRepos)
				 {
					 [Repo repoWithInfo:info moc:moc];
				 }
			 } finalCallback:^(BOOL success) {
				 if(callback) callback(success);
			 }];
}

-(void)syncReposForOrg:(NSString*)orgLogin toMoc:(NSManagedObjectContext *)moc andCallback:(void(^)(BOOL success))callback
{
	[self getPagedDataInPath:[NSString stringWithFormat:@"/orgs/%@/repos",orgLogin]
					  params:nil
			 perPageCallback:^(id data, BOOL lastPage) {
				 NSArray *pageOfRepos = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
				 for(NSDictionary *info in pageOfRepos)
				 {
					 [Repo repoWithInfo:info moc:moc];
				 }
			 } finalCallback:^(BOOL success) {
				 if(callback) callback(success);
			 }];
}

-(void)syncOrgsToMoc:(NSManagedObjectContext *)moc andCallback:(void(^)(BOOL success))callback
{
	[self getPagedDataInPath:@"/user/orgs"
					  params:nil
			 perPageCallback:^(id data, BOOL lastPage) {
				 NSArray *pageOfOrgs = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
				 for(NSDictionary *info in pageOfOrgs) [Org orgWithInfo:info moc:moc];
			 } finalCallback:^(BOOL success) {
				 if(callback) callback(success);
			 }];
}

-(void)syncUserDetailsAndCallback:(void (^)(BOOL))callback
{
	[self getDataInPath:@"/user"
				 params:nil
			andCallback:^(id data, BOOL lastPage) {
				if(data)
				{
					NSDictionary *userRecord = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
					[[NSUserDefaults standardUserDefaults] setObject:[userRecord ofk:@"login"] forKey:USER_NAME_KEY];
					[[NSUserDefaults standardUserDefaults] setObject:[userRecord ofk:@"id"] forKey:USER_ID_KEY];
					[[NSUserDefaults standardUserDefaults] synchronize];
					if(callback) callback(YES);
				}
				else if(callback) callback(NO);
			}];
}

-(void)getPagedDataInPath:(NSString*)path
				   params:(NSDictionary*)params
		  perPageCallback:(void(^)(id data, BOOL lastPage))pageCallback
			finalCallback:(void(^)(BOOL success))finalCallback
{
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		__block NSInteger page = 1;
		__block BOOL keepGoing = YES;
		__block BOOL ok = YES;
		dispatch_semaphore_t s = dispatch_semaphore_create(0);
		NSMutableDictionary *mparams = [params mutableCopy];
		if(!mparams) mparams = [NSMutableDictionary dictionaryWithCapacity:2];
		while(keepGoing)
		{
			mparams[@"page"] = @(page);
			mparams[@"per_page"] = @100;
			[self getDataInPath:path
						 params:mparams
					andCallback:^(id data, BOOL lastPage) {
						if(data)
						{
							if(pageCallback)
							{
								pageCallback(data,lastPage);
							}
							keepGoing = !lastPage;
							page++;
						}
						else
						{
							ok = NO;
							keepGoing = NO;
						}
						dispatch_semaphore_signal(s);
					}];
			dispatch_semaphore_wait(s, DISPATCH_TIME_FOREVER);
		}
		if(finalCallback)
		{
			dispatch_sync(dispatch_get_main_queue(), ^{
				finalCallback(ok);
			});
		}
	});
}

-(void)getDataInPath:(NSString*)path params:(NSDictionary*)params andCallback:(void(^)(id data, BOOL lastPage))callback
{
	NSMutableURLRequest *request = [client requestWithMethod:@"GET" path:path parameters:params];
	AFHTTPRequestOperation *o = [client HTTPRequestOperationWithRequest:request
																success:^(AFHTTPRequestOperation *operation, id responseObject) {
																	long long requestsRemaining = [[operation.response allHeaderFields][@"X-RateLimit-Remaining"] longLongValue];
																	long long requestLimit = [[operation.response allHeaderFields][@"X-RateLimit-Limit"] longLongValue];
																	long long epochSeconds = [[operation.response allHeaderFields][@"X-RateLimit-Reset"] longLongValue];
																	NSDate *date = [NSDate dateWithTimeIntervalSince1970:epochSeconds];
																	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
																	formatter.dateStyle = NSDateFormatterMediumStyle;
																	formatter.timeStyle = NSDateFormatterMediumStyle;
																	self.resetDate = [formatter stringFromDate:date];
																	//NSDictionary *data = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:nil];
																	//NSLog(@"Success %@",data);
																	//NSLog(@"Remaining requests: %lld/%lld",requestsRemaining,requestLimit);
																	[[NSNotificationCenter defaultCenter] postNotificationName:RATE_UPDATE_NOTIFICATION
																														object:nil
																													  userInfo:@{ RATE_UPDATE_NOTIFICATION_LIMIT_KEY: @(requestLimit),
																																  RATE_UPDATE_NOTIFICATION_REMAINING_KEY: @(requestsRemaining) }];
																	if(callback) callback(responseObject, [API lastPage:operation.response]);
																} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
																	NSLog(@"Failure: %@",error);
																	if(callback) callback(nil,NO);
																}];
	o.threadPriority = 0.0;
	[client.operationQueue addOperation:o];
}

-(void)getRateLimitAndCallback:(void (^)(long long, long long, long long))callback
{
	NSMutableURLRequest *request = [client requestWithMethod:@"GET" path:@"/rate_limit" parameters:nil];
	AFHTTPRequestOperation *o = [client HTTPRequestOperationWithRequest:request
																success:^(AFHTTPRequestOperation *operation, id responseObject) {
																	long long requestsRemaining = [[operation.response allHeaderFields][@"X-RateLimit-Remaining"] longLongValue];
																	long long requestLimit = [[operation.response allHeaderFields][@"X-RateLimit-Limit"] longLongValue];
																	long long epochSeconds = [[operation.response allHeaderFields][@"X-RateLimit-Reset"] longLongValue];
																	if(callback) callback(requestsRemaining,requestLimit,epochSeconds);
																} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
																	if(callback) callback(-1, -1, -1);
																}];
	o.threadPriority = 0.0;
	[client.operationQueue addOperation:o];
}

+(BOOL)lastPage:(NSHTTPURLResponse*)response
{
	NSString *linkHeader = [[response allHeaderFields] objectForKey:@"Link"];
	if(!linkHeader) return YES;
	return ([linkHeader rangeOfString:@"rel=\"next\""].location==NSNotFound);
}

@end
