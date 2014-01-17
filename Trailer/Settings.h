
@interface Settings : NSObject

+ (Settings *)shared;

- (NSString *)sortField;

@property (nonatomic) NSInteger sortMethod;

@property (nonatomic) NSString *authToken, *localUser, *localUserId;

@property (nonatomic) float refreshPeriod, backgroundRefreshPeriod;

@property (nonatomic) BOOL shouldHideUncommentedRequests, showCommentsEverywhere,
							sortDescending, showCreatedInsteadOfUpdated,
							dontKeepMyPrs, hideAvatars, autoParticipateInMentions,
							alsoKeepClosedPrs;

@end
