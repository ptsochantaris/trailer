
@class PullRequest;

@interface PRStatus : DataItem

@property (nonatomic, retain) NSString * state;
@property (nonatomic, retain) NSString * targetUrl;
@property (nonatomic, retain) NSString * descriptionText;
@property (nonatomic, retain) NSDate * createdAt;
@property (nonatomic, retain) NSNumber * serverId;
@property (nonatomic, retain) NSDate * updatedAt;
@property (nonatomic, retain) NSString * url;
@property (nonatomic, retain) NSNumber * userId;
@property (nonatomic, retain) NSString * userName;
@property (nonatomic, retain) PullRequest *pullRequest;

+ (PRStatus *)statusWithInfo:(NSDictionary *)info fromServer:(ApiServer *)apiServer;

- (COLOR_CLASS *)colorForDisplay;

- (NSString *)displayText;

@end
