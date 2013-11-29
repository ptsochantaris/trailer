//
//  Repo.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface Repo : DataItem

@property (nonatomic, retain) NSString * fullName;
@property (nonatomic, retain) NSNumber * active;

+(Repo*)repoWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext *)moc;

+(NSArray*)allReposSortedByField:(NSString*)fieldName withTitleFilter:(NSString *)titleFilterOrNil inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)activeReposInMoc:(NSManagedObjectContext *)moc;

@end
