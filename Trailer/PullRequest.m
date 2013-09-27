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
@dynamic touched;

+(PullRequest *)pullRequestWithInfo:(NSDictionary *)info moc:(NSManagedObjectContext *)moc
{
	PullRequest *p = [DataItem itemWithInfo:info type:@"PullRequest" moc:moc];

	p.url = info[@"url"];
	p.number = info[@"number"];
	p.state = info[@"state"];
	p.title = info[@"title"];
	p.body = info[@"body"];

	p.issueCommentLink = info[@"_links"][@"comments"][@"href"];
	p.reviewCommentLink = info[@"_links"][@"review_comments"][@"href"];
	return p;
}

-(void)prepareForDeletion
{
	[PRComment removeCommentsWithPullRequestURL:self.url inMoc:self.managedObjectContext];
}

@end
