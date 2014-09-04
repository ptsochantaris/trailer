
@interface Settings : NSObject

- (NSString *)sortField;

- (void)log:(NSString *)logMessage;

@property (nonatomic) NSInteger sortMethod, statusFilteringMode,
								closeHandlingPolicy, mergeHandlingPolicy, statusItemRefreshInterval;

@property (nonatomic) NSArray *statusFilteringTerms, *commentAuthorBlacklist;

@property (nonatomic) NSDate *latestReceivedEventDateProcessed, *latestUserEventDateProcessed;

@property (nonatomic) NSNumber *localUserId;

@property (nonatomic) NSString *authToken, *localUser,
							*apiFrontEnd, *apiBackEnd, *apiPath,
							*hotkeyLetter, *latestReceivedEventEtag, *latestUserEventEtag;

@property (nonatomic) float refreshPeriod, backgroundRefreshPeriod, newRepoCheckPeriod;

@property (nonatomic) BOOL shouldHideUncommentedRequests, showCommentsEverywhere,
							sortDescending, showCreatedInsteadOfUpdated,
							dontKeepPrsMergedByMe, hideAvatars, autoParticipateInMentions,
							dontAskBeforeWipingMerged, dontAskBeforeWipingClosed,
							includeReposInFilter, showReposInName, hideNewRepositories,
							dontReportRefreshFailures, groupByRepo, hideAllPrsSection,
							showStatusItems, makeStatusItemsSelectable, moveAssignedPrsToMySection,
							markUnmergeableOnUserSectionsOnly, countOnlyListedPrs,
							openPrAtFirstUnreadComment, logActivityToConsole;

@property (nonatomic) BOOL hotkeyEnable, hotkeyCommandModifier, hotkeyOptionModifier, hotkeyShiftModifier, hotkeyControlModifier;

// auto updates in OSX
@property (nonatomic) BOOL checkForUpdatesAutomatically;
@property (nonatomic) NSInteger checkForUpdatesInterval;

@end

extern Settings *settings;

#ifdef DEBUG
	#define DLog(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#elif __MAC_OS_X_VERSION_MIN_REQUIRED
	#define DLog(s, ...) [settings log:[NSString stringWithFormat:s, ##__VA_ARGS__]]
#else
	#define DLog(...)
#endif
