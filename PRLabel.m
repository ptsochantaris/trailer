
@implementation PRLabel

@dynamic url;
@dynamic name;
@dynamic color;
@dynamic apiServer;
@dynamic pullRequest;
@dynamic createdAt;
@dynamic postSyncAction;
@dynamic serverId;
@dynamic updatedAt;

+ (PRLabel *)labelWithInfo:(NSDictionary *)info fromServer:(ApiServer *)apiServer
{
	PRLabel *l = [DataItem itemWithInfo:info type:@"PRLabel" fromServer:apiServer];
	if(l.postSyncAction.integerValue != kPostSyncDoNothing)
	{
		l.url = [info ofk:@"url"];
		l.name = [info ofk:@"name"];
		l.color = @([[info ofk:@"color"] parseFromHex]);
	}
	return l;
}

- (COLOR_CLASS *)colorForDisplay
{
	unsigned long long c = self.color.longLongValue;
	CGFloat red = (c & 0xFF0000)>>16;
	CGFloat green = (c & 0x00FF00)>>8;
	CGFloat blue = c & 0x0000FF;
	return [COLOR_CLASS colorWithRed:red/255.0
							   green:green/255.0
								blue:blue/255.0
							   alpha:1.0];
}

@end
