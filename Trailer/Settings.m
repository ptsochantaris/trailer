
Settings *settings;

@implementation Settings
{
	NSUserDefaults *defaults;
	NSMutableDictionary *valuesCache;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        defaults = [NSUserDefaults standardUserDefaults];
		valuesCache = [NSMutableDictionary new];
    }
    return self;
}

- (void)log:(NSString *)logMessage
{
	if(settings.logActivityToConsole) NSLog(@"%@",logMessage);
}

- (NSString *)sortField
{
	switch (self.sortMethod)
	{
		case kCreationDate: return @"createdAt";
		case kRecentActivity: return @"updatedAt";
		case kTitle: return @"title";
	}
	return nil;
}

- (void)storeDefaultValue:(id)value forKey:(NSString *)key
{
	if(value)
	{
		[defaults setObject:value forKey:key];
		[valuesCache setObject:value forKey:key];
		DLog(@"Set %@: %@",key,value);
	}
	else
	{
		[defaults removeObjectForKey:key];
		[valuesCache removeObjectForKey:key];
		DLog(@"Cleared %@",key);
	}
	[defaults synchronize];
}

- (id)defaultValueForKey:(NSString *)key
{
	id v = valuesCache[key];
	if(!v)
	{
		v = [defaults objectForKey:key];
		if(v) [valuesCache setObject:v forKey:key];
	}
	return v;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define IOS_BACKGROUND_REFRESH_PERIOD_KEY @"IOS_BACKGROUND_REFRESH_PERIOD_KEY"
- (float)backgroundRefreshPeriod
{
	float period = [[self defaultValueForKey:IOS_BACKGROUND_REFRESH_PERIOD_KEY] floatValue];
	if(period==0)
	{
		period = 1800.0;
		self.backgroundRefreshPeriod = period;
	}
	return period;
}
- (void)setBackgroundRefreshPeriod:(float)backgroundRefreshPeriod
{
#ifdef __IPHONE_OS_VERSION_MIN_REQUIRED
	[[UIApplication sharedApplication] setMinimumBackgroundFetchInterval:backgroundRefreshPeriod];
#endif
	[self storeDefaultValue:@(backgroundRefreshPeriod) forKey:IOS_BACKGROUND_REFRESH_PERIOD_KEY];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define REFRESH_PERIOD_KEY @"REFRESH_PERIOD_KEY"
- (float)refreshPeriod
{
	float period = [[self defaultValueForKey:REFRESH_PERIOD_KEY] floatValue];
	if(period<60.0)
	{
		period = 120.0;
		self.refreshPeriod = period;
	}
	return period;
}
- (void)setRefreshPeriod:(float)refreshPeriod
{
	[self storeDefaultValue:@(refreshPeriod) forKey:REFRESH_PERIOD_KEY];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define NEW_REPO_CHECK_PERIOD @"NEW_REPO_CHECK_PERIOD"
- (float)newRepoCheckPeriod
{
	float period = [[self defaultValueForKey:NEW_REPO_CHECK_PERIOD] floatValue];
	if(period==0)
	{
		period = 2;
		self.newRepoCheckPeriod = period;
	}
	return period;
}
- (void)setNewRepoCheckPeriod:(float)newRepoCheckPeriod
{
	[self storeDefaultValue:@(newRepoCheckPeriod) forKey:NEW_REPO_CHECK_PERIOD];
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HIDE_PRS_KEY @"HIDE_UNCOMMENTED_PRS_KEY"
- (void)setShouldHideUncommentedRequests:(BOOL)shouldHideUncommentedRequests { [self storeDefaultValue:@(shouldHideUncommentedRequests) forKey:HIDE_PRS_KEY]; }
- (BOOL)shouldHideUncommentedRequests { return [[self defaultValueForKey:HIDE_PRS_KEY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY @"OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY"
- (void)setOpenPrAtFirstUnreadComment:(BOOL)openPrAtFirstUnreadComment { [self storeDefaultValue:@(openPrAtFirstUnreadComment) forKey:OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY]; }
- (BOOL)openPrAtFirstUnreadComment { return [[self defaultValueForKey:OPEN_PR_AT_FIRST_UNREAD_COMMENT_KEY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HIDE_NEW_REPOS_KEY @"HIDE_NEW_REPOS_KEY"
- (void)setHideNewRepositories:(BOOL)hideNewRepositories { [self storeDefaultValue:@(hideNewRepositories) forKey:HIDE_NEW_REPOS_KEY]; }
- (BOOL)hideNewRepositories { return [[self defaultValueForKey:HIDE_NEW_REPOS_KEY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SHOW_COMMENTS_EVERYWHERE_KEY @"SHOW_COMMENTS_EVERYWHERE_KEY"
- (BOOL)showCommentsEverywhere { return [[self defaultValueForKey:SHOW_COMMENTS_EVERYWHERE_KEY] boolValue]; }
- (void)setShowCommentsEverywhere:(BOOL)showCommentsEverywhere { [self storeDefaultValue:@(showCommentsEverywhere) forKey:SHOW_COMMENTS_EVERYWHERE_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define LOG_ACTIVITY_TO_CONSOLE_KEY @"LOG_ACTIVITY_TO_CONSOLE_KEY"
- (BOOL)logActivityToConsole { return [[self defaultValueForKey:LOG_ACTIVITY_TO_CONSOLE_KEY] boolValue]; }
- (void)setLogActivityToConsole:(BOOL)logActivityToConsole { [self storeDefaultValue:@(logActivityToConsole) forKey:LOG_ACTIVITY_TO_CONSOLE_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SORT_ORDER_KEY @"SORT_ORDER_KEY"
- (BOOL)sortDescending { return [[self defaultValueForKey:SORT_ORDER_KEY] boolValue]; }
- (void)setSortDescending:(BOOL)sortDescending { [self storeDefaultValue:@(sortDescending) forKey:SORT_ORDER_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SHOW_UPDATED_KEY @"SHOW_UPDATED_KEY"
- (BOOL)showCreatedInsteadOfUpdated { return [[self defaultValueForKey:SHOW_UPDATED_KEY] boolValue]; }
- (void)setShowCreatedInsteadOfUpdated:(BOOL)showCreatedInsteadOfUpdated { [self storeDefaultValue:@(showCreatedInsteadOfUpdated) forKey:SHOW_UPDATED_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#define SORT_METHOD_KEY @"SORT_METHOD_KEY"
- (NSInteger)sortMethod { return [[self defaultValueForKey:SORT_METHOD_KEY] integerValue]; }
- (void)setSortMethod:(NSInteger)sortMethod { [self storeDefaultValue:@(sortMethod) forKey:SORT_METHOD_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define STATUS_FILTERING_METHOD_KEY @"STATUS_FILTERING_METHOD_KEY"
- (NSInteger)statusFilteringMode { return [[self defaultValueForKey:STATUS_FILTERING_METHOD_KEY] integerValue]; }
- (void)setStatusFilteringMode:(NSInteger)statusFilteringMode { [self storeDefaultValue:@(statusFilteringMode) forKey:STATUS_FILTERING_METHOD_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define UPDATE_CHECK_INTERVAL_KEY @"UPDATE_CHECK_INTERVAL_KEY"
- (NSInteger)checkForUpdatesInterval
{
    id item = [self defaultValueForKey:UPDATE_CHECK_INTERVAL_KEY];
    if(item)
    {
        return [item integerValue];
    }
    else
    {
        return 8;
    }
}
- (void)setCheckForUpdatesInterval:(NSInteger)checkForUpdatesInterval { [self storeDefaultValue:@(checkForUpdatesInterval) forKey:UPDATE_CHECK_INTERVAL_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define UPDATE_CHECK_AUTO_KEY @"UPDATE_CHECK_AUTO_KEY"
- (void)setCheckForUpdatesAutomatically:(BOOL)checkForUpdatesAutomatically { [self storeDefaultValue:@(checkForUpdatesAutomatically) forKey:UPDATE_CHECK_AUTO_KEY]; }
- (BOOL)checkForUpdatesAutomatically
{
    id item = [self defaultValueForKey:UPDATE_CHECK_AUTO_KEY];
    if(item)
    {
        return [item boolValue];
    }
    else
    {
        return YES;
    }
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define STATUS_FILTERING_TERMS_KEY @"STATUS_FILTERING_TERMS_KEY"
- (NSArray *)statusFilteringTerms { return [self defaultValueForKey:STATUS_FILTERING_TERMS_KEY]; }
- (void)setStatusFilteringTerms:(NSArray *)statusFilteringTerms { [self storeDefaultValue:statusFilteringTerms forKey:STATUS_FILTERING_TERMS_KEY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define COMMENT_AUTHOR_BLACKLIST @"COMMENT_AUTHOR_BLACKLIST"
- (NSArray *)commentAuthorBlacklist
{
	NSArray *r = [self defaultValueForKey:COMMENT_AUTHOR_BLACKLIST];
	if(!r) r = @[];
	return r;
}
- (void)setCommentAuthorBlacklist:(NSArray *)commentAuthorBlacklist { [self storeDefaultValue:commentAuthorBlacklist forKey:COMMENT_AUTHOR_BLACKLIST]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define DONT_KEEP_MY_PRS_KEY @"DONT_KEEP_MY_PRS_KEY"
- (void)setDontKeepPrsMergedByMe:(BOOL)dontKeepPrsMergedByMe { [self storeDefaultValue:@(dontKeepPrsMergedByMe) forKey:DONT_KEEP_MY_PRS_KEY]; }
- (BOOL)dontKeepPrsMergedByMe { return [[self defaultValueForKey:DONT_KEEP_MY_PRS_KEY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HIDE_AVATARS_KEY @"HIDE_AVATARS_KEY"
- (void)setHideAvatars:(BOOL)hideAvatars { [self storeDefaultValue:@(hideAvatars) forKey:HIDE_AVATARS_KEY]; }
- (BOOL)hideAvatars { return [[self defaultValueForKey:HIDE_AVATARS_KEY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define AUTO_PARTICIPATE_IN_MENTIONS_KEY @"AUTO_PARTICIPATE_IN_MENTIONS_KEY"
- (void)setAutoParticipateInMentions:(BOOL)autoParticipateInMentions { [self storeDefaultValue:@(autoParticipateInMentions) forKey:AUTO_PARTICIPATE_IN_MENTIONS_KEY]; }
- (BOOL)autoParticipateInMentions { return [[self defaultValueForKey:AUTO_PARTICIPATE_IN_MENTIONS_KEY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define DONT_ASK_BEFORE_WIPING_MERGED @"DONT_ASK_BEFORE_WIPING_MERGED"
- (void)setDontAskBeforeWipingMerged:(BOOL)dontAskBeforeWipingMerged { [self storeDefaultValue:@(dontAskBeforeWipingMerged) forKey:DONT_ASK_BEFORE_WIPING_MERGED]; }
- (BOOL)dontAskBeforeWipingMerged { return [[self defaultValueForKey:DONT_ASK_BEFORE_WIPING_MERGED] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define DONT_ASK_BEFORE_WIPING_CLOSED @"DONT_ASK_BEFORE_WIPING_CLOSED"
- (void)setDontAskBeforeWipingClosed:(BOOL)dontAskBeforeWipingClosed { [self storeDefaultValue:@(dontAskBeforeWipingClosed) forKey:DONT_ASK_BEFORE_WIPING_CLOSED]; }
- (BOOL)dontAskBeforeWipingClosed { return [[self defaultValueForKey:DONT_ASK_BEFORE_WIPING_CLOSED] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define INCLUDE_REPOS_IN_FILTER @"INCLUDE_REPOS_IN_FILTER"
- (void)setIncludeReposInFilter:(BOOL)includeReposInFilter { [self storeDefaultValue:@(includeReposInFilter) forKey:INCLUDE_REPOS_IN_FILTER]; }
- (BOOL)includeReposInFilter { return [[self defaultValueForKey:INCLUDE_REPOS_IN_FILTER] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SHOW_REPOS_IN_NAME @"SHOW_REPOS_IN_NAME"
- (void)setShowReposInName:(BOOL)showReposInName { [self storeDefaultValue:@(showReposInName) forKey:SHOW_REPOS_IN_NAME]; }
- (BOOL)showReposInName { return [[self defaultValueForKey:SHOW_REPOS_IN_NAME] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define DONT_REPORT_REFRESH_FAILURES @"DONT_REPORT_REFRESH_FAILURES"
- (void)setDontReportRefreshFailures:(BOOL)dontReportRefreshFailures { [self storeDefaultValue:@(dontReportRefreshFailures) forKey:DONT_REPORT_REFRESH_FAILURES]; }
- (BOOL)dontReportRefreshFailures { return [[self defaultValueForKey:DONT_REPORT_REFRESH_FAILURES] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define GROUP_BY_REPO @"GROUP_BY_REPO"
- (void)setGroupByRepo:(BOOL)groupByRepo { [self storeDefaultValue:@(groupByRepo) forKey:GROUP_BY_REPO]; }
- (BOOL)groupByRepo { return [[self defaultValueForKey:GROUP_BY_REPO] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HIDE_ALL_SECTION @"HIDE_ALL_SECTION"
- (void)setHideAllPrsSection:(BOOL)hideAllPrsSection { [self storeDefaultValue:@(hideAllPrsSection) forKey:HIDE_ALL_SECTION]; }
- (BOOL)hideAllPrsSection { return [[self defaultValueForKey:HIDE_ALL_SECTION] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define SHOW_STATUS_ITEMS @"SHOW_STATUS_ITEMS"
- (void)setShowStatusItems:(BOOL)showStatusItems { [self storeDefaultValue:@(showStatusItems) forKey:SHOW_STATUS_ITEMS]; }
- (BOOL)showStatusItems { return [[self defaultValueForKey:SHOW_STATUS_ITEMS] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define MAKE_STATUS_ITEMS_SELECTABLE @"MAKE_STATUS_ITEMS_SELECTABLE"
- (void)setMakeStatusItemsSelectable:(BOOL)makeStatusItemsSelectable { [self storeDefaultValue:@(makeStatusItemsSelectable) forKey:MAKE_STATUS_ITEMS_SELECTABLE]; }
- (BOOL)makeStatusItemsSelectable { return [[self defaultValueForKey:MAKE_STATUS_ITEMS_SELECTABLE] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define MOVE_ASSIGNED_PRS_TO_MY_SECTION @"MOVE_ASSIGNED_PRS_TO_MY_SECTION"
- (void)setMoveAssignedPrsToMySection:(BOOL)moveAssignedPrsToMySection { [self storeDefaultValue:@(moveAssignedPrsToMySection) forKey:MOVE_ASSIGNED_PRS_TO_MY_SECTION]; }
- (BOOL)moveAssignedPrsToMySection { return [[self defaultValueForKey:MOVE_ASSIGNED_PRS_TO_MY_SECTION] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY @"MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY"
- (void)setMarkUnmergeableOnUserSectionsOnly:(BOOL)markUnmergeableOnUserSectionsOnly { [self storeDefaultValue:@(markUnmergeableOnUserSectionsOnly) forKey:MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY]; }
- (BOOL)markUnmergeableOnUserSectionsOnly { return [[self defaultValueForKey:MARK_UNMERGEABLE_ON_USER_SECTIONS_ONLY] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HOTKEY_ENABLE @"HOTKEY_ENABLE"
- (void)setHotkeyEnable:(BOOL)hotkeyEnable { [self storeDefaultValue:@(hotkeyEnable) forKey:HOTKEY_ENABLE]; }
- (BOOL)hotkeyEnable { return [[self defaultValueForKey:HOTKEY_ENABLE] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define REPO_SUBSCRIPTION_POLICY @"REPO_SUBSCRIPTION_POLICY"
- (NSInteger)repoSubscriptionPolicy { return [[self defaultValueForKey:REPO_SUBSCRIPTION_POLICY] integerValue]; }
- (void)setRepoSubscriptionPolicy:(NSInteger)repoSubscriptionPolicy { [self storeDefaultValue:@(repoSubscriptionPolicy) forKey:REPO_SUBSCRIPTION_POLICY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define MERGE_HANDLING_POLICY @"MERGE_HANDLING_POLICY"
- (NSInteger)mergeHandlingPolicy { return [[self defaultValueForKey:MERGE_HANDLING_POLICY] integerValue]; }
- (void)setMergeHandlingPolicy:(NSInteger)mergeHandlingPolicy { [self storeDefaultValue:@(mergeHandlingPolicy) forKey:MERGE_HANDLING_POLICY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define CLOSE_HANDLING_POLICY @"CLOSE_HANDLING_POLICY"
- (NSInteger)closeHandlingPolicy { return [[self defaultValueForKey:CLOSE_HANDLING_POLICY] integerValue]; }
- (void)setCloseHandlingPolicy:(NSInteger)closeHandlingPolicy { [self storeDefaultValue:@(closeHandlingPolicy) forKey:CLOSE_HANDLING_POLICY]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define STATUS_ITEM_REFRESH_COUNT @"STATUS_ITEM_REFRESH_COUNT"
- (NSInteger)statusItemRefreshInterval
{
	NSInteger i = [[self defaultValueForKey:STATUS_ITEM_REFRESH_COUNT] integerValue];
	if(i==0) i = 10;
	return i;
}
- (void)setStatusItemRefreshInterval:(NSInteger)statusItemRefreshInterval { [self storeDefaultValue:@(statusItemRefreshInterval) forKey:STATUS_ITEM_REFRESH_COUNT]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define COUNT_ONLY_LISTED_PRS @"COUNT_ONLY_LISTED_PRS"
- (void)setCountOnlyListedPrs:(BOOL)countOnlyListedPrs { [self storeDefaultValue:@(countOnlyListedPrs) forKey:COUNT_ONLY_LISTED_PRS]; }
- (BOOL)countOnlyListedPrs { return [[self defaultValueForKey:COUNT_ONLY_LISTED_PRS] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HOTKEY_CONTROL_MODIFIER @"HOTKEY_CONTROL_MODIFIER"
- (void)setHotkeyControlModifier:(BOOL)hotkeyControlModifier { [self storeDefaultValue:@(hotkeyControlModifier) forKey:HOTKEY_CONTROL_MODIFIER]; }
- (BOOL)hotkeyControlModifier { return [[self defaultValueForKey:HOTKEY_CONTROL_MODIFIER] boolValue]; }

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HOTKEY_COMMAND_MODIFIER @"HOTKEY_COMMAND_MODIFIER"
- (void)setHotkeyCommandModifier:(BOOL)hotkeyCommandModifier { [self storeDefaultValue:@(hotkeyCommandModifier) forKey:HOTKEY_COMMAND_MODIFIER]; }
- (BOOL)hotkeyCommandModifier
{
	NSString *v = [self defaultValueForKey:HOTKEY_COMMAND_MODIFIER];
	if(!v) return YES;
	return v.boolValue;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HOTKEY_SHIFT_MODIFIER @"HOTKEY_SHIFT_MODIFIER"
- (void)setHotkeyShiftModifier:(BOOL)hotkeyShiftModifier { [self storeDefaultValue:@(hotkeyShiftModifier) forKey:HOTKEY_SHIFT_MODIFIER]; }
- (BOOL)hotkeyShiftModifier
{
	NSString *v = [self defaultValueForKey:HOTKEY_SHIFT_MODIFIER];
	if(!v) return YES;
	return v.boolValue;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HOTKEY_OPTION_MODIFIER @"HOTKEY_OPTION_MODIFIER"
- (void)setHotkeyOptionModifier:(BOOL)hotkeyOptionModifier { [self storeDefaultValue:@(hotkeyOptionModifier) forKey:HOTKEY_OPTION_MODIFIER]; }
- (BOOL)hotkeyOptionModifier
{
	NSString *v = [self defaultValueForKey:HOTKEY_OPTION_MODIFIER];
	if(!v) return YES;
	return v.boolValue;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

#define HOTKEY_LETTER @"HOTKEY_LETTER"
- (NSString *)hotkeyLetter
{
	NSString *value = [self defaultValueForKey:HOTKEY_LETTER];
	if(!value) value = @"T";
	return value;
}
- (void)setHotkeyLetter:(NSString *)hotkeyLetter { [self storeDefaultValue:hotkeyLetter forKey:HOTKEY_LETTER]; }

@end
