//
//  Repo.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//


@interface Org : DataItem

@property (nonatomic, retain) NSString * avatarUrl;
@property (nonatomic, retain) NSString * login;

+(Org*)orgWithInfo:(NSDictionary*)info moc:(NSManagedObjectContext*)moc;

@end
