
@implementation Repo

@dynamic fullName;
@dynamic active;
@dynamic fork;
@dynamic webUrl;

+ (Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext*)moc
{
	Repo *r = [DataItem itemWithInfo:info type:@"Repo" moc:moc];
	r.fullName = [info ofk:@"full_name"];
	r.fork = @([[info ofk:@"fork"] boolValue]);
	r.webUrl = [info ofk:@"html_url"];
	return r;
}

+ (NSArray *)activeReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;
	f.predicate = [NSPredicate predicateWithFormat:@"active = YES"];
	return [moc executeFetchRequest:f error:nil];
}

+ (NSUInteger)countActiveReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.predicate = [NSPredicate predicateWithFormat:@"active = YES"];
	return [moc countForFetchRequest:f error:nil];
}

- (void)prepareForDeletion
{
	for(PullRequest *r in [PullRequest allItemsOfType:@"PullRequest" inMoc:self.managedObjectContext])
	{
		if([r.repoId isEqualToNumber:self.serverId])
		{
			[self.managedObjectContext deleteObject:r];
		}
	}
}

@end
