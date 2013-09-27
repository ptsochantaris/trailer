//
//  Comment.h
//  Trailer
//
//  Created by Paul Tsochantaris on 27/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface PRComment : DataItem

@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * touched;
@property (nonatomic, retain) NSDate * updatedAt;
@property (nonatomic, retain) NSNumber * position;
@property (nonatomic, retain) NSString * body;
@property (nonatomic, retain) NSString * userName;
@property (nonatomic, retain) NSString * path;
@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSString * pullRequestUrl;

+(PRComment *)commentWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc;

+(void)removeCommentsWithPullRequestURL:(NSString *)url inMoc:(NSManagedObjectContext *)moc;

+(NSInteger)countCommentsForPullRequestUrl:(NSString *)url inMoc:(NSManagedObjectContext *)moc;

@end
