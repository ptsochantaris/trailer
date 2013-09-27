//
//  DataItem.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#define kTouchedNo 0
#define kTouchedNew 1
#define kTouchedUpdated 2
#define kTouchedSkipped 3

@interface DataItem : NSManagedObject

@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * touched;
@property (nonatomic, retain) NSDate * updatedAt;

+(id)itemOfType:(NSString*)type serverId:(NSNumber*)serverId moc:(NSManagedObjectContext*)moc;

+(NSArray *)allItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(id)itemWithInfo:(NSDictionary*)info type:(NSString*)type moc:(NSManagedObjectContext*)moc;

+(void)unTouchItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(void)nukeUntouchedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSUInteger)countItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)newOrUpdatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

@end
