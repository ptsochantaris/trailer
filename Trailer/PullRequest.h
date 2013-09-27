//
//  PullRequest.h
//  Trailer
//
//  Created by Paul Tsochantaris on 27/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface PullRequest : DataItem

@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSNumber * number;
@property (nonatomic, retain) NSString * state;
@property (nonatomic, retain) NSString * title;
@property (nonatomic, retain) NSString * body;
@property (nonatomic, retain) NSString * issueCommentLink;
@property (nonatomic, retain) NSString * reviewCommentLink;
@property (nonatomic, retain) NSDate * updatedAt;
@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * touched;

+(PullRequest *)pullRequestWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

@end
