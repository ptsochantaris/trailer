
@implementation DataItem

@dynamic serverId;
@dynamic postSyncAction;
@dynamic createdAt;
@dynamic updatedAt;

NSDateFormatter *_syncDateFormatter;

+ (void)load
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		_syncDateFormatter = [[NSDateFormatter alloc] init];
		_syncDateFormatter.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'";
		_syncDateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
		_syncDateFormatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US"];
	});
}

+ (id)itemOfType:(NSString*)type serverId:(NSNumber*)serverId moc:(NSManagedObjectContext*)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.fetchLimit = 1;
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"serverId = %@",serverId];
	return [[moc executeFetchRequest:f error:nil] lastObject];
}

+ (NSArray *)allItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.returnsObjectsAsFaults = NO;
	return [moc executeFetchRequest:f error:nil];
}

+ (id)itemWithInfo:(NSDictionary*)info type:(NSString*)type moc:(NSManagedObjectContext*)moc
{
	NSNumber *serverId = [info ofk:@"id"];
	NSDate *updatedDate = [_syncDateFormatter dateFromString:[info ofk:@"updated_at"]];

	DataItem *existingItem = [DataItem itemOfType:type serverId:serverId moc:moc];
	if(!existingItem)
	{
		DLog(@"Creating new %@: %@",type,serverId);
		existingItem = [NSEntityDescription insertNewObjectForEntityForName:type inManagedObjectContext:moc];
		existingItem.serverId = serverId;
		existingItem.createdAt = [_syncDateFormatter dateFromString:[info ofk:@"created_at"]];
		existingItem.postSyncAction = @(kPostSyncNoteNew);
		existingItem.updatedAt = updatedDate;
	}
	else if(![updatedDate isEqual:existingItem.updatedAt])
	{
		DLog(@"Updating existing %@: %@",type,serverId);
		existingItem.postSyncAction = @(kPostSyncNoteUpdated);
		existingItem.updatedAt = updatedDate;
	}
	else
	{
		DLog(@"Skipping %@: %@",type,serverId);
		existingItem.postSyncAction = @(kPostSyncDoNothing);
	}
	return existingItem;
}

+ (NSArray*)itemsOfType:(NSString *)type surviving:(BOOL)survivingItems inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.returnsObjectsAsFaults = NO;
	if(survivingItems)
	{
		f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction != %d",kPostSyncDelete];
	}
	else
	{
		f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d",kPostSyncDelete];
	}
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray*)newOrUpdatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d or postSyncAction = %d",kPostSyncNoteNew,kPostSyncNoteUpdated];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray*)updatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d",kPostSyncNoteUpdated];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)newItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d",kPostSyncNoteNew];
	return [moc executeFetchRequest:f error:nil];
}

+ (void)nukeDeletedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSArray *untouchedItems = [self itemsOfType:type surviving:NO inMoc:moc];
	for(DataItem *i in untouchedItems)
	{
		DLog(@"Nuking %@: %@",type,i.serverId);
		[moc deleteObject:i];
	}
	DLog(@"Nuked %lu %@ items",(unsigned long)untouchedItems.count,type);
}

+ (NSUInteger)countItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	return [moc countForFetchRequest:f error:nil];
}

@end
