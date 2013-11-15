//
//  DataItem.h
//  Trailer
//
//  Created by Paul Tsochantaris on 20/09/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#define kTouchedNone 0
#define kTouchedDelete 1
#define kTouchedNew 2
#define kTouchedUpdated 3

@interface DataItem : NSManagedObject

@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * postSyncAction;
@property (nonatomic, retain) NSDate * updatedAt, * createdAt;

+(id)itemOfType:(NSString*)type serverId:(NSNumber*)serverId moc:(NSManagedObjectContext*)moc;

+(NSArray *)allItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(id)itemWithInfo:(NSDictionary*)info type:(NSString*)type moc:(NSManagedObjectContext*)moc;

+(void)assumeWilldeleteItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(void)nukeDeletedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSUInteger)countItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)newOrUpdatedItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+(NSArray*)newItemsOfType:(NSString *)type inMoc:(NSManagedObjectContext *)moc;

+ (void)deleteAllObjectsInContext:(NSManagedObjectContext *)context
                       usingModel:(NSManagedObjectModel *)model;

+ (void)deleteAllObjectsWithEntityName:(NSString *)entityName
                             inContext:(NSManagedObjectContext *)context;
@end
