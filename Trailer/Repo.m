
#import "Repo.h"

@implementation Repo

@dynamic fullName;
@dynamic active;

+(Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext*)moc
{
	Repo *r = [DataItem itemWithInfo:info type:@"Repo" moc:moc];
	r.fullName = info[@"full_name"];
	return r;
}

+(NSArray*)allReposSortedByField:(NSString*)fieldName withTitleFilter:(NSString *)titleFilterOrNil inMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	if(titleFilterOrNil.length)
	{
		f.predicate = [NSPredicate predicateWithFormat:@"fullName contains [cd] %@",titleFilterOrNil];
	}
	if(fieldName)
	{
		f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:fieldName ascending:YES]];
	}
	return [moc executeFetchRequest:f error:nil];
}

+(NSArray *)activeReposInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.predicate = [NSPredicate predicateWithFormat:@"active = YES"];
	return [moc executeFetchRequest:f error:nil];
}

-(void)prepareForDeletion
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
