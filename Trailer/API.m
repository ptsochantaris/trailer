//
//  API.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface API ()
{
	NSOperationQueue *requestQueue;
	NSDateFormatter *dateFormatter;
}
@end

@implementation API

- (id)init
{
    self = [super init];
    if (self) {
		dateFormatter = [[NSDateFormatter alloc] initWithDateFormat:@"YYYY-MM-DDTHH:MM:SSZ" allowNaturalLanguage:NO];
		requestQueue = [[NSOperationQueue alloc] init];
		requestQueue.maxConcurrentOperationCount = 8;
		self.reachability = [Reachability reachabilityWithHostName:API_SERVER];
		[self.reachability startNotifier];
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
}

#define USER_NAME_KEY @"USER_NAME_KEY"
-(NSString *)localUser { return [[NSUserDefaults standardUserDefaults] stringForKey:USER_NAME_KEY]; }
-(void)setLocalUser:(NSString *)localUser { [self storeDefaultValue:localUser forKey:USER_NAME_KEY]; }

#define USER_ID_KEY @"USER_ID_KEY"
-(NSString *)localUserId { return [[NSUserDefaults standardUserDefaults] stringForKey:USER_ID_KEY]; }
-(void)setLocalUserId:(NSString *)localUserId { [self storeDefaultValue:localUserId forKey:USER_ID_KEY]; }

#define HIDE_PRS_KEY @"HIDE_UNCOMMENTED_PRS_KEY"
-(void)setShouldHideUncommentedRequests:(BOOL)shouldHideUncommentedRequests { [self storeDefaultValue:@(shouldHideUncommentedRequests) forKey:HIDE_PRS_KEY]; }
-(BOOL)shouldHideUncommentedRequests { return [[[NSUserDefaults standardUserDefaults] stringForKey:HIDE_PRS_KEY] boolValue]; }

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
				startingFromPage:1
						  params:nil
				 perPageCallback:^(id data, BOOL lastPage) {
					 for(NSDictionary *info in data)
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

-(void)detectMergedPullRequestsInMoc:(NSManagedObjectContext *)moc andCallback:(void(^)(BOOL success))callback
{
	NSArray *pullRequests = [PullRequest allItemsOfType:@"PullRequest" inMoc:moc];
	NSMutableArray *prsToCheck = [NSMutableArray array];
	for(PullRequest *r in pullRequests)
	{
		Repo *parent = [Repo itemOfType:@"Repo" serverId:r.repoId moc:moc];
		if(r.postSyncAction.integerValue==kTouchedDelete &&
		   parent && (parent.postSyncAction.integerValue!=kTouchedDelete) &&
		   (r.isMine || r.commentedByMe) &&
		   (!r.merged.boolValue))
		{
			[prsToCheck addObject:r]; // possibly merged
		}
	}
	[self _detectMergedPullRequests:prsToCheck andCallback:callback];
}

-(void)_detectMergedPullRequests:(NSMutableArray *)prsToCheck andCallback:(void(^)(BOOL success))callback
{
	if(prsToCheck.count==0)
	{
		callback(YES);
		return;
	}
	PullRequest *r = [prsToCheck objectAtIndex:0];
	[prsToCheck removeObjectAtIndex:0];

	Repo *parent = [Repo itemOfType:@"Repo" serverId:r.repoId moc:r.managedObjectContext];
	NSString *owner = [parent.fullName copy];

	[self get:[NSString stringWithFormat:@"/repos/%@/pulls/%@/merge",owner,r.number]
   parameters:nil
	  success:^(NSHTTPURLResponse *response, id data) {
		  // merged indeed
		  r.postSyncAction = @(kTouchedNone); // don't delete this
		  r.merged = @(YES); // pin it so it sticks around
		  [[AppDelegate shared] postNotificationOfType:kPrMerged forItem:r];
		  [self _detectMergedPullRequests:prsToCheck andCallback:callback];
	  } failure:^(NSError *error) {
		  // not merged
		  if(error) r.postSyncAction = @(kTouchedNone); // don't delete this, we couldn't check, play it safe
		  [self _detectMergedPullRequests:prsToCheck andCallback:callback];
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
						if(success)
						{
							[self detectMergedPullRequestsInMoc:syncContext andCallback:^(BOOL success) {
								if(success)
								{
									[DataItem nukeDeletedItemsOfType:@"PullRequest" inMoc:syncContext];
									if(success && syncContext.hasChanges) [syncContext save:nil];
									if(callback) callback(success);
								}
							}];
						}
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
				startingFromPage:1
						  params:nil
				 perPageCallback:^(id data, BOOL lastPage) {
					 for(NSDictionary *info in data)
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
			startingFromPage:1
					  params:nil
			 perPageCallback:^(id data, BOOL lastPage) {
				 for(NSDictionary *info in data)
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
			startingFromPage:1
					  params:nil
			 perPageCallback:^(id data, BOOL lastPage) {
				 for(NSDictionary *info in data)
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
			startingFromPage:1
					  params:nil
			 perPageCallback:^(id data, BOOL lastPage) {
				 for(NSDictionary *info in data) [Org orgWithInfo:info moc:moc];
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
					[[NSUserDefaults standardUserDefaults] setObject:[data ofk:@"login"] forKey:USER_NAME_KEY];
					[[NSUserDefaults standardUserDefaults] setObject:[data ofk:@"id"] forKey:USER_ID_KEY];
					[[NSUserDefaults standardUserDefaults] synchronize];
					if(callback) callback(YES);
				}
				else if(callback) callback(NO);
			}];
}

-(void)getPagedDataInPath:(NSString*)path
		 startingFromPage:(NSInteger)page
				   params:(NSDictionary*)params
		  perPageCallback:(void(^)(id data, BOOL lastPage))pageCallback
			finalCallback:(void(^)(BOOL success))finalCallback
{
	NSMutableDictionary *mparams;
	if(params) mparams = [params mutableCopy];
	else mparams = [NSMutableDictionary dictionaryWithCapacity:2];
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

					if(lastPage)
					{
						finalCallback(YES);
					}
					else
					{
						[self getPagedDataInPath:path
								startingFromPage:page+1
										  params:params
								 perPageCallback:pageCallback
								   finalCallback:finalCallback];
					}
				}
				else
				{
					finalCallback(NO);
				}
			}];
}

-(void)getDataInPath:(NSString*)path params:(NSDictionary*)params andCallback:(void(^)(id data, BOOL lastPage))callback
{
	[self get:path
   parameters:params
	  success:^(NSHTTPURLResponse *response, id data) {
		  long long requestsRemaining = [[response allHeaderFields][@"X-RateLimit-Remaining"] longLongValue];
		  long long requestLimit = [[response allHeaderFields][@"X-RateLimit-Limit"] longLongValue];
		  long long epochSeconds = [[response allHeaderFields][@"X-RateLimit-Reset"] longLongValue];
		  NSDate *date = [NSDate dateWithTimeIntervalSince1970:epochSeconds];
		  NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
		  formatter.dateStyle = NSDateFormatterMediumStyle;
		  formatter.timeStyle = NSDateFormatterMediumStyle;
		  self.resetDate = [formatter stringFromDate:date];
		  [[NSNotificationCenter defaultCenter] postNotificationName:RATE_UPDATE_NOTIFICATION
															  object:nil
															userInfo:@{ RATE_UPDATE_NOTIFICATION_LIMIT_KEY: @(requestLimit),
																		RATE_UPDATE_NOTIFICATION_REMAINING_KEY: @(requestsRemaining) }];
		  if(callback) callback(data, [API lastPage:response]);
	  } failure:^(NSError *error) {
		  NSLog(@"Failure: %@",error);
		  if(callback) callback(nil,NO);
	  }];
}

-(void)getRateLimitAndCallback:(void (^)(long long, long long, long long))callback
{
	[self get:@"/rate_limit"
	  parameters:nil
		 success:^(NSHTTPURLResponse *response, id data) {
			 long long requestsRemaining = [[response allHeaderFields][@"X-RateLimit-Remaining"] longLongValue];
			 long long requestLimit = [[response allHeaderFields][@"X-RateLimit-Limit"] longLongValue];
			 long long epochSeconds = [[response allHeaderFields][@"X-RateLimit-Reset"] longLongValue];
			 if(callback) callback(requestsRemaining,requestLimit,epochSeconds);
		 } failure:^(NSError *error) {
			 if(callback) callback(-1, -1, -1);
		 }];
}

+(BOOL)lastPage:(NSHTTPURLResponse*)response
{
	NSString *linkHeader = [[response allHeaderFields] objectForKey:@"Link"];
	if(!linkHeader) return YES;
	return ([linkHeader rangeOfString:@"rel=\"next\""].location==NSNotFound);
}

-(NSOperation *)get:(NSString *)path parameters:(NSDictionary *)params success:(void(^)(NSHTTPURLResponse *response, id data))successCallback failure:(void(^)(NSError *error))failureCallback
{
	NSString *authToken = self.authToken;
	NSBlockOperation *o = [NSBlockOperation blockOperationWithBlock:^{

		NSString *expandedPath;
		if([path rangeOfString:@"/"].location==0) expandedPath = [[@"https://" stringByAppendingString:API_SERVER] stringByAppendingString:path];
		else expandedPath = path;

		if(params.count)
		{
			expandedPath = [expandedPath stringByAppendingString:@"?"];
			NSMutableArray *pairs = [NSMutableArray arrayWithCapacity:params.count];
			for(NSString *key in params)
			{
				[pairs addObject:[NSString stringWithFormat:@"%@=%@", key, params[key]]];
			}
			expandedPath = [expandedPath stringByAppendingString:[pairs componentsJoinedByString:@"&"]];
		}

		NSMutableURLRequest *r = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:expandedPath]
															  cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
														  timeoutInterval:60.0];
		[r setValue:@"Trailer" forHTTPHeaderField:@"User-Agent"];
		[r setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
		if(authToken) [r setValue:[@"token " stringByAppendingString:authToken] forHTTPHeaderField:@"Authorization"];

		NSError *error;
		NSHTTPURLResponse *response;
		NSData *data = [NSURLConnection sendSynchronousRequest:r returningResponse:&response error:&error];
		if(!error && response.statusCode>299)
		{
			error = [NSError errorWithDomain:@"Error response received" code:response.statusCode userInfo:nil];
		}
		if(error)
		{
			NSLog(@"GET %@ - FAILED: %@",expandedPath,error);
			if(failureCallback)
			{
				dispatch_async(dispatch_get_main_queue(), ^{
					failureCallback(error);
				});
			}
		}
		else
		{
			NSLog(@"GET %@ - RESULT: %ld",expandedPath,(long)response.statusCode);
			if(successCallback)
			{
				id parsedData = nil;
				if(data.length) parsedData = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
				dispatch_async(dispatch_get_main_queue(), ^{
					successCallback(response,parsedData);
				});
			}
		}
	}];
	o.threadPriority = 0.0;
	[requestQueue addOperation:o];
	return o;
}



@end
