//
//  Repo.m
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@implementation Org

@dynamic avatarUrl;
@dynamic login;

+(Org*)orgWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext*)moc
{
	Org *o = [DataItem itemWithInfo:info type:@"Org" moc:moc];
	o.login = info[@"login"];
	o.avatarUrl = info[@"avatar_url"];
	return o;
}

+(void)nukeUntouchedItemsInMoc:(NSManagedObjectContext *)moc
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Org"];
	f.predicate = [NSPredicate predicateWithFormat:@"touched = NO"];
	NSArray *untouchedItems = [moc executeFetchRequest:f error:nil];
	for(DataItem *i in untouchedItems) [moc deleteObject:i];
	NSLog(@"Nuked %lu Orgs",untouchedItems.count);
}

+(void)unTouchEverythingInMoc:(NSManagedObjectContext *)moc
{
	NSArray *allItems = [self allItemsOfType:@"Org" inMoc:moc];
	for(DataItem *i in allItems) i.touched = @NO;
}

@end
