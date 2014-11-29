
@interface Settings : NSObject

- (NSString *)sortField;

- (void)log:(NSString *)logMessage;

@property (nonatomic) NSInteger sortMethod, statusFilteringMode, lastPreferencesTabSelected,
								closeHandlingPolicy, mergeHandlingPolicy, statusItemRefreshInterval,
								labelRefreshInterval;

@property (nonatomic) NSArray *statusFilteringTerms, *commentAuthorBlacklist;

@property (nonatomic) NSString *hotkeyLetter;

@property (nonatomic) float refreshPeriod, backgroundRefreshPeriod, newRepoCheckPeriod;

@property (nonatomic) BOOL shouldHideUncommentedRequests, showCommentsEverywhere,
							sortDescending, showCreatedInsteadOfUpdated,
							dontKeepPrsMergedByMe, hideAvatars, autoParticipateInMentions,
							dontAskBeforeWipingMerged, dontAskBeforeWipingClosed,
							includeReposInFilter, showReposInName, hideNewRepositories,
							groupByRepo, hideAllPrsSection, showLabels,
							showStatusItems, makeStatusItemsSelectable, moveAssignedPrsToMySection,
							markUnmergeableOnUserSectionsOnly, countOnlyListedPrs,
							openPrAtFirstUnreadComment, logActivityToConsole;

@property (nonatomic) BOOL hotkeyEnable, hotkeyCommandModifier, hotkeyOptionModifier, hotkeyShiftModifier, hotkeyControlModifier;

// OSX only
@property (nonatomic) BOOL checkForUpdatesAutomatically, useVibrancy;
@property (nonatomic) NSInteger checkForUpdatesInterval;

@end

extern Settings *settings;

