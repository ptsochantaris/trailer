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
@dynamic updatedAt;

static NSDateFormatter *_syncDateFormatter;

+(void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_syncDateFormatter = [[NSDateFormatter alloc] init];
		_syncDateFormatter.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'";
		_syncDateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
		_syncDateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
	});
}

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
	NSDate *updatedDate = [_syncDateFormatter dateFromString:info[@"updated_at"]];

	DataItem *existingItem = [DataItem itemOfType:type serverId:serverId moc:moc];
	if(!existingItem)
	{
		NSLog(@"Creating new %@: %@",type,serverId);
		existingItem = [NSEntityDescription insertNewObjectForEntityForName:type inManagedObjectContext:moc];
		existingItem.serverId = serverId;
		existingItem.touched = @(kTouchedNew);
	}
	else if([updatedDate compare:existingItem.updatedAt]==NSOrderedDescending)
	{
		NSLog(@"Updating existing %@: %@",type,serverId);
		existingItem.touched = @(kTouchedUpdated);
	}
	else
	{
		NSLog(@"Skipping %@: %@",type,serverId);
		existingItem.touched = @(kTouchedSkipped);
	}
	existingItem.updatedAt = updatedDate;
	return existingItem;
}

+(NSArray*)itemsOfType:(NSString *)type touched:(BOOL)touched inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	if(touched)
	{
		f.predicate = [NSPredicate predicateWithFormat:@"touched != %d",kTouchedNo];
	}
	else
	{
		f.predicate = [NSPredicate predicateWithFormat:@"touched = %d",kTouchedNo];
	}
	return [moc executeFetchRequest:f error:nil];
}

+(NSArray*)newOrUpdatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.predicate = [NSPredicate predicateWithFormat:@"touched = %d or touched = %d",kTouchedNew,kTouchedUpdated];
	return [moc executeFetchRequest:f error:nil];
}

+(void)nukeUntouchedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSArray *untouchedItems = [self itemsOfType:type touched:NO inMoc:moc];
	for(Org *i in untouchedItems)
	{
		NSLog(@"Nuking %@: %@",type,i.serverId);
		[moc deleteObject:i];
	}
	NSLog(@"Nuked %lu %@ items",untouchedItems.count,type);
}

+(void)unTouchItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSArray *touchedItems = [self itemsOfType:type touched:YES inMoc:moc];
	for(DataItem *i in touchedItems) i.touched = @(kTouchedNo);
}

+(NSUInteger)countItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	return [moc countForFetchRequest:f error:nil];
}

@end
