
@interface Settings : NSObject

+ (Settings *)shared;

- (NSString *)sortField;

@property (nonatomic) NSInteger sortMethod;

@property (nonatomic) NSString *authToken, *localUser, *localUserId,
							*apiFrontEnd, *apiBackEnd;

@property (nonatomic) float refreshPeriod, backgroundRefreshPeriod;

@property (nonatomic) BOOL shouldHideUncommentedRequests, showCommentsEverywhere,
							sortDescending, showCreatedInsteadOfUpdated,
							dontKeepMyPrs, hideAvatars, autoParticipateInMentions,
							alsoKeepClosedPrs, dontAskBeforeWipingMerged,
							dontAskBeforeWipingClosed, includeReposInFilter, showReposInName,
							dontReportRefreshFailures, groupByRepo;

@end
