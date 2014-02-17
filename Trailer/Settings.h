
@interface Settings : NSObject

+ (Settings *)shared;

- (NSString *)sortField;

@property (nonatomic) NSInteger sortMethod, statusFilteringMode,
								repoSubscriptionPolicy;

@property (nonatomic) NSArray *statusFilteringTerms;

@property (nonatomic) NSString *authToken, *localUser, *localUserId,
							*apiFrontEnd, *apiBackEnd, *apiPath,
							*hotkeyLetter;

@property (nonatomic) float refreshPeriod, backgroundRefreshPeriod, newRepoCheckPeriod;

@property (nonatomic) BOOL shouldHideUncommentedRequests, showCommentsEverywhere,
							sortDescending, showCreatedInsteadOfUpdated,
							dontKeepMyPrs, hideAvatars, autoParticipateInMentions,
							alsoKeepClosedPrs, dontAskBeforeWipingMerged,
							dontAskBeforeWipingClosed, includeReposInFilter, showReposInName,
							dontReportRefreshFailures, groupByRepo, hideAllPrsSection,
							showStatusItems, makeStatusItemsSelectable, moveAssignedPrsToMySection,
							markUnmergeableOnUserSectionsOnly;

@property (nonatomic) BOOL hotkeyEnable, hotkeyCommandModifier, hotkeyOptionModifier, hotkeyShiftModifier;

@end
