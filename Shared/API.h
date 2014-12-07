#import "Reachability.h"

@class ApiServer;

@interface API : NSObject

@property (nonatomic) Reachability *reachability;
@property (nonatomic) long successfulRefreshesSinceLastStatusCheck, successfulRefreshesSinceLastLabelCheck;

- (void)updateLimitsFromServer;

- (void)fetchRepositoriesToMoc:(NSManagedObjectContext *)moc
				   andCallback:(completionBlockType)callback;

- (void)fetchPullRequestsForActiveReposAndCallback:(completionBlockType)callback;

- (void)getRateLimitFromServer:(ApiServer *)apiServer
				   andCallback:(void(^)(long long remaining, long long limit, long long reset))callback;

- (void)testApiToServer:(ApiServer *)apiServer andCallback:(void (^)(NSError *))callback;

- (void)expireOldImageCacheEntries;

- (void)clearImageCache;

- (NSString *)lastUpdateDescription;

- (BOOL)haveCachedAvatar:(NSString *)path
	  tryLoadAndCallback:(void(^)(IMAGE_CLASS *image))callbackOrNil;

@end
