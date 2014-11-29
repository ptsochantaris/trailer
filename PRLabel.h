#import "DataItem.h"

@class ApiServer, PullRequest;

@interface PRLabel : DataItem

@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSString * name;
@property (nonatomic, retain) NSNumber * color;
@property (nonatomic, retain) NSDate * createdAt;
@property (nonatomic, retain) NSNumber * postSyncAction;
@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSDate * updatedAt;
@property (nonatomic, retain) ApiServer *apiServer;
@property (nonatomic, retain) PullRequest *pullRequest;

+ (PRLabel *)labelWithInfo:(NSDictionary *)info fromServer:(ApiServer *)apiServer;

- (COLOR_CLASS *)colorForDisplay;

@end
