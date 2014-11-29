#import "DataItem.h"

@interface PRComment : DataItem

@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSNumber * postSyncAction;
@property (nonatomic, retain) NSDate * updatedAt;
@property (nonatomic, retain) NSNumber * position;
@property (nonatomic, retain) NSString * body;
@property (nonatomic, retain) NSString * userName;
@property (nonatomic, retain) NSString * avatarUrl;
@property (nonatomic, retain) NSString * path;
@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSString * webUrl;
@property (nonatomic, retain) NSNumber * userId;
@property (nonatomic, retain) PullRequest *pullRequest;

+ (PRComment *)commentWithInfo:(NSDictionary *)info fromServer:(ApiServer *)apiServer;

- (BOOL)isMine;

- (BOOL)refersToMe;

@end
