//
//  API.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#define GITHUB_TOKEN_KEY @"GITHUB_AUTH_TOKEN"
#define RATE_UPDATE_NOTIFICATION @"RateUpdateNotification"
#define RATE_UPDATE_NOTIFICATION_LIMIT_KEY @"RateUpdateNotificationLimit"
#define RATE_UPDATE_NOTIFICATION_REMAINING_KEY @"RateUpdateNotificationRemaining"

@interface API : NSObject

@property (nonatomic,readonly) NSString *authToken;
@property (nonatomic) NSString *resetDate;

-(void)fetchRepositoriesAndCallback:(void(^)(BOOL success))callback;
-(void)fetchPullRequestsForActiveReposAndCallback:(void(^)(BOOL success))callback;

@end
