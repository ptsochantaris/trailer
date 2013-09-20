//
//  DataItem.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@implementation DataItem

@dynamic serverId;
@dynamic touched;

+(id)itemOfType:(NSString*)type serverId:(NSNumber*)serverId moc:(NSManagedObjectContext*)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.fetchLimit = 1;
	f.predicate = [NSPredicate predicateWithFormat:@"serverId = %@",serverId];
	return [[moc executeFetchRequest:f error:nil] lastObject];
}

+(NSArray *)allItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	return [moc executeFetchRequest:f error:nil];
}

+(id)itemWithInfo:(NSDictionary*)info type:(NSString*)type moc:(NSManagedObjectContext*)moc
{
	NSNumber *serverId = info[@"id"];
	Org *existingItem = [DataItem itemOfType:type serverId:serverId moc:moc];
	if(!existingItem)
	{
		NSLog(@"Creating new item: %@",serverId);
		existingItem = [NSEntityDescription insertNewObjectForEntityForName:type
													 inManagedObjectContext:moc];
		existingItem.serverId = serverId;
	}
	else
	{
		NSLog(@"Updating existing item: %@",serverId);
	}
	existingItem.touched = @YES;
	return existingItem;
}

+(void)nukeUntouchedItemsInMoc:(NSManagedObjectContext*)moc
{
	abort(); // TODO: override!
}

+(void)unTouchEverythingInMoc:(NSManagedObjectContext *)moc
{
	abort(); // TODO: override!
}

@end
