//
//  DataItem.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@implementation DataItem

@dynamic serverId;
@dynamic postSyncAction;
@dynamic createdAt;
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
		existingItem.createdAt = [_syncDateFormatter dateFromString:info[@"created_at"]];
		existingItem.postSyncAction = @(kTouchedNew);
	}
	else if([updatedDate compare:existingItem.updatedAt]==NSOrderedDescending)
	{
		NSLog(@"Updating existing %@: %@",type,serverId);
		existingItem.postSyncAction = @(kTouchedUpdated);
	}
	else
	{
		NSLog(@"Skipping %@: %@",type,serverId);
		existingItem.postSyncAction = @(kTouchedNone);
	}
	existingItem.updatedAt = updatedDate;
	return existingItem;
}

+(NSArray*)itemsOfType:(NSString *)type surviving:(BOOL)survivingItems inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	if(survivingItems)
	{
		f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction != %d",kTouchedDelete];
	}
	else
	{
		f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d",kTouchedDelete];
	}
	return [moc executeFetchRequest:f error:nil];
}

+(NSArray*)newOrUpdatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d or postSyncAction = %d",kTouchedNew,kTouchedUpdated];
	return [moc executeFetchRequest:f error:nil];
}

+(NSArray *)newItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d",kTouchedNew];
	return [moc executeFetchRequest:f error:nil];
}

+(void)nukeDeletedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSArray *untouchedItems = [self itemsOfType:type surviving:NO inMoc:moc];
	for(DataItem *i in untouchedItems)
	{
		NSLog(@"Nuking %@: %@",type,i.serverId);
		[moc deleteObject:i];
	}
	NSLog(@"Nuked %lu %@ items",untouchedItems.count,type);
}

+(void)assumeWilldeleteItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSArray *touchedItems = [self itemsOfType:type surviving:YES inMoc:moc];
	for(DataItem *i in touchedItems) i.postSyncAction = @(kTouchedDelete);
}

+(NSUInteger)countItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	return [moc countForFetchRequest:f error:nil];
}

+ (void)deleteAllObjectsInContext:(NSManagedObjectContext *)context
                       usingModel:(NSManagedObjectModel *)model
{
    NSArray *entities = model.entities;
    for (NSEntityDescription *entityDescription in entities) {
        [self deleteAllObjectsWithEntityName:entityDescription.name
                                   inContext:context];
    }
}

+ (void)deleteAllObjectsWithEntityName:(NSString *)entityName
                             inContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *fetchRequest =
	[NSFetchRequest fetchRequestWithEntityName:entityName];
    fetchRequest.includesPropertyValues = NO;
    fetchRequest.includesSubentities = NO;

    NSError *error;
    NSArray *items = [context executeFetchRequest:fetchRequest error:&error];

    for (NSManagedObject *managedObject in items) {
        [context deleteObject:managedObject];
        NSLog(@"Deleted %@", entityName);
    }
}

@end
