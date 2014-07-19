
@interface AppDelegate ()
{
	// Keyboard support
	id globalKeyMonitor, localKeyMonitor;
	NSMutableArray *currentPRItems;
}
@end

@implementation AppDelegate

static AppDelegate *_static_shared_ref;
+ (AppDelegate *)shared { return _static_shared_ref; }

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Useful snippet for resetting prefs when testing
	//NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
	//[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];

	self.currentAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];

	self.mainMenu.backgroundColor = [COLOR_CLASS whiteColor];

	self.filterTimer = [[HTPopTimer alloc] initWithTimeInterval:0.2 target:self selector:@selector(filterTimerPopped)];

	[NSThread setThreadPriority:0.0];

	_static_shared_ref = self;

	self.dataManager = [[DataManager alloc] init];
	self.api = [[API alloc] init];

	[self setupSortMethodMenu];

	// ONLY FOR DEBUG!
	/*
	NSArray *allPRs = [PullRequest allItemsOfType:@"PullRequest" inMoc:self.dataManager.managedObjectContext];
	PullRequest *firstPr = allPRs[2];
	firstPr.updatedAt = [NSDate distantPast];

	Repo *r = [Repo itemOfType:@"Repo" serverId:firstPr.repoId moc:self.dataManager.managedObjectContext];
	r.updatedAt = [NSDate distantPast];

	NSString *prUrl = firstPr.url;
	NSArray *allCommentsForFirstPr = [PRComment commentsForPullRequestUrl:prUrl inMoc:self.dataManager.managedObjectContext];
    [self.dataManager.managedObjectContext deleteObject:[allCommentsForFirstPr objectAtIndex:0]];
	 */
	// ONLY FOR DEBUG!

	[self.dataManager postProcessAllPrs];

	[self updateScrollBarWidth]; // also updates menu

	[self startRateLimitHandling];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(defaultsUpdated)
												 name:NSUserDefaultsDidChangeNotification
											   object:nil];

	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

	NSString *currentAppVersion = [@"Version " stringByAppendingString:self.currentAppVersion];
	[self.versionNumber setStringValue:currentAppVersion];
	[self.aboutVersion setStringValue:currentAppVersion];

	if([Settings shared].authToken.length)
	{
		[self.githubTokenHolder setStringValue:[Settings shared].authToken];
		[self startRefresh];
	}
	else
	{
		[self preferencesSelected:nil];
	}

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(networkStateChanged)
												 name:kReachabilityChangedNotification
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(prItemFocused:)
												 name:PR_ITEM_FOCUSED_NOTIFICATION_KEY
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateScrollBarWidth)
												 name:NSPreferredScrollerStyleDidChangeNotification
											   object:nil];

	[self addHotKeySupport];

	SUUpdater *s = [SUUpdater sharedUpdater];
    [self setUpdateCheckParameters];
	if(!s.updateInProgress && [Settings shared].checkForUpdatesAutomatically)
	{
		[s checkForUpdatesInBackground];
	}
}

- (void)setupSortMethodMenu
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Sorting"];
	if([Settings shared].sortDescending)
	{
		[m addItemWithTitle:@"Youngest First" action:@selector(sortMethodChanged:) keyEquivalent:@""];
		[m addItemWithTitle:@"Most Recently Active" action:@selector(sortMethodChanged:) keyEquivalent:@""];
		[m addItemWithTitle:@"Reverse Alphabetically" action:@selector(sortMethodChanged:) keyEquivalent:@""];
	}
	else
	{
		[m addItemWithTitle:@"Oldest First" action:@selector(sortMethodChanged:) keyEquivalent:@""];
		[m addItemWithTitle:@"Inactive For Longest" action:@selector(sortMethodChanged:) keyEquivalent:@""];
		[m addItemWithTitle:@"Alphabetically" action:@selector(sortMethodChanged:) keyEquivalent:@""];
	}
	self.sortModeSelect.menu = m;
	[self.sortModeSelect selectItemAtIndex:[Settings shared].sortMethod];
}

- (IBAction)dontConfirmRemoveAllMergedSelected:(NSButton *)sender
{
	BOOL dontConfirm = (sender.integerValue==1);
    [Settings shared].dontAskBeforeWipingMerged = dontConfirm;
}

- (IBAction)hideAllPrsSection:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	[Settings shared].hideAllPrsSection = setting;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)markUnmergeableOnUserSectionsOnlySelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	[Settings shared].markUnmergeableOnUserSectionsOnly = setting;
	[self updateMenu];
}

- (IBAction)displayRepositoryNameSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	[Settings shared].showReposInName = setting;
	[self updateMenu];
}

- (IBAction)includeRepositoriesInfilterSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	[Settings shared].includeReposInFilter = setting;
}

- (IBAction)dontReportRefreshFailuresSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	[Settings shared].dontReportRefreshFailures = setting;
}

- (IBAction)dontConfirmRemoveAllClosedSelected:(NSButton *)sender
{
	BOOL dontConfirm = (sender.integerValue==1);
    [Settings shared].dontAskBeforeWipingClosed = dontConfirm;
}

- (IBAction)autoParticipateOnMentionSelected:(NSButton *)sender
{
	BOOL autoParticipate = (sender.integerValue==1);
	[Settings shared].autoParticipateInMentions = autoParticipate;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)dontKeepMyPrsSelected:(NSButton *)sender
{
	BOOL dontKeep = (sender.integerValue==1);
	[Settings shared].dontKeepPrsMergedByMe = dontKeep;
}

- (IBAction)hideAvatarsSelected:(NSButton *)sender
{
	BOOL hide = (sender.integerValue==1);
	[Settings shared].hideAvatars = hide;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)hidePrsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	[Settings shared].shouldHideUncommentedRequests = show;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)showAllCommentsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	[Settings shared].showCommentsEverywhere = show;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)sortOrderSelected:(NSButton *)sender
{
	BOOL descending = (sender.integerValue==1);
	[Settings shared].sortDescending = descending;
	[self setupSortMethodMenu];
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)countOnlyListedPrsSelected:(NSButton *)sender
{
	[Settings shared].countOnlyListedPrs = (sender.integerValue==1);
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)hideNewRespositoriesSelected:(NSButton *)sender
{
	[Settings shared].hideNewRepositories = (sender.integerValue==1);
}

- (IBAction)openPrAtFirstUnreadCommentSelected:(NSButton *)sender
{
	[Settings shared].openPrAtFirstUnreadComment = (sender.integerValue==1);
}

- (IBAction)sortMethodChanged:(id)sender
{
	[Settings shared].sortMethod = self.sortModeSelect.indexOfSelectedItem;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)showStatusItemsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	[Settings shared].showStatusItems = show;
	[self updateMenu];

	[self updateStatusItemsOptions];

	self.api.successfulRefreshesSinceLastStatusCheck = 0;
	self.preferencesDirty = YES;
}

- (void)updateStatusItemsOptions
{
	BOOL enable = [Settings shared].showStatusItems;
	[self.makeStatusItemsSelectable setEnabled:enable];
	[self.statusTermMenu setEnabled:enable];
	[self.statusTermsField setEnabled:enable];
	[self.statusItemRefreshCounter setEnabled:enable];

	if(enable)
	{
		[self.statusItemRescanLabel setAlphaValue:1.0];
		[self.statusItemsRefreshNote setAlphaValue:1.0];
	}
	else
	{
		[self.statusItemRescanLabel setAlphaValue:0.5];
		[self.statusItemsRefreshNote setAlphaValue:0.5];
	}

	self.statusItemRefreshCounter.integerValue = [Settings shared].statusItemRefreshInterval;
	NSInteger count = [Settings shared].statusItemRefreshInterval;
	if(count>1)
		self.statusItemRescanLabel.stringValue = [NSString stringWithFormat:@"...and re-scan once every %ld refreshes",(long)count];
	else
		self.statusItemRescanLabel.stringValue = [NSString stringWithFormat:@"...and re-scan on every refresh"];
}

- (IBAction)statusItemRefreshCountChanged:(NSStepper *)sender
{
	[Settings shared].statusItemRefreshInterval = self.statusItemRefreshCounter.integerValue;
	[self updateStatusItemsOptions];
}

- (IBAction)makeStatusItemsSelectableSelected:(NSButton *)sender
{
	BOOL yes = (sender.integerValue==1);
	[Settings shared].makeStatusItemsSelectable = yes;
	[self updateMenu];
}

- (IBAction)showCreationSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	[Settings shared].showCreatedInsteadOfUpdated = show;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)groupbyRepoSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	[Settings shared].groupByRepo = setting;
	[self updateMenu];
}

- (IBAction)moveAssignedPrsToMySectionSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	[Settings shared].moveAssignedPrsToMySection = setting;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)checkForUpdatesAutomaticallySelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
    [Settings shared].checkForUpdatesAutomatically = setting;
    [self refreshUpdatePreferences];
}

- (void)refreshUpdatePreferences
{
    BOOL setting = [Settings shared].checkForUpdatesAutomatically;
    NSInteger interval = [Settings shared].checkForUpdatesInterval;

    [self.checkForUpdatesLabel setHidden:!setting];
    [self.checkForUpdatesSelector setHidden:!setting];

    [self.checkForUpdatesSelector setIntegerValue:interval];
    [self.checkForUpdatesAutomatically setIntegerValue:setting];
    if(interval<2)
    {
        self.checkForUpdatesLabel.stringValue = [NSString stringWithFormat:@"Check every hour"];
    }
    else
    {
        self.checkForUpdatesLabel.stringValue = [NSString stringWithFormat:@"Check every %ld hours",(long)interval];
    }
}

- (IBAction)checkForUpdatesIntervalChanged:(NSStepper *)sender
{
    [Settings shared].checkForUpdatesInterval = sender.integerValue;
    [self refreshUpdatePreferences];
}

- (IBAction)launchAtStartSelected:(NSButton *)sender
{
	if(sender.integerValue==1)
	{
		[self addAppAsLoginItem];
	}
	else
	{
		[self deleteAppFromLoginItem];
	}
}

- (IBAction)aboutLinkSelected:(NSButton *)sender
{
	NSString *urlToOpen = TRAILER_GITHUB_REPO;
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlToOpen]];
}


- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
	return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
	switch (notification.activationType)
	{
		case NSUserNotificationActivationTypeActionButtonClicked:
		case NSUserNotificationActivationTypeContentsClicked:
		{
			[[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];

			NSString *urlToOpen = notification.userInfo[NOTIFICATION_URL_KEY];
			if(!urlToOpen)
			{
				NSNumber *itemId = notification.userInfo[PULL_REQUEST_ID_KEY];
				PullRequest *pullRequest = nil;
				if(itemId) // it's a pull request
				{
					pullRequest = [PullRequest itemOfType:@"PullRequest" serverId:itemId moc:self.dataManager.managedObjectContext];
					urlToOpen = pullRequest.webUrl;
				}
				else // it's a comment
				{
					itemId = notification.userInfo[COMMENT_ID_KEY];
					PRComment *c = [PRComment itemOfType:@"PRComment" serverId:itemId moc:self.dataManager.managedObjectContext];
					urlToOpen = c.webUrl;
					pullRequest = [PullRequest pullRequestWithUrl:c.pullRequestUrl moc:self.dataManager.managedObjectContext];
				}
				[pullRequest catchUpWithComments];
			}

			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:urlToOpen]];

			[self updateMenu];

			break;
		}
		default: break;
	}
}

- (void)postNotificationOfType:(PRNotificationType)type forItem:(id)item
{
	if(self.preferencesDirty) return;

	NSUserNotification *notification = [[NSUserNotification alloc] init];
	notification.userInfo = [self.dataManager infoForType:type item:item];

	switch (type)
	{
		case kNewMention:
		{
			notification.title = @"Mentioned in Comment";
			notification.informativeText = [item body];
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:[item pullRequestUrl] moc:self.dataManager.managedObjectContext];
			notification.subtitle = associatedRequest.title;
			break;
		}
		case kNewComment:
		{
			notification.title = @"New PR Comment";
			notification.informativeText = [item body];
			PullRequest *associatedRequest = [PullRequest pullRequestWithUrl:[item pullRequestUrl] moc:self.dataManager.managedObjectContext];
			notification.subtitle = associatedRequest.title;
			break;
		}
		case kNewPr:
		{
			notification.title = @"New PR";
			notification.subtitle = [item title];
			break;
		}
		case kPrReopened:
		{
			notification.title = @"Re-Opened PR";
			notification.subtitle = [item title];
			break;
		}
		case kPrMerged:
		{
			notification.title = @"PR Merged!";
			notification.subtitle = [item title];
			break;
		}
		case kPrClosed:
		{
			notification.title = @"PR Closed";
			notification.subtitle = [item title];
			break;
		}
		case kNewRepoSubscribed:
		{
			notification.title = @"New Repository Subscribed";
			notification.subtitle = [item fullName];
			break;
		}
		case kNewRepoAnnouncement:
		{
			notification.title = @"New Repository";
			notification.subtitle = [item fullName];
			break;
		}
	}

	if((type==kNewComment || type==kNewMention) &&
	   ![Settings shared].hideAvatars &&
	   [notification respondsToSelector:@selector(setContentImage:)]) // let's add an avatar on this!
	{
		PRComment *c = (PRComment *)item;
		[self.api haveCachedAvatar:c.avatarUrl
				tryLoadAndCallback:^(NSImage *image) {
					notification.contentImage = image;
					[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
				}];
	}
	else // proceed as normal
	{
		[[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
	}
}

- (void)prItemSelected:(PRItemView *)item alternativeSelect:(BOOL)isAlternative
{
	self.ignoreNextFocusLoss = isAlternative;

	PullRequest *r = [PullRequest itemOfType:@"PullRequest" serverId:item.userInfo moc:self.dataManager.managedObjectContext];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:r.urlForOpening]];
	[r catchUpWithComments];

	NSInteger reSelectIndex = -1;
	if(isAlternative)
	{
		PRItemView *v = [self focusedItemView];
		if(v) reSelectIndex = [currentPRItems indexOfObject:v];
	}

	[self updateMenu];

	if(reSelectIndex>-1 && reSelectIndex<currentPRItems.count)
	{
		PRItemView *v = currentPRItems[reSelectIndex];
		v.focused = YES;
	}
}

- (void)statusItemTapped:(StatusItemView *)statusItem
{
	if(self.statusItemView.highlighted)
	{
		[self closeMenu];
	}
	else
	{
		self.statusItemView.highlighted = YES;
		[self sizeMenuAndShow:YES];
	}
}

- (void)menuWillOpen:(NSMenu *)menu
{
	if([[menu title] isEqualToString:@"Options"])
	{
		if(!self.isRefreshing)
		{
			NSString *prefix;

			if([Settings shared].localUser)
				prefix = [NSString stringWithFormat:@" Refresh %@",[Settings shared].localUser];
			else
				prefix = @" Refresh";

			self.refreshNow.title = [prefix stringByAppendingFormat:@" - %@",[self.api lastUpdateDescription]];
		}
	}
}

- (void)sizeMenuAndShow:(BOOL)show
{
	NSScreen *screen = [NSScreen mainScreen];
	CGFloat menuLeft = self.statusItemView.window.frame.origin.x;
	CGFloat rightSide = screen.visibleFrame.origin.x+screen.visibleFrame.size.width;
	CGFloat overflow = (menuLeft+MENU_WIDTH)-rightSide;
	if(overflow>0) menuLeft -= overflow;

	CGFloat screenHeight = screen.visibleFrame.size.height;
	CGFloat menuHeight = 28.0+[self.mainMenu.scrollView.documentView frame].size.height;
	CGFloat bottom = screen.visibleFrame.origin.y;
	if(menuHeight<screenHeight)
	{
		bottom += screenHeight-menuHeight;
	}
	else
	{
		menuHeight = screenHeight;
	}

	CGRect frame = CGRectMake(menuLeft, bottom, MENU_WIDTH, menuHeight);
	//DLog(@"Will show menu at %f, %f - %f x %f",frame.origin.x,frame.origin.y,frame.size.width,frame.size.height);
	[self.mainMenu setFrame:frame display:NO animate:NO];

	if(show)
	{
		[self displayMenu];
	}
}

- (void)displayMenu
{
	self.opening = YES;
	[self.mainMenu setLevel:NSFloatingWindowLevel];
	[self.mainMenu makeKeyAndOrderFront:self];
	[NSApp activateIgnoringOtherApps:YES];
	self.opening = NO;
}

- (void)closeMenu
{
	self.statusItemView.highlighted = NO;
	[self.mainMenu orderOut:nil];
	for(PRItemView *v in currentPRItems) v.focused = NO;
}

- (void)sectionHeaderRemoveSelectedFrom:(SectionHeader *)header
{
	if([header.title isEqualToString:kPullRequestSectionNames[kPullRequestSectionMerged]])
	{
		if([Settings shared].dontAskBeforeWipingMerged)
		{
			[self removeAllMergedRequests];
		}
		else
		{
			NSArray *mergedRequests = [PullRequest allMergedRequestsInMoc:self.dataManager.managedObjectContext];

			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:[NSString stringWithFormat:@"Clear %ld merged PRs?",mergedRequests.count]];
			[alert setInformativeText:[NSString stringWithFormat:@"This will clear %ld merged PRs from your list.  This action cannot be undone, are you sure?",mergedRequests.count]];
			[alert addButtonWithTitle:@"No"];
			[alert addButtonWithTitle:@"Yes"];
			[alert setShowsSuppressionButton:YES];

			if([alert runModal]==NSAlertSecondButtonReturn)
            {
                [self removeAllMergedRequests];
                if([[alert suppressionButton] state] == NSOnState)
                {
                    [Settings shared].dontAskBeforeWipingMerged = YES;
                }
            }
		}
	}
	else if([header.title isEqualToString:kPullRequestSectionNames[kPullRequestSectionClosed]])
	{
		if([Settings shared].dontAskBeforeWipingClosed)
		{
			[self removeAllClosedRequests];
		}
		else
		{
			NSArray *closedRequests = [PullRequest allClosedRequestsInMoc:self.dataManager.managedObjectContext];

			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:[NSString stringWithFormat:@"Clear %ld closed PRs?",closedRequests.count]];
			[alert setInformativeText:[NSString stringWithFormat:@"This will clear %ld closed PRs from your list.  This action cannot be undone, are you sure?",closedRequests.count]];
			[alert addButtonWithTitle:@"No"];
			[alert addButtonWithTitle:@"Yes"];
			[alert setShowsSuppressionButton:YES];

			if([alert runModal]==NSAlertSecondButtonReturn)
            {
                [self removeAllClosedRequests];
                if([[alert suppressionButton] state] == NSOnState)
                {
                    [Settings shared].dontAskBeforeWipingClosed = YES;
                }
            }
		}
	}
    if(!self.mainMenu.isVisible) [self statusItemTapped:nil];
}

- (void)removeAllMergedRequests
{
	DataManager *dataManager = self.dataManager;
	NSArray *mergedRequests = [PullRequest allMergedRequestsInMoc:dataManager.managedObjectContext];
	for(PullRequest *r in mergedRequests)
		[dataManager.managedObjectContext deleteObject:r];
	[dataManager saveDB];
	[self updateMenu];
}

- (void)removeAllClosedRequests
{
	DataManager *dataManager = self.dataManager;
	NSArray *closedRequests = [PullRequest allClosedRequestsInMoc:dataManager.managedObjectContext];
	for(PullRequest *r in closedRequests)
		[dataManager.managedObjectContext deleteObject:r];
	[dataManager saveDB];
	[self updateMenu];
}

- (void)unPinSelectedFrom:(PRItemView *)item
{
	DataManager *dataManager = self.dataManager;
	PullRequest *r = [PullRequest itemOfType:@"PullRequest" serverId:item.userInfo moc:dataManager.managedObjectContext];
	[dataManager.managedObjectContext deleteObject:r];
	[dataManager saveDB];
	[self updateMenu];
}

- (void)buildPrMenuItemsFromList:(NSArray *)pullRequests
{
	currentPRItems = [NSMutableArray array];

	SectionHeader *myHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:nil title:kPullRequestSectionNames[kPullRequestSectionMine]];
	SectionHeader *participatedHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:nil title:kPullRequestSectionNames[kPullRequestSectionParticipated]];
	SectionHeader *mergedHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:self title:kPullRequestSectionNames[kPullRequestSectionMerged]];
	SectionHeader *closedHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:self title:kPullRequestSectionNames[kPullRequestSectionClosed]];
	SectionHeader *allHeader = [[SectionHeader alloc] initWithRemoveAllDelegate:nil title:kPullRequestSectionNames[kPullRequestSectionAll]];

	NSDictionary *sections = @{
							   @kPullRequestSectionMine: [NSMutableArray arrayWithObject:myHeader],
								@kPullRequestSectionParticipated: [NSMutableArray arrayWithObject:participatedHeader],
								@kPullRequestSectionMerged: [NSMutableArray arrayWithObject:mergedHeader],
								@kPullRequestSectionClosed: [NSMutableArray arrayWithObject:closedHeader],
								@kPullRequestSectionAll: [NSMutableArray arrayWithObject:allHeader],
								};

	for(PullRequest *r in pullRequests)
	{
		PRItemView *view = [[PRItemView alloc] initWithPullRequest:r userInfo:r.serverId delegate:self];
		[sections[r.sectionIndex] addObject:view];
	}

	for(NSInteger section=kPullRequestSectionMine;section<=kPullRequestSectionAll;section++)
	{
		NSArray *itemsInSection = sections[@(section)];
		for(NSInteger p=1;p<itemsInSection.count;p++) // first item is the header
			[currentPRItems addObject:itemsInSection[p]];
	}

	CGFloat top = 10.0;
	NSView *menuContents = [[NSView alloc] initWithFrame:CGRectZero];

	if(pullRequests.count)
	{
		for(NSInteger section=kPullRequestSectionAll; section>=kPullRequestSectionMine; section--)
		{
			NSArray *itemsInSection = sections[@(section)];
			if(itemsInSection.count>1)
			{
				for(NSView *v in [itemsInSection reverseObjectEnumerator])
				{
					CGFloat H = v.frame.size.height;
					v.frame = CGRectMake(0, top, MENU_WIDTH, H);
					top += H;
					[menuContents addSubview:v];
				}
			}
		}
	}
	else
	{
		top = 100;
		EmptyView *empty = [[EmptyView alloc] initWithFrame:CGRectMake(0, 0, MENU_WIDTH, top)
													message:[self.dataManager reasonForEmptyWithFilter:self.mainMenuFilter.stringValue]];
		[menuContents addSubview:empty];
	}

	menuContents.frame = CGRectMake(0, 0, MENU_WIDTH, top);

	CGPoint lastPos = self.mainMenu.scrollView.contentView.documentVisibleRect.origin;
	self.mainMenu.scrollView.documentView = menuContents;
	[self.mainMenu.scrollView.documentView scrollPoint:lastPos];
}

- (void)defaultsUpdated
{
	NSTableColumn *repositoryColumn = [self.projectsTable tableColumns][1];

	if([Settings shared].localUser)
		[[repositoryColumn headerCell] setStringValue:[NSString stringWithFormat:@" Watched repositories for %@",[Settings shared].localUser]];
	else
		[[repositoryColumn headerCell] setStringValue:@" Your watched repositories"];
}

- (void)startRateLimitHandling
{
	[self.apiLoad setIndeterminate:YES];
	[self.apiLoad stopAnimation:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(apiUsageUpdate:) name:RATE_UPDATE_NOTIFICATION object:nil];
	if([Settings shared].authToken.length)
	{
		[self.api updateLimitFromServer];
	}
}

- (void)apiUsageUpdate:(NSNotification *)n
{
	[self.apiLoad setIndeterminate:NO];
	self.apiLoad.maxValue = self.api.requestsLimit;
	self.apiLoad.doubleValue = self.api.requestsLimit-self.api.requestsRemaining;
}


- (IBAction)refreshReposSelected:(NSButton *)sender
{
	[self prepareForRefresh];
	[self controlTextDidChange:nil];

	[self.api fetchRepositoriesAndCallback:^(BOOL success) {
		[self completeRefresh];
		if(!success)
		{
			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:@"Error"];
			[alert setInformativeText:@"Could not refresh repository list, please ensure that the token you are using is valid"];
			[alert addButtonWithTitle:@"OK"];
			[alert runModal];
		}
	}];
}

- (void)tokenChanged
{
	NSString *newToken = [self.githubTokenHolder.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSString *oldToken = [Settings shared].authToken;
	if(newToken.length>0)
	{
		self.refreshButton.enabled = YES;
		[Settings shared].authToken = newToken;
	}
	else
	{
		self.refreshButton.enabled = NO;
		[Settings shared].authToken = nil;
	}
	if(newToken && oldToken && ![newToken isEqualToString:oldToken])
	{
		[self reset];
	}
}

- (void)controlTextDidChange:(NSNotification *)obj
{
	if(obj.object==self.githubTokenHolder)
	{
		[self tokenChanged];
	}
	else if(obj.object==self.repoFilter)
	{
		[self.projectsTable reloadData];
	}
	else if(obj.object==self.mainMenuFilter)
	{
		[self.filterTimer push];
	}
	else if(obj.object==self.statusTermsField)
	{
		NSArray *existingTerms = [Settings shared].statusFilteringTerms;
		NSArray *newTerms = self.statusTermsField.objectValue;
		if(![existingTerms isEqualToArray:newTerms])
		{
			[Settings shared].statusFilteringTerms = newTerms;
			[self updateMenu];
		}
	}
}

- (void)filterTimerPopped
{
	[self updateMenu];
	[self scrollToTop];
}

- (void)reset
{
	self.preferencesDirty = YES;
	self.api.successfulRefreshesSinceLastStatusCheck = 0;
	self.lastSuccessfulRefresh = nil;
	[self.dataManager deleteEverything];
	[self.projectsTable reloadData];
	[self updateMenu];
}

- (IBAction)markAllReadSelected:(NSMenuItem *)sender
{
	NSManagedObjectContext *moc = self.dataManager.managedObjectContext;
	NSFetchRequest *f = [PullRequest requestForPullRequestsWithFilter:self.mainMenuFilter.stringValue];

	for(PullRequest *r in [moc executeFetchRequest:f error:nil])
		[r catchUpWithComments];
	[self updateMenu];
}

- (IBAction)preferencesSelected:(NSMenuItem *)sender
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	[self.api updateLimitFromServer];
	[self updateStatusTermPreferenceControls];

	[self.sortModeSelect selectItemAtIndex:[Settings shared].sortMethod];
	[self.prMergedPolicy selectItemAtIndex:[Settings shared].mergeHandlingPolicy];
	[self.prClosedPolicy selectItemAtIndex:[Settings shared].closeHandlingPolicy];

	self.launchAtStartup.integerValue = [self isAppLoginItem];
	self.hideAllPrsSection.integerValue = [Settings shared].hideAllPrsSection;
	self.dontConfirmRemoveAllClosed.integerValue = [Settings shared].dontAskBeforeWipingClosed;
	self.dontReportRefreshFailures.integerValue = [Settings shared].dontReportRefreshFailures;
	self.displayRepositoryNames.integerValue = [Settings shared].showReposInName;
	self.includeRepositoriesInFiltering.integerValue = [Settings shared].includeReposInFilter;
	self.dontConfirmRemoveAllMerged.integerValue = [Settings shared].dontAskBeforeWipingMerged;
	self.hideUncommentedPrs.integerValue = [Settings shared].shouldHideUncommentedRequests;
	self.autoParticipateWhenMentioned.integerValue = [Settings shared].autoParticipateInMentions;
	self.hideAvatars.integerValue = [Settings shared].hideAvatars;
	self.dontKeepPrsMergedByMe.integerValue = [Settings shared].dontKeepPrsMergedByMe;
	self.showAllComments.integerValue = [Settings shared].showCommentsEverywhere;
	self.sortingOrder.integerValue = [Settings shared].sortDescending;
	self.showCreationDates.integerValue = [Settings shared].showCreatedInsteadOfUpdated;
	self.groupByRepo.integerValue = [Settings shared].groupByRepo;
	self.moveAssignedPrsToMySection.integerValue = [Settings shared].moveAssignedPrsToMySection;
	self.showStatusItems.integerValue = [Settings shared].showStatusItems;
	self.makeStatusItemsSelectable.integerValue = [Settings shared].makeStatusItemsSelectable;
	self.markUnmergeableOnUserSectionsOnly.integerValue = [Settings shared].markUnmergeableOnUserSectionsOnly;
	self.countOnlyListedPrs.integerValue = [Settings shared].countOnlyListedPrs;
	self.hideNewRepositories.integerValue = [Settings shared].hideNewRepositories;
	self.openPrAtFirstUnreadComment.integerValue = [Settings shared].openPrAtFirstUnreadComment;

	self.hotkeyEnable.integerValue = [Settings shared].hotkeyEnable;
	self.hotkeyControlModifier.integerValue = [Settings shared].hotkeyControlModifier;
	self.hotkeyCommandModifier.integerValue = [Settings shared].hotkeyCommandModifier;
	self.hotkeyOptionModifier.integerValue = [Settings shared].hotkeyOptionModifier;
	self.hotkeyShiftModifier.integerValue = [Settings shared].hotkeyShiftModifier;
	[self enableHotkeySegments];
	[self populateHotkeyLetterMenu];

    [self refreshUpdatePreferences];

	[self updateStatusItemsOptions];

	[self.hotkeyEnable setEnabled:(AXIsProcessTrustedWithOptions != NULL)];

	[self.repoCheckStepper setFloatValue:[Settings shared].newRepoCheckPeriod];
	[self newRepoCheckChanged:nil];

	[self.refreshDurationStepper setFloatValue:[Settings shared].refreshPeriod];
	[self refreshDurationChanged:nil];

	[self.preferencesWindow setLevel:NSFloatingWindowLevel];
	[self.preferencesWindow makeKeyAndOrderFront:self];
}

- (void)colorButton:(NSButton *)button withColor:(NSColor *)color
{
	NSMutableAttributedString *title = [button.attributedTitle mutableCopy];
	[title addAttribute:NSForegroundColorAttributeName
				  value:color
				  range:NSMakeRange(0, title.length)];
	button.attributedTitle = title;
}

- (void)enableHotkeySegments
{
	Settings *s = [Settings shared];
	if(s.hotkeyEnable)
	{
		if(s.hotkeyCommandModifier)
			[self colorButton:self.hotkeyCommandModifier withColor:[NSColor controlTextColor]];
		else
			[self colorButton:self.hotkeyCommandModifier withColor:[NSColor disabledControlTextColor]];

		if(s.hotkeyControlModifier)
			[self colorButton:self.hotkeyControlModifier withColor:[NSColor controlTextColor]];
		else
			[self colorButton:self.hotkeyControlModifier withColor:[NSColor disabledControlTextColor]];

		if(s.hotkeyOptionModifier)
			[self colorButton:self.hotkeyOptionModifier withColor:[NSColor controlTextColor]];
		else
			[self colorButton:self.hotkeyOptionModifier withColor:[NSColor disabledControlTextColor]];

		if(s.hotkeyShiftModifier)
			[self colorButton:self.hotkeyShiftModifier withColor:[NSColor controlTextColor]];
		else
			[self colorButton:self.hotkeyShiftModifier withColor:[NSColor disabledControlTextColor]];
	}
	[self.hotKeyContainer setHidden:!s.hotkeyEnable];
	[self.hotKeyHelp setHidden:s.hotkeyEnable];
}

- (void)populateHotkeyLetterMenu
{
	NSMutableArray *titles = [NSMutableArray array];
	for(char l='A';l<='Z';l++)
		[titles addObject:[NSString stringWithFormat:@"%c",l]];
	[self.hotkeyLetter addItemsWithTitles:titles];
	[self.hotkeyLetter selectItemWithTitle:[Settings shared].hotkeyLetter];
}

- (IBAction)showAllRepositoriesSelected:(NSButton *)sender
{
	for(Repo *r in [self getFilteredRepos]) { r.hidden = @NO; r.dirty = @YES; }
	self.preferencesDirty = YES;
	[self.projectsTable reloadData];
}

- (IBAction)hideAllRepositoriesSelected:(NSButton *)sender
{
	for(Repo *r in [self getFilteredRepos]) { r.hidden = @YES; r.dirty = @NO; }
	self.preferencesDirty = YES;
	[self.projectsTable reloadData];
}

- (IBAction)enableHotkeySelected:(NSButton *)sender
{
	[Settings shared].hotkeyEnable = self.hotkeyEnable.integerValue;
	[Settings shared].hotkeyLetter = self.hotkeyLetter.titleOfSelectedItem;
	[Settings shared].hotkeyControlModifier = self.hotkeyControlModifier.integerValue;
	[Settings shared].hotkeyCommandModifier = self.hotkeyCommandModifier.integerValue;
	[Settings shared].hotkeyOptionModifier = self.hotkeyOptionModifier.integerValue;
	[Settings shared].hotkeyShiftModifier = self.hotkeyShiftModifier.integerValue;
	[self enableHotkeySegments];
	[self addHotKeySupport];
}

- (IBAction)createTokenSelected:(NSButton *)sender
{
	NSString *address = [NSString stringWithFormat:@"https://%@/settings/tokens/new",[Settings shared].apiFrontEnd];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
}

- (IBAction)viewExistingTokensSelected:(NSButton *)sender
{
	NSString *address = [NSString stringWithFormat:@"https://%@/settings/applications",[Settings shared].apiFrontEnd];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
}

- (IBAction)viewWatchlistSelected:(NSButton *)sender
{
	NSString *address = [NSString stringWithFormat:@"https://%@/watching",[Settings shared].apiFrontEnd];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
}

- (IBAction)prMergePolicySelected:(NSPopUpButton *)sender
{
	[Settings shared].mergeHandlingPolicy = sender.indexOfSelectedItem;
}

- (IBAction)prClosePolicySelected:(NSPopUpButton *)sender
{
	[Settings shared].closeHandlingPolicy = sender.indexOfSelectedItem;
}

/////////////////////////////////// Repo table

- (NSArray *)getFilteredRepos
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];
	f.returnsObjectsAsFaults = NO;

	NSString *filter = self.repoFilter.stringValue;
	if(filter.length)
		f.predicate = [NSPredicate predicateWithFormat:@"fullName contains [cd] %@",filter];

	f.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"fork" ascending:YES],
						  [NSSortDescriptor sortDescriptorWithKey:@"fullName" ascending:YES]];

	return [self.dataManager.managedObjectContext executeFetchRequest:f error:nil];
}

- (NSUInteger)countParentRepos
{
	NSFetchRequest *f = [NSFetchRequest fetchRequestWithEntityName:@"Repo"];

	NSString *filter = self.repoFilter.stringValue;
	if(filter.length)
		f.predicate = [NSPredicate predicateWithFormat:@"fork == NO and fullName contains [cd] %@",filter];
	else
		f.predicate = [NSPredicate predicateWithFormat:@"fork == NO"];

	return [self.dataManager.managedObjectContext countForFetchRequest:f error:nil];
}

- (Repo *)repoForRow:(NSUInteger)row
{
	if(row>[self countParentRepos]) row--;
	return [self getFilteredRepos][row-1];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSButtonCell *cell = [tableColumn dataCellForRow:row];
	if([tableColumn.identifier isEqualToString:@"hide"])
	{
		if([self tableView:tableView isGroupRow:row])
		{
			[cell setImagePosition:NSNoImage];
			cell.state = NSMixedState;
			[cell setEnabled:NO];
		}
		else
		{
			[cell setImagePosition:NSImageOnly];

			Repo *r = [self repoForRow:row];
			if(r.hidden.boolValue)
				cell.state = NSOnState;
			else
				cell.state = NSOffState;
			[cell setEnabled:YES];
		}
	}
	else
	{
		if([self tableView:tableView isGroupRow:row])
		{
			if(row==0)
				cell.title = @"Parent Repositories";
			else
				cell.title = @"Forked Repositories";

			cell.state = NSMixedState;
			[cell setEnabled:NO];
		}
		else
		{
			Repo *r = [self repoForRow:row];
			cell.title = r.fullName;
			[cell setEnabled:YES];
		}
	}
	return cell;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
	return (row == 0 || row == [self countParentRepos]+1);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [self getFilteredRepos].count+2;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if(![self tableView:tableView isGroupRow:row])
	{
		Repo *r = [self repoForRow:row];
		BOOL hideNow = [object boolValue];
		r.hidden = @(hideNow);
		r.dirty = @(!hideNow);
	}
	[self.dataManager saveDB];
	self.preferencesDirty = YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	[self.dataManager saveDB];
    return NSTerminateNow;
}

- (void)scrollToTop
{
	NSScrollView *scrollView = self.mainMenu.scrollView;
	[scrollView.documentView scrollPoint:CGPointMake(0, [scrollView.documentView frame].size.height-scrollView.contentView.bounds.size.height)];
	[self.mainMenu layout];
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
	if([notification object]==self.mainMenu)
	{
		if(self.ignoreNextFocusLoss)
		{
			self.ignoreNextFocusLoss = NO;
		}
		else
		{
			[self scrollToTop];
			for(PRItemView *v in currentPRItems)
				v.focused = NO;
		}
		[self.mainMenuFilter becomeFirstResponder];
	}
}

- (void)windowDidResignKey:(NSNotification *)notification
{
	if(self.ignoreNextFocusLoss)
	{
		[self displayMenu];
		return;
	}
	if(!self.opening)
	{
		if([notification object]==self.mainMenu)
		{
			[self closeMenu];
		}
	}
}

- (void)windowWillClose:(NSNotification *)notification
{
	if([notification object]==self.preferencesWindow)
	{
		[self controlTextDidChange:nil];
		if([Settings shared].authToken.length && self.preferencesDirty)
		{
			[self startRefresh];
		}
		else
		{
			if(!self.refreshTimer && [Settings shared].refreshPeriod>0.0)
			{
				[self startRefreshIfItIsDue];
			}
		}
        [self setUpdateCheckParameters];
	}
	else if([notification object]==self.apiSettings)
	{
		[self commitApiInfo];
	}
}

- (void)setUpdateCheckParameters
{
    SUUpdater *s = [SUUpdater sharedUpdater];
    BOOL autoCheck = [Settings shared].checkForUpdatesAutomatically;
	s.automaticallyChecksForUpdates = autoCheck;
    if(autoCheck)
    {
        [s setUpdateCheckInterval:3600.0*[Settings shared].checkForUpdatesInterval];
    }
    DLog(@"Check for updates set to %d every %f seconds",s.automaticallyChecksForUpdates,s.updateCheckInterval);
}

- (void)commitApiInfo
{
	NSString *frontEnd = [self.apiFrontEnd stringValue];
	NSString *backEnd = [self.apiBackEnd stringValue];
	NSString *path = [self.apiPath stringValue];

	NSCharacterSet *cs = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	frontEnd = [frontEnd stringByTrimmingCharactersInSet:cs];
	backEnd = [backEnd stringByTrimmingCharactersInSet:cs];
	path = [path stringByTrimmingCharactersInSet:cs];

	if(frontEnd.length==0) frontEnd = nil;
	if(backEnd.length==0) backEnd = nil;
	if(path.length==0) path = nil;

	[Settings shared].apiFrontEnd = frontEnd;
	[Settings shared].apiBackEnd = backEnd;
	[Settings shared].apiPath = path;

	[AppDelegate shared].preferencesDirty = YES;
}

- (void)networkStateChanged
{
	if([self.api.reachability currentReachabilityStatus]!=NotReachable)
	{
		DLog(@"Network is back");
		[self startRefreshIfItIsDue];
	}
}

- (void)startRefreshIfItIsDue
{
	if(self.lastSuccessfulRefresh)
	{
		NSTimeInterval howLongAgo = [[NSDate date] timeIntervalSinceDate:self.lastSuccessfulRefresh];
		if(howLongAgo>[Settings shared].refreshPeriod)
		{
			[self startRefresh];
		}
		else
		{
			NSTimeInterval howLongUntilNextSync = [Settings shared].refreshPeriod-howLongAgo;
			DLog(@"No need to refresh yet, will refresh in %f",howLongUntilNextSync);
			self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:howLongUntilNextSync
																 target:self
															   selector:@selector(refreshTimerDone)
															   userInfo:nil
																repeats:NO];
		}
	}
	else
	{
		[self startRefresh];
	}
}

- (IBAction)refreshNowSelected:(NSMenuItem *)sender
{
	if([Repo countVisibleReposInMoc:self.dataManager.managedObjectContext]==0)
	{
		[self preferencesSelected:nil];
		return;
	}
	[self startRefresh];
}

- (void)checkApiUsage
{
	if(self.api.requestsLimit>0)
	{
		if(self.api.requestsRemaining==0)
		{
			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:@"Your API request usage is over the limit!"];
			[alert setInformativeText:[NSString stringWithFormat:@"Your request cannot be completed until GitHub resets your hourly API allowance at %@.\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from the bottom of the preferences pane at any time.",self.api.resetDate]];
			[alert addButtonWithTitle:@"OK"];
			[alert runModal];
			return;
		}
		else if((self.api.requestsRemaining/self.api.requestsLimit)<LOW_API_WARNING)
		{
			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:@"Your API request usage is close to full"];
			[alert setInformativeText:[NSString stringWithFormat:@"Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github on %@.\n\nYou can check your API usage from the bottom of the preferences pane.",self.api.resetDate]];
			[alert addButtonWithTitle:@"OK"];
			[alert runModal];
		}
	}
}

- (void)prepareForRefresh
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	[self.refreshButton setEnabled:NO];
	[self.projectsTable setEnabled:NO];
	[self.githubTokenHolder setEnabled:NO];
	[self.activityDisplay startAnimation:nil];
	self.statusItemView.grayOut = YES;

	[self.api expireOldImageCacheEntries];
	[self.dataManager postMigrationTasks];

	self.isRefreshing = YES;

	for(NSView *v in [self.mainMenu.scrollView.documentView subviews])
		if([v isKindOfClass:[EmptyView class]])
			[self updateMenu];

	if([Settings shared].localUser)
		self.refreshNow.title = [NSString stringWithFormat:@" Refreshing %@...",[Settings shared].localUser];
	else
		self.refreshNow.title = @" Refreshing...";

	DLog(@"Starting refresh");
}

- (void)completeRefresh
{
	self.isRefreshing = NO;
	[self.refreshButton setEnabled:YES];
	[self.projectsTable setEnabled:YES];
	[self.githubTokenHolder setEnabled:YES];
	[self.activityDisplay stopAnimation:nil];
	[self.dataManager saveDB];
	[self.projectsTable reloadData];
	[self updateMenu];
	[self checkApiUsage];
	[self.dataManager sendNotifications];
	[self.dataManager saveDB];

	DLog(@"Refresh done");
}

- (void)startRefresh
{
	if(self.isRefreshing) return;

	[self prepareForRefresh];

	id oldTarget = self.refreshNow.target;
	SEL oldAction = self.refreshNow.action;
	[self.refreshNow setAction:nil];
	[self.refreshNow setTarget:nil];

	[self.api fetchPullRequestsForActiveReposAndCallback:^(BOOL success) {
		self.refreshNow.target = oldTarget;
		self.refreshNow.action = oldAction;
		self.lastUpdateFailed = !success;
		if(success)
		{
			self.lastSuccessfulRefresh = [NSDate date];
			self.preferencesDirty = NO;
		}
		[self completeRefresh];
		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:[Settings shared].refreshPeriod
															 target:self
														   selector:@selector(refreshTimerDone)
														   userInfo:nil
															repeats:NO];
	}];
}


- (IBAction)refreshDurationChanged:(NSStepper *)sender
{
	[Settings shared].refreshPeriod = self.refreshDurationStepper.floatValue;
	[self.refreshDurationLabel setStringValue:[NSString stringWithFormat:@"Refresh PRs every %ld seconds",(long)self.refreshDurationStepper.integerValue]];
}

- (IBAction)newRepoCheckChanged:(NSStepper *)sender
{
	[Settings shared].newRepoCheckPeriod = self.repoCheckStepper.floatValue;
	[self.repoCheckLabel setStringValue:[NSString stringWithFormat:@"Refresh repositories every %ld hours",(long)self.repoCheckStepper.integerValue]];
}

- (void)refreshTimerDone
{
	if([Settings shared].localUserId && [Settings shared].authToken.length)
	{
		[self startRefresh];
	}
}

- (void)updateMenu
{
	NSManagedObjectContext *moc = self.dataManager.managedObjectContext;
	NSFetchRequest *f = [PullRequest requestForPullRequestsWithFilter:self.mainMenuFilter.stringValue];
	NSArray *pullRequests = [moc executeFetchRequest:f error:nil];

	[self buildPrMenuItemsFromList:pullRequests];

	NSString *countString;
	NSDictionary *attributes;
	if(self.lastUpdateFailed && (![Settings shared].dontReportRefreshFailures))
	{
		countString = @"X";
		attributes = @{
					   NSFontAttributeName: [NSFont boldSystemFontOfSize:10.0],
					   NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0),
					   };
	}
	else
	{
		NSUInteger count;

		if([Settings shared].countOnlyListedPrs)
			count = pullRequests.count;
		else
			count = [PullRequest countOpenRequestsInMoc:moc];

		countString = [NSString stringWithFormat:@"%ld",count];

		if([PullRequest badgeCountInMoc:moc]>0)
		{
			attributes = @{ NSFontAttributeName: [NSFont menuBarFontOfSize:10.0],
							NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) };
		}
		else
		{
			attributes = @{ NSFontAttributeName: [NSFont menuBarFontOfSize:10.0],
							NSForegroundColorAttributeName: [COLOR_CLASS blackColor] };
		}
	}

	DLog(@"Updating menu, %@ total PRs",countString);

	CGFloat width = [countString sizeWithAttributes:attributes].width;

	NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
	CGFloat H = statusBar.thickness;
	CGFloat length = H+width+STATUSITEM_PADDING*3;
	if(!self.statusItem) self.statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];

	self.statusItemView = [[StatusItemView alloc] initWithFrame:CGRectMake(0, 0, length, H)
														  label:countString
													 attributes:attributes
													   delegate:self];
	self.statusItemView.highlighted = [self.mainMenu isVisible];
	self.statusItemView.grayOut = self.isRefreshing;
	self.statusItem.view = self.statusItemView;

	[self sizeMenuAndShow:NO];
}

//////////////// launch at startup from: http://cocoatutorial.grapewave.com/tag/lssharedfilelistitemresolve/

- (void) addAppAsLoginItem
{
	// Create a reference to the shared file list.
	// We are adding it to the current user only.
	// If we want to add it all users, use
	// kLSSharedFileListGlobalLoginItems instead of kLSSharedFileListSessionLoginItems
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if(loginItems)
	{
		NSString * appPath = [[NSBundle mainBundle] bundlePath];
		CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
		LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
																	 kLSSharedFileListItemLast, NULL, NULL,
																	 url, NULL, NULL);
		if (item) CFRelease(item);
		CFRelease(loginItems);
	}
}

- (BOOL)isAppLoginItem
{
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if(loginItems)
	{
		UInt32 seedValue;
		NSArray  *loginItemsArray = (__bridge_transfer NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
		CFRelease(loginItems);

		for(int i = 0 ; i< loginItemsArray.count; i++)
		{
			LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)loginItemsArray[i];

			NSString * appPath = [[NSBundle mainBundle] bundlePath];
			CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
			if(LSSharedFileListItemResolve(itemRef, 0, &url, NULL) == noErr)
			{
				NSURL *uu = (__bridge_transfer NSURL*)url;
				if ([[uu path] compare:appPath] == NSOrderedSame)
				{
					return YES;
				}
			}
		}
	}
	return NO;
}

- (void) deleteAppFromLoginItem
{
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if(loginItems)
	{
		UInt32 seedValue;
		NSArray  *loginItemsArray = (__bridge_transfer NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
		CFRelease(loginItems);

		for(int i = 0 ; i< [loginItemsArray count]; i++)
		{
			LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];

			NSString * appPath = [[NSBundle mainBundle] bundlePath];
			CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];

			if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr)
			{
				NSURL *uu = (__bridge_transfer NSURL*)url;
				if ([[uu path] compare:appPath] == NSOrderedSame)
				{
					LSSharedFileListItemRemove(loginItems,itemRef);
				}
			}
		}
	}
}

- (void)updateStatusTermPreferenceControls
{
	NSInteger mode = [Settings shared].statusFilteringMode;
	[self.statusTermMenu selectItemAtIndex:mode];
	if(mode!=0)
	{
		[self.statusTermsField setEnabled:YES];
		self.statusTermsField.alphaValue = 1.0;
	}
	else
	{
		[self.statusTermsField setEnabled:NO];
		self.statusTermsField.alphaValue = 0.8;
	}
	self.statusTermsField.objectValue = [Settings shared].statusFilteringTerms;
}

- (IBAction)statusFilterMenuChanged:(NSPopUpButton *)sender
{
	[Settings shared].statusFilteringMode = sender.indexOfSelectedItem;
	[Settings shared].statusFilteringTerms = self.statusTermsField.objectValue;
	[self updateStatusTermPreferenceControls];
}

- (IBAction)apiServerSelected:(NSButton *)sender
{
	[self.apiFrontEnd setStringValue:[Settings shared].apiFrontEnd];
	[self.apiBackEnd setStringValue:[Settings shared].apiBackEnd];
	[self.apiPath setStringValue:[Settings shared].apiPath];

	[self.apiSettings setLevel:NSFloatingWindowLevel];
	[self.apiSettings makeKeyAndOrderFront:self];
}

- (IBAction)testApiServerSelected:(NSButton *)sender
{
	[self commitApiInfo];
	[sender setEnabled:NO];

	[self.api testApiAndCallback:^(NSError *error) {
		NSAlert *alert = [[NSAlert alloc] init];
		if(error)
		{
			[alert setMessageText:[NSString stringWithFormat:@"The test failed for https://%@/%@",[Settings shared].apiBackEnd,[Settings shared].apiPath]];
			[alert setInformativeText:error.localizedDescription];
		}
		else
		{
			[alert setMessageText:@"The API server is OK!"];
		}
		[alert addButtonWithTitle:@"OK"];
		[alert runModal];
		[sender setEnabled:YES];
	}];
}

- (IBAction)apiRestoreDefaultsSelected:(NSButton *)sender
{
	[Settings shared].apiFrontEnd = nil;
	[Settings shared].apiBackEnd = nil;
	[Settings shared].apiPath = nil;

	[self.apiFrontEnd setStringValue:[Settings shared].apiFrontEnd];
	[self.apiBackEnd setStringValue:[Settings shared].apiBackEnd];
	[self.apiPath setStringValue:[Settings shared].apiPath];
}

/////////////////////// keyboard shortcuts

- (void)addHotKeySupport
{
	if(AXIsProcessTrustedWithOptions != NULL)
	{
		if([Settings shared].hotkeyEnable)
		{
			if(!globalKeyMonitor)
			{
				BOOL alreadyTrusted = AXIsProcessTrusted();
				NSDictionary *options = @{ (__bridge id)kAXTrustedCheckOptionPrompt: @(!alreadyTrusted)};
				if(AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options))
				{
					globalKeyMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSKeyDownMask handler:^void(NSEvent* incomingEvent) {
						[self checkForHotkey:incomingEvent];
					}];
				}
			}
		}
		else
		{
			if(globalKeyMonitor)
			{
				[NSEvent removeMonitor:globalKeyMonitor];
				globalKeyMonitor = nil;
			}
		}
	}

	if(localKeyMonitor) return;

	localKeyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyDownMask handler:^NSEvent *(NSEvent *incomingEvent) {

		if([self checkForHotkey:incomingEvent]) return nil;

		switch(incomingEvent.keyCode)
		{
			case 125: // down
			{
				PRItemView *v = [self focusedItemView];
				NSInteger i = -1;
				if(v) i = [currentPRItems indexOfObject:v];
				if(i<(NSInteger)currentPRItems.count-1)
				{
					i++;
					v.focused = NO;
					v = currentPRItems[i];
					v.focused = YES;
					[self.mainMenu scrollToView:v];
				}
				return nil;
			}
			case 126: // up
			{
				PRItemView *v = [self focusedItemView];
				NSInteger i = currentPRItems.count;
				if(v) i = [currentPRItems indexOfObject:v];
				if(i>0)
				{
					i--;
					v.focused = NO;
					v = currentPRItems[i];
					v.focused = YES;
					[self.mainMenu scrollToView:v];
				}
				return nil;
			}
			case 36: // enter
			{
				PRItemView *v = [self focusedItemView];
				BOOL isAlternative = ((incomingEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask);
				if(v) [self prItemSelected:v alternativeSelect:isAlternative];
				return nil;
			}
		}

		return incomingEvent;
	}];
}

- (NSString *)focusedItemUrl
{
	PRItemView *v = [self focusedItemView];
	v.focused = NO;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		v.focused = YES;
	});
	PullRequest *r = [PullRequest itemOfType:@"PullRequest" serverId:v.userInfo moc:self.dataManager.managedObjectContext];
	return r.webUrl;
}

- (void)prItemFocused:(NSNotification *)focusedNotification
{
	BOOL state = [focusedNotification.userInfo[PR_ITEM_FOCUSED_STATE_KEY] boolValue];
	if(state)
	{
		PRItemView *itemView = focusedNotification.object;
		for(PRItemView *v in currentPRItems)
			if(itemView!=v)
				v.focused = NO;
	}
}

- (PRItemView *)focusedItemView
{
	for(PRItemView *v in currentPRItems)
		if(v.focused)
			return v;

	return nil;
}

- (BOOL)checkForHotkey:(NSEvent *)incomingEvent
{
	if(AXIsProcessTrustedWithOptions == NULL) return NO;

	NSInteger check = 0;

	if([Settings shared].hotkeyCommandModifier)
	{
		if((incomingEvent.modifierFlags & NSCommandKeyMask) == NSCommandKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSCommandKeyMask) == NSCommandKeyMask) check--; else check++;
	}

	if([Settings shared].hotkeyControlModifier)
	{
		if((incomingEvent.modifierFlags & NSControlKeyMask) == NSControlKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSControlKeyMask) == NSControlKeyMask) check--; else check++;
	}

	if([Settings shared].hotkeyOptionModifier)
	{
		if((incomingEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask) check--; else check++;
	}

	if([Settings shared].hotkeyShiftModifier)
	{
		if((incomingEvent.modifierFlags & NSShiftKeyMask) == NSShiftKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSShiftKeyMask) == NSShiftKeyMask) check--; else check++;
	}

	if(check==4)
	{
		NSDictionary *codeLookup = @{@"A": @(0),
									 @"B": @(11),
									 @"C": @(8),
									 @"D": @(2),
									 @"E": @(14),
									 @"F": @(3),
									 @"G": @(5),
									 @"H": @(4),
									 @"I": @(34),
									 @"J": @(38),
									 @"K": @(40),
									 @"L": @(37),
									 @"M": @(46),
									 @"N": @(45),
									 @"O": @(31),
									 @"P": @(35),
									 @"Q": @(12),
									 @"R": @(15),
									 @"S": @(1),
									 @"T": @(17),
									 @"U": @(32),
									 @"V": @(9),
									 @"W": @(13),
									 @"X": @(7),
									 @"Y": @(16),
									 @"Z": @(6) };

		NSNumber *n = codeLookup[[Settings shared].hotkeyLetter];
		if(incomingEvent.keyCode==n.integerValue)
		{
			[self statusItemTapped:self.statusItemView];
			return YES;
		}
	}
	return NO;
}

////////////// scrollbars

- (void)updateScrollBarWidth
{
	if(self.mainMenu.scrollView.verticalScroller.scrollerStyle==NSScrollerStyleLegacy)
		self.scrollBarWidth = self.mainMenu.scrollView.verticalScroller.frame.size.width;
	else
		self.scrollBarWidth = 0;
	[self updateMenu];
}

@end
