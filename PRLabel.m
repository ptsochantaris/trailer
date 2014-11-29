#import "PRLabel.h"

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
	NSString *name = [info ofk:@"name"];
	PRLabel *l = [PRLabel labelWithName:name fromServer:apiServer];
	if(!l)
	{
		l = [NSEntityDescription insertNewObjectForEntityForName:@"PRLabel" inManagedObjectContext:apiServer.managedObjectContext];
		l.name = name;
		l.serverId = @0;
		l.updatedAt = [NSDate distantPast];
		l.createdAt = [NSDate distantPast];
		l.apiServer = apiServer;
	}
	l.url = [info ofk:@"url"];
	l.color = @([[info ofk:@"color"] parseFromHex]);
	l.postSyncAction = @(kPostSyncDoNothing);
	return l;
}

+ (PRLabel *)labelWithName:(NSString *)name fromServer:(ApiServer *)apiServer
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"PRLabel"];
	f.fetchLimit = 1;
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"name == %@ and apiServer == %@", name, apiServer];
	return [[apiServer.managedObjectContext executeFetchRequest:f error:nil] lastObject];
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
