
@implementation DataItem

@dynamic serverId;
@dynamic postSyncAction;
@dynamic createdAt;
@dynamic updatedAt;
@dynamic apiServer;

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

- (void)prepareForDeletion
{
	if(self.postSyncAction.integerValue==kPostSyncDelete) DLog(@"Deleting %@ ID: %@",self.entity.name,self.serverId);
	[super prepareForDeletion];
}

+ (NSArray *)allItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.returnsObjectsAsFaults = NO;
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)allItemsOfType:(NSString *)type fromServer:(ApiServer *)apiServer
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"apiServer == %@", apiServer];
	return [apiServer.managedObjectContext executeFetchRequest:f error:nil];
}

+ (id)itemOfType:(NSString*)type serverId:(NSNumber*)serverId fromServer:(ApiServer *)apiServer
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.fetchLimit = 1;
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"serverId = %@ and apiServer == %@", serverId, apiServer];
	return [[apiServer.managedObjectContext executeFetchRequest:f error:nil] lastObject];
}

+ (id)itemWithInfo:(NSDictionary*)info type:(NSString*)type fromServer:(ApiServer *)apiServer
{
	NSNumber *serverId = [info ofk:@"id"];
	NSDate *updatedDate = [_syncDateFormatter dateFromString:[info ofk:@"updated_at"]];

	DataItem *existingItem = [self itemOfType:type serverId:serverId fromServer:apiServer];
	if(!existingItem)
	{
		DLog(@"Creating new %@: %@",type,serverId);
		existingItem = [NSEntityDescription insertNewObjectForEntityForName:type inManagedObjectContext:apiServer.managedObjectContext];
		existingItem.serverId = serverId;
		existingItem.createdAt = [_syncDateFormatter dateFromString:[info ofk:@"created_at"]];
		existingItem.postSyncAction = @(kPostSyncNoteNew);
		existingItem.updatedAt = updatedDate;
		existingItem.apiServer = apiServer;
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
	if(survivingItems)
	{
		f.returnsObjectsAsFaults = NO;
		f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction != %d",kPostSyncDelete];
	}
	else
	{
		f.returnsObjectsAsFaults = YES;
		f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d",kPostSyncDelete];
	}
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray*)newOrUpdatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"postSyncAction = %d or postSyncAction = %d", kPostSyncNoteNew, kPostSyncNoteUpdated];
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

+ (void)nukeDeletedItemsInMoc:(NSManagedObjectContext *)moc
{
	NSArray *types = @[@"Repo", @"PullRequest", @"PRStatus", @"PRComment"];
	unsigned long count=0;
	for(NSString *type in types)
	{
		NSArray *discarded = [self itemsOfType:type surviving:NO inMoc:moc];
		count += discarded.count;
		for(DataItem *i in discarded)
		{
			DLog(@"Nuking unused %@: %@",type,i.serverId);
			[moc deleteObject:i];
		}
	}
	DLog(@"Nuked %lu deleted items in total",count);
}

+ (NSUInteger)countItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:type];
	return [moc countForFetchRequest:f error:nil];
}

@end
