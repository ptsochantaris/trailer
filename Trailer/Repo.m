
@implementation Repo

@dynamic fullName;
@dynamic fork;
@dynamic webUrl;
@dynamic hidden;
@dynamic dirty;
@dynamic lastDirtied;
@dynamic inaccessible;
@dynamic pullRequests;

+ (Repo*)repoWithInfo:(NSDictionary*)info fromServer:(ApiServer *)apiServer
{
	Repo *r = [DataItem itemWithInfo:info type:@"Repo" fromServer:apiServer];
	if(r.postSyncAction.integerValue != kPostSyncDoNothing)
	{
		r.fullName = [info ofk:@"full_name"];
		r.fork = @([[info ofk:@"fork"] boolValue]);
		r.webUrl = [info ofk:@"html_url"];
		r.dirty = @YES;
		r.lastDirtied = [NSDate date];
	}
	return r;
}

+ (NSArray *)inaccessibleReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"inaccessible = YES"];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)visibleReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"hidden = NO"];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)unsyncableReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"hidden = YES or inaccessible = YES"];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)syncableReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"dirty = YES and hidden = NO and inaccessible != YES"];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSUInteger)countVisibleReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.predicate = [NSPredicate predicateWithFormat:@"hidden = NO"];
	return [moc countForFetchRequest:f error:nil];
}

+ (void)markDirtyReposWithIds:(NSSet *)ids inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"serverId IN %@",ids];
	NSArray *repos = [moc executeFetchRequest:f error:nil];
	for(Repo *r in repos) r.dirty = @(!r.hidden.boolValue);
}

@end
