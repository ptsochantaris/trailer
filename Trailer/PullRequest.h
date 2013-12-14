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
@property (nonatomic, retain) NSNumber * postSyncAction;
@property (nonatomic, retain) NSString * webUrl;
@property (nonatomic, retain) NSNumber * userId;
@property (nonatomic, retain) NSDate * latestReadCommentDate;
@property (nonatomic, retain) NSNumber *repoId;
@property (nonatomic, retain) NSNumber *merged;

+ (PullRequest *)pullRequestWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

+ (PullRequest *)pullRequestWithUrl:(NSString *)url moc:(NSManagedObjectContext *)moc;

+ (NSArray *)pullRequestsSortedByField:(NSString *)fieldName
								filter:(NSString *)filter
							 ascending:(BOOL)ascending
								 inMoc:(NSManagedObjectContext *)moc;

+ (NSArray *)allMergedRequestsInMoc:(NSManagedObjectContext *)moc;

+ (NSUInteger)countUnmergedRequestsInMoc:(NSManagedObjectContext *)moc;

- (NSInteger)unreadCommentCount;

- (void)catchUpWithComments;

- (BOOL)isMine;

- (BOOL)commentedByMe;

@end
