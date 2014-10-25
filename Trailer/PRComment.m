
@implementation PRComment

@dynamic serverId;
@dynamic postSyncAction;
@dynamic updatedAt;
@dynamic position;
@dynamic body;
@dynamic userName;
@dynamic avatarUrl;
@dynamic path;
@dynamic url;
@dynamic userId;
@dynamic webUrl;
@dynamic pullRequest;

+ (PRComment *)commentWithInfo:(NSDictionary *)info fromServer:(ApiServer *)apiServer
{
	PRComment *c = [DataItem itemWithInfo:info type:@"PRComment" fromServer:apiServer];
	if(c.postSyncAction.integerValue != kPostSyncDoNothing)
	{
		c.body = [info ofk:@"body"];
		c.position = [info ofk:@"position"];
		c.path = [info ofk:@"path"];
		c.url = [info ofk:@"url"];
		c.webUrl = [info ofk:@"html_url"];

		NSDictionary *userInfo = [info ofk:@"user"];
		c.userName = [userInfo ofk:@"login"];
		c.userId = [userInfo ofk:@"id"];
		c.avatarUrl = [userInfo ofk:@"avatar_url"];

		NSDictionary *links = [info ofk:@"links"];
		c.url = [[links ofk:@"self"] ofk:@"href"];
		if(!c.webUrl) c.webUrl = [[links ofk:@"html"] ofk:@"href"];
	}
	return c;
}

- (BOOL)isMine
{
	return [self.userId isEqualToNumber:self.apiServer.userId];
}

- (BOOL)refersToMe
{
	NSString *myHandle = [NSString stringWithFormat:@"@%@", self.apiServer.userName];
	NSRange rangeOfHandle = [self.body rangeOfString:myHandle options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch];
	return rangeOfHandle.location != NSNotFound;
}

@end
