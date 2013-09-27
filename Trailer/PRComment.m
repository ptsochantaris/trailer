//
//  Comment.m
//  Trailer
//
//  Created by Paul Tsochantaris on 27/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@implementation PRComment

@dynamic serverId;
@dynamic touched;
@dynamic updatedAt;
@dynamic position;
@dynamic body;
@dynamic userName;
@dynamic path;
@dynamic pullRequestUrl;
@dynamic url;

+(PRComment *)commentWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PRComment *c = [DataItem itemWithInfo:info type:@"PRComment" moc:moc];

	c.body = info[@"body"];
	c.position = [info ofk:@"position"];
	c.body = info[@"body"];
	c.path = info[@"path"];
	c.url = info[@"url"];
	c.userName = info[@"user"][@"userName"];
	c.url = info[@"_links"][@"self"][@"href"];
	c.pullRequestUrl = info[@"_links"][@"pull_request"][@"href"];

	return c;
}

+(void)removeCommentsWithPullRequestURL:(NSString *)url inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",url];
	for(PRComment *c in [moc executeFetchRequest:f error:nil])
	{
		NSLog(@"  Deleting comment ID %@",c.serverId);
		[moc deleteObject:c];
	}
}

+(NSInteger)countCommentsForPullRequestUrl:(NSString *)url inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRComment"];
	f.predicate = [NSPredicate predicateWithFormat:@"pullRequestUrl = %@",url];
	return [moc countForFetchRequest:f error:nil];
}

@end
