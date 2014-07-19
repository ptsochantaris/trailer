
@implementation Repo

@dynamic fullName;
@dynamic fork;
@dynamic webUrl;
@dynamic hidden;
@dynamic dirty;

+ (Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext*)moc
{
	Repo *r = [DataItem itemWithInfo:info type:@"Repo" moc:moc];
	if(r.postSyncAction.integerValue != kPostSyncDoNothing)
	{
		r.fullName = [info ofk:@"full_name"];
		r.fork = @([[info ofk:@"fork"] boolValue]);
		r.webUrl = [info ofk:@"html_url"];
		r.dirty = @(YES);
	}
	return r;
}

- (void)prepareForDeletion
{
    [self removeAllRelatedPullRequests];
	[super prepareForDeletion];
}

- (void)removeAllRelatedPullRequests
{
	NSNumber *sid = self.serverId;
    if(sid)
    {
        NSManagedObjectContext *moc = self.managedObjectContext;
        for(PullRequest *r in [PullRequest allItemsOfType:@"PullRequest" inMoc:moc])
        {
            if([r.repoId isEqualToNumber:sid])
            {
                [moc deleteObject:r];
            }
        }
    }
}

+ (NSArray *)visibleReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"hidden = NO"];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)hiddenReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"hidden = YES"];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSArray *)dirtyReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"dirty = YES and hidden = NO"];
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
