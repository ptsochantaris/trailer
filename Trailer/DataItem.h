//
//  DataItem.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface DataItem : NSManagedObject

@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * touched;

+(id)itemOfType:(NSString*)type serverId:(NSNumber*)serverId moc:(NSManagedObjectContext*)moc;
+(NSArray *)allItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;
+(id)itemWithInfo:(NSDictionary*)info type:(NSString*)type moc:(NSManagedObjectContext*)moc;
+(void)nukeUntouchedItemsInMoc:(NSManagedObjectContext*)moc;
+(void)unTouchEverythingInMoc:(NSManagedObjectContext*)moc;

@end
