//
//  Repo.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

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

+(NSArray*)allReposSortedByField:(NSString*)fieldName inMoc:(NSManagedObjectContext*)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:fieldName ascending:YES]];
	return [moc executeFetchRequest:f error:nil];
}

+(void)nukeUntouchedItemsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.predicate = [NSPredicate predicateWithFormat:@"touched = NO"];
	NSArray *untouchedItems = [moc executeFetchRequest:f error:nil];
	for(DataItem *i in untouchedItems) [moc deleteObject:i];
	NSLog(@"Nuked %lu Repos",untouchedItems.count);
}

+(void)unTouchEverythingInMoc:(NSManagedObjectContext *)moc
{
	NSArray *allItems = [self allItemsOfType:@"Repo" inMoc:moc];
	for(DataItem *i in allItems) i.touched = @NO;
}

@end
