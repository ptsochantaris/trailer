//
//  ApiServer.m
//  Trailer
//
//  Created by Paul Tsochantaris on 18/10/14.
//  Copyright (c) 2014 HouseTrip. All rights reserved.
//

#import "ApiServer.h"

@implementation ApiServer

@dynamic repos;
@dynamic comments;
@dynamic pullRequests;
@dynamic statuses;

@dynamic apiPath;
@dynamic authToken;
@dynamic label;
@dynamic latestReceivedEventDateProcessed;
@dynamic latestReceivedEventEtag;
@dynamic latestUserEventDateProcessed;
@dynamic latestUserEventEtag;
@dynamic requestsLimit;
@dynamic requestsRemaining;
@dynamic resetDate;
@dynamic userId;
@dynamic userName;
@dynamic webPath;
@dynamic createdAt;
@dynamic lastSyncSucceeded;
@dynamic reportRefreshFailures;

+ (BOOL)shouldReportRefreshFailureInMoc:(NSManagedObjectContext *)moc
{
	for(ApiServer *apiServer in [ApiServer allApiServersInMoc:moc])
	{
		if(apiServer.goodToGo && !apiServer.lastSyncSucceeded.boolValue && apiServer.reportRefreshFailures.boolValue)
		{
			return YES;
		}
	}

	return NO;
}

- (void)rollBackAllUpdatesInMoc:(NSManagedObjectContext *)moc
{
	DLog(@"Rolling back changes for failed sync on API server %@",self.label);
	for(NSArray *items in @[self.repos, self.pullRequests, self.comments, self.statuses])
	{
		for(DataItem *i in items)
		{
			switch (i.postSyncAction.integerValue)
			{
				case kPostSyncDelete:
					i.postSyncAction = @(kPostSyncDoNothing);
					break;
				case kPostSyncNoteNew:
					[moc deleteObject:i];
					break;
				case kPostSyncNoteUpdated:
					[moc refreshObject:i mergeChanges:NO];
					break;
			}
		}
	}
	[moc refreshObject:self mergeChanges:NO];
}

+ (void)resetSyncSuccessInMoc:(NSManagedObjectContext *)moc
{
	for(ApiServer *apiServer in [ApiServer allApiServersInMoc:moc])
		if(apiServer.goodToGo)
			apiServer.lastSyncSucceeded = @YES;
}

+ (ApiServer *)insertNewServerInMoc:(NSManagedObjectContext *)moc
{
	ApiServer *githubServer = [NSEntityDescription insertNewObjectForEntityForName:@"ApiServer"
															inManagedObjectContext:moc];
	githubServer.createdAt = [NSDate date];
	return githubServer;
}

+ (ApiServer *)addDefaultGithubInMoc:(NSManagedObjectContext *)moc
{
	ApiServer *githubServer = [self insertNewServerInMoc:moc];
	[githubServer resetToGithub];
	return githubServer;
}

- (void)clearAllRelatedInfo
{
	for(NSManagedObject *o in self.repos)
		[self.managedObjectContext deleteObject:o];
}

- (void)resetToGithub
{
	self.webPath = @"https://github.com";
	self.apiPath = @"https://api.github.com";
	self.label = @"GitHub";
	self.latestReceivedEventDateProcessed = [NSDate distantPast];
	self.latestUserEventDateProcessed = [NSDate distantPast];
}

- (BOOL)goodToGo
{
	return (self.authToken.length>0);
}

+ (void)ensureAtLeastGithubInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"ApiServer"];
	f.fetchLimit = 1;
	NSUInteger numberOfExistingApiServers = [moc countForFetchRequest:f error:nil];
	if(numberOfExistingApiServers==0) [self addDefaultGithubInMoc:moc];
}

+ (NSArray *)allApiServersInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"ApiServer"];
	f.returnsObjectsAsFaults = NO;
	f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"createdAt" ascending:YES]];
	return [moc executeFetchRequest:f error:nil];
}

+ (BOOL)someServersHaveAuthTokensInMoc:(NSManagedObjectContext *)moc
{
	NSArray *allServers = [self allApiServersInMoc:moc];
	for(ApiServer *apiServer in allServers)
		if(apiServer.authToken.length>0)
			return YES;
	return NO;
}

+ (NSUInteger)countApiServersInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"ApiServer"];
	f.returnsObjectsAsFaults = NO;
	return [moc countForFetchRequest:f error:nil];
}

@end
