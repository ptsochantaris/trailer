
AppDelegate *app;

@interface AppDelegate ()
{
	// Keyboard support
	id globalKeyMonitor, localKeyMonitor;
	NSMutableArray *currentPRItems;
}
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	app = self;

	// Useful snippet for resetting prefs when testing
	//NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
	//[[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];

	self.currentAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];

	self.mainMenu.backgroundColor = [COLOR_CLASS whiteColor];

	self.filterTimer = [[HTPopTimer alloc] initWithTimeInterval:0.2 target:self selector:@selector(filterTimerPopped)];

	[NSThread setThreadPriority:0.0];

	settings = [[Settings alloc] init];
	self.dataManager = [[DataManager alloc] init];
	self.api = [[API alloc] init];

	[self setupSortMethodMenu];

	// ONLY FOR DEBUG!
	/*
	#warning COMMENT THIS
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

	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

	NSString *currentAppVersion = [@"Version " stringByAppendingString:self.currentAppVersion];
	[self.versionNumber setStringValue:currentAppVersion];
	[self.aboutVersion setStringValue:currentAppVersion];

	if([ApiServer someServersHaveAuthTokensInMoc:self.dataManager.managedObjectContext])
	{
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
	if(!s.updateInProgress && settings.checkForUpdatesAutomatically)
	{
		[s checkForUpdatesInBackground];
	}
}

- (void)setupSortMethodMenu
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Sorting"];
	if(settings.sortDescending)
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
	[self.sortModeSelect selectItemAtIndex:settings.sortMethod];
}

- (IBAction)dontConfirmRemoveAllMergedSelected:(NSButton *)sender
{
	BOOL dontConfirm = (sender.integerValue==1);
    settings.dontAskBeforeWipingMerged = dontConfirm;
}

- (IBAction)hideAllPrsSection:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	settings.hideAllPrsSection = setting;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)markUnmergeableOnUserSectionsOnlySelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	settings.markUnmergeableOnUserSectionsOnly = setting;
	[self updateMenu];
}

- (IBAction)displayRepositoryNameSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	settings.showReposInName = setting;
	[self updateMenu];
}

- (IBAction)logActivityToConsoleSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	settings.logActivityToConsole = setting;

	if(settings.logActivityToConsole)
	{
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"Warning"];
		[alert setInformativeText:@"Logging is a feature meant for error reporting, having it constantly enabled will cause this app to be less responsive and use more power"];
		[alert addButtonWithTitle:@"OK"];
		[alert runModal];
	}
}

- (IBAction)includeRepositoriesInfilterSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	settings.includeReposInFilter = setting;
}

- (IBAction)dontConfirmRemoveAllClosedSelected:(NSButton *)sender
{
	BOOL dontConfirm = (sender.integerValue==1);
    settings.dontAskBeforeWipingClosed = dontConfirm;
}

- (IBAction)autoParticipateOnMentionSelected:(NSButton *)sender
{
	BOOL autoParticipate = (sender.integerValue==1);
	settings.autoParticipateInMentions = autoParticipate;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)dontKeepMyPrsSelected:(NSButton *)sender
{
	BOOL dontKeep = (sender.integerValue==1);
	settings.dontKeepPrsMergedByMe = dontKeep;
}

- (IBAction)hideAvatarsSelected:(NSButton *)sender
{
	BOOL hide = (sender.integerValue==1);
	settings.hideAvatars = hide;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)hidePrsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	settings.shouldHideUncommentedRequests = show;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)showAllCommentsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	settings.showCommentsEverywhere = show;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)sortOrderSelected:(NSButton *)sender
{
	BOOL descending = (sender.integerValue==1);
	settings.sortDescending = descending;
	[self setupSortMethodMenu];
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)countOnlyListedPrsSelected:(NSButton *)sender
{
	settings.countOnlyListedPrs = (sender.integerValue==1);
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)hideNewRespositoriesSelected:(NSButton *)sender
{
	settings.hideNewRepositories = (sender.integerValue==1);
}

- (IBAction)openPrAtFirstUnreadCommentSelected:(NSButton *)sender
{
	settings.openPrAtFirstUnreadComment = (sender.integerValue==1);
}

- (IBAction)sortMethodChanged:(id)sender
{
	settings.sortMethod = self.sortModeSelect.indexOfSelectedItem;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)showStatusItemsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	settings.showStatusItems = show;
	[self updateMenu];

	[self updateStatusItemsOptions];

	self.api.successfulRefreshesSinceLastStatusCheck = 0;
	self.preferencesDirty = YES;
}

- (void)updateStatusItemsOptions
{
	BOOL enable = settings.showStatusItems;
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

	self.statusItemRefreshCounter.integerValue = settings.statusItemRefreshInterval;
	NSInteger count = settings.statusItemRefreshInterval;
	if(count>1)
		self.statusItemRescanLabel.stringValue = [NSString stringWithFormat:@"...and re-scan once every %ld refreshes",(long)count];
	else
		self.statusItemRescanLabel.stringValue = [NSString stringWithFormat:@"...and re-scan on every refresh"];
}

- (IBAction)statusItemRefreshCountChanged:(NSStepper *)sender
{
	settings.statusItemRefreshInterval = self.statusItemRefreshCounter.integerValue;
	[self updateStatusItemsOptions];
}

- (IBAction)makeStatusItemsSelectableSelected:(NSButton *)sender
{
	BOOL yes = (sender.integerValue==1);
	settings.makeStatusItemsSelectable = yes;
	[self updateMenu];
}

- (IBAction)showCreationSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	settings.showCreatedInsteadOfUpdated = show;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)groupbyRepoSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	settings.groupByRepo = setting;
	[self updateMenu];
}

- (IBAction)moveAssignedPrsToMySectionSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	settings.moveAssignedPrsToMySection = setting;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)checkForUpdatesAutomaticallySelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
    settings.checkForUpdatesAutomatically = setting;
    [self refreshUpdatePreferences];
}

- (void)refreshUpdatePreferences
{
    BOOL setting = settings.checkForUpdatesAutomatically;
    NSInteger interval = settings.checkForUpdatesInterval;

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
    settings.checkForUpdatesInterval = sender.integerValue;
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
				NSManagedObjectContext *moc = app.dataManager.managedObjectContext;

				NSManagedObjectID *itemId = [app.dataManager idForUriPath:notification.userInfo[PULL_REQUEST_ID_KEY]];

				PullRequest *pullRequest = nil;
				if(itemId) // it's a pull request
				{
					pullRequest = (PullRequest *)[moc existingObjectWithID:itemId error:nil];
					urlToOpen = pullRequest.webUrl;
				}
				else // it's a comment
				{
					itemId = [app.dataManager idForUriPath:notification.userInfo[COMMENT_ID_KEY]];
					PRComment *c = (PRComment *)[moc existingObjectWithID:itemId error:nil];
					urlToOpen = c.webUrl;
					pullRequest = c.pullRequest;
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
			PRComment *c = item;
			notification.title = [NSString stringWithFormat:@"@%@ mentioned you:",c.userName];
			notification.informativeText = c.body;
			notification.subtitle = c.pullRequest.title;
			break;
		}
		case kNewComment:
		{
			PRComment *c = item;
			notification.title = [NSString stringWithFormat:@"@%@ commented:", c.userName];
			notification.informativeText = c.body;
			notification.subtitle = c.pullRequest.title;
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
		case kNewPrAssigned:
		{
			notification.title = @"PR Assigned";
			notification.subtitle = [item title];
			break;
		}
	}

	if((type==kNewComment || type==kNewMention) &&
	   !settings.hideAvatars &&
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

	PullRequest *r = item.associatedPullRequest;
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
			self.refreshNow.title = [@" Refresh" stringByAppendingFormat:@" - %@",[self.api lastUpdateDescription]];
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
		if(settings.dontAskBeforeWipingMerged)
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
                    settings.dontAskBeforeWipingMerged = YES;
                }
            }
		}
	}
	else if([header.title isEqualToString:kPullRequestSectionNames[kPullRequestSectionClosed]])
	{
		if(settings.dontAskBeforeWipingClosed)
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
                    settings.dontAskBeforeWipingClosed = YES;
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
	PullRequest *r = item.associatedPullRequest;
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
		PRItemView *view = [[PRItemView alloc] initWithPullRequest:r delegate:self];
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

- (void)startRateLimitHandling
{
	[[NSNotificationCenter defaultCenter] addObserver:self.serverList selector:@selector(reloadData) name:API_USAGE_UPDATE object:nil];
	[self.api updateLimitsFromServer];
}

- (IBAction)refreshReposSelected:(NSButton *)sender
{
	[self prepareForRefresh];
	[self controlTextDidChange:nil];

	NSManagedObjectContext *tempContext = [self.dataManager tempContext];
	[self.api fetchRepositoriesToMoc:tempContext andCallback:^{
		if([ApiServer shouldReportRefreshFailureInMoc:tempContext])
		{
			NSMutableArray *errorServers = [NSMutableArray new];
			for(ApiServer *apiServer in [ApiServer allApiServersInMoc:tempContext])
			{
				if(apiServer.goodToGo && !apiServer.lastSyncSucceeded.boolValue)
				{
					[errorServers addObject:apiServer.label];
				}
			}

			NSString *serverNames = [errorServers componentsJoinedByString:@", "];
			NSString *message = [NSString stringWithFormat:@"Could not refresh repository list from %@, please ensure that the tokens you are using are valid",serverNames];

			NSAlert *alert = [[NSAlert alloc] init];
			[alert setMessageText:@"Error"];
			[alert setInformativeText:message];
			[alert addButtonWithTitle:@"OK"];
			[alert runModal];
		}
		else
		{
			[tempContext save:nil];
		}
		[self completeRefresh];
	}];
}

- (ApiServer *)selectedServer
{
	NSInteger selected = self.serverList.selectedRow;
	if(selected>=0)
	{
		NSArray *allApiServers = [ApiServer allApiServersInMoc:self.dataManager.managedObjectContext];
		return allApiServers[selected];
	}
	return nil;
}

- (IBAction)deleteSelectedServerSelected:(NSButton *)sender
{
	ApiServer *selectedServer = [self selectedServer];
	NSInteger index = [[ApiServer allApiServersInMoc:self.dataManager.managedObjectContext] indexOfObject:selectedServer];
	[self.dataManager.managedObjectContext deleteObject:selectedServer];
	[self.serverList reloadData];
	[self.serverList selectRowIndexes:[NSIndexSet indexSetWithIndex:MIN(index,self.serverList.numberOfRows-1)]
				 byExtendingSelection:NO];
	[self fillServerApiFormFromSelectedServer];
	[self updateMenu];
	[self.dataManager saveDB];
}


- (IBAction)apiServerReportErrorSelected:(NSButton *)sender
{
	ApiServer *apiServer = [self selectedServer];
	apiServer.reportRefreshFailures = @(sender.integerValue!=0);
	[self storeApiFormToSelectedServer];
}

- (void)controlTextDidChange:(NSNotification *)obj
{
	if(obj.object==self.apiServerName)
	{
		ApiServer *apiServer = [self selectedServer];
		apiServer.label = self.apiServerName.stringValue;
		[self storeApiFormToSelectedServer];
	}
	else if(obj.object==self.apiServerApiPath)
	{
		ApiServer *apiServer = [self selectedServer];
		apiServer.apiPath = self.apiServerApiPath.stringValue;
		[self storeApiFormToSelectedServer];
		[apiServer clearAllRelatedInfo];
		[self reset];
	}
	else if(obj.object==self.apiServerWebPath)
	{
		ApiServer *apiServer = [self selectedServer];
		apiServer.webPath = self.apiServerWebPath.stringValue;
		[self storeApiFormToSelectedServer];
	}
	else if(obj.object==self.apiServerAuthToken)
	{
		ApiServer *apiServer = [self selectedServer];
		apiServer.authToken = self.apiServerAuthToken.stringValue;
		[self storeApiFormToSelectedServer];
		[apiServer clearAllRelatedInfo];
		[self reset];
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
		NSArray *existingTokens = settings.statusFilteringTerms;
		NSArray *newTokens = self.statusTermsField.objectValue;
		if(![existingTokens isEqualToArray:newTokens])
		{
			settings.statusFilteringTerms = newTokens;
			[self updateMenu];
		}
	}
	else if(obj.object==self.commentAuthorBlacklist)
	{
		NSArray *existingTokens = settings.commentAuthorBlacklist;
		NSArray *newTokens = self.commentAuthorBlacklist.objectValue;
		if(![existingTokens isEqualToArray:newTokens])
		{
			settings.commentAuthorBlacklist = newTokens;
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
	self.lastRepoCheck = nil;
	[self.projectsTable reloadData];
	self.refreshButton.enabled = [ApiServer someServersHaveAuthTokensInMoc:self.dataManager.managedObjectContext];
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

	[self.serverList selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

	[self.api updateLimitsFromServer];
	[self updateStatusTermPreferenceControls];
	self.commentAuthorBlacklist.objectValue = settings.commentAuthorBlacklist;

	[self.sortModeSelect selectItemAtIndex:settings.sortMethod];
	[self.prMergedPolicy selectItemAtIndex:settings.mergeHandlingPolicy];
	[self.prClosedPolicy selectItemAtIndex:settings.closeHandlingPolicy];

	self.launchAtStartup.integerValue = [self isAppLoginItem];
	self.hideAllPrsSection.integerValue = settings.hideAllPrsSection;
	self.dontConfirmRemoveAllClosed.integerValue = settings.dontAskBeforeWipingClosed;
	self.displayRepositoryNames.integerValue = settings.showReposInName;
	self.includeRepositoriesInFiltering.integerValue = settings.includeReposInFilter;
	self.dontConfirmRemoveAllMerged.integerValue = settings.dontAskBeforeWipingMerged;
	self.hideUncommentedPrs.integerValue = settings.shouldHideUncommentedRequests;
	self.autoParticipateWhenMentioned.integerValue = settings.autoParticipateInMentions;
	self.hideAvatars.integerValue = settings.hideAvatars;
	self.dontKeepPrsMergedByMe.integerValue = settings.dontKeepPrsMergedByMe;
	self.showAllComments.integerValue = settings.showCommentsEverywhere;
	self.sortingOrder.integerValue = settings.sortDescending;
	self.showCreationDates.integerValue = settings.showCreatedInsteadOfUpdated;
	self.groupByRepo.integerValue = settings.groupByRepo;
	self.moveAssignedPrsToMySection.integerValue = settings.moveAssignedPrsToMySection;
	self.showStatusItems.integerValue = settings.showStatusItems;
	self.makeStatusItemsSelectable.integerValue = settings.makeStatusItemsSelectable;
	self.markUnmergeableOnUserSectionsOnly.integerValue = settings.markUnmergeableOnUserSectionsOnly;
	self.countOnlyListedPrs.integerValue = settings.countOnlyListedPrs;
	self.hideNewRepositories.integerValue = settings.hideNewRepositories;
	self.openPrAtFirstUnreadComment.integerValue = settings.openPrAtFirstUnreadComment;
	self.logActivityToConsole.integerValue = settings.logActivityToConsole;

	self.hotkeyEnable.integerValue = settings.hotkeyEnable;
	self.hotkeyControlModifier.integerValue = settings.hotkeyControlModifier;
	self.hotkeyCommandModifier.integerValue = settings.hotkeyCommandModifier;
	self.hotkeyOptionModifier.integerValue = settings.hotkeyOptionModifier;
	self.hotkeyShiftModifier.integerValue = settings.hotkeyShiftModifier;
	[self enableHotkeySegments];
	[self populateHotkeyLetterMenu];

    [self refreshUpdatePreferences];

	[self updateStatusItemsOptions];

	[self.hotkeyEnable setEnabled:(AXIsProcessTrustedWithOptions != NULL)];

	[self.repoCheckStepper setFloatValue:settings.newRepoCheckPeriod];
	[self newRepoCheckChanged:nil];

	[self.refreshDurationStepper setFloatValue:MIN(settings.refreshPeriod,3600)];
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
	Settings *s = settings;
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
	[self.hotkeyLetter selectItemWithTitle:settings.hotkeyLetter];
}

- (IBAction)showAllRepositoriesSelected:(NSButton *)sender
{
	for(Repo *r in [self getFilteredRepos]) { r.hidden = @NO; r.dirty = @YES; r.lastDirtied = [NSDate date]; }
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
	settings.hotkeyEnable = self.hotkeyEnable.integerValue;
	settings.hotkeyLetter = self.hotkeyLetter.titleOfSelectedItem;
	settings.hotkeyControlModifier = self.hotkeyControlModifier.integerValue;
	settings.hotkeyCommandModifier = self.hotkeyCommandModifier.integerValue;
	settings.hotkeyOptionModifier = self.hotkeyOptionModifier.integerValue;
	settings.hotkeyShiftModifier = self.hotkeyShiftModifier.integerValue;
	[self enableHotkeySegments];
	[self addHotKeySupport];
}

- (void)reportNeedFrontEnd
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:[NSString stringWithFormat:@"Please provide a full URL for the web front end of this server first"]];
	[alert addButtonWithTitle:@"OK"];
	[alert runModal];
}

- (IBAction)createTokenSelected:(NSButton *)sender
{
	if([self.apiServerWebPath.stringValue length]==0)
	{
		[self reportNeedFrontEnd];
	}
	else
	{
		NSString *address = [NSString stringWithFormat:@"%@/settings/tokens/new",self.apiServerWebPath.stringValue];
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
	}
}

- (IBAction)viewExistingTokensSelected:(NSButton *)sender
{
	if([self.apiServerWebPath.stringValue length]==0)
	{
		[self reportNeedFrontEnd];
	}
	else
	{
		NSString *address = [NSString stringWithFormat:@"%@/settings/applications",self.apiServerWebPath.stringValue];
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
	}
}

- (IBAction)viewWatchlistSelected:(NSButton *)sender
{
	if([self.apiServerWebPath.stringValue length]==0)
	{
		[self reportNeedFrontEnd];
	}
	else
	{
		NSString *address = [NSString stringWithFormat:@"%@/watching",self.apiServerWebPath.stringValue];
		[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:address]];
	}
}

- (IBAction)prMergePolicySelected:(NSPopUpButton *)sender
{
	settings.mergeHandlingPolicy = sender.indexOfSelectedItem;
}

- (IBAction)prClosePolicySelected:(NSPopUpButton *)sender
{
	settings.closeHandlingPolicy = sender.indexOfSelectedItem;
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

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self fillServerApiFormFromSelectedServer];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSButtonCell *cell = [tableColumn dataCellForRow:row];

	if(tableView==self.projectsTable)
	{
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
				cell.title = r.inaccessible.boolValue ? [r.fullName stringByAppendingString:@" (inaccessible)"] : r.fullName;
				[cell setEnabled:YES];
			}
		}
	}
	else
	{
		NSArray *allServers = [ApiServer allApiServersInMoc:self.dataManager.managedObjectContext];
		ApiServer *apiServer = allServers[row];
		if([tableColumn.identifier isEqualToString:@"server"])
		{
			cell.title = apiServer.label;
		}
		else // api usage
		{
			NSLevelIndicatorCell *c = (NSLevelIndicatorCell*)cell;
			[c setMinValue:0.0];
			[c setMaxValue:apiServer.requestsLimit.doubleValue];
			[c setWarningValue:apiServer.requestsLimit.doubleValue*0.5];
			[c setCriticalValue:apiServer.requestsLimit.doubleValue*0.8];
			[c setDoubleValue:apiServer.requestsLimit.doubleValue-apiServer.requestsRemaining.doubleValue];
		}
	}
	return cell;
}

- (BOOL)tableView:(NSTableView *)tableView isGroupRow:(NSInteger)row
{
	if(tableView==self.projectsTable)
	{
		return (row == 0 || row == [self countParentRepos]+1);
	}
	else
	{
		return NO;
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if(tableView==self.projectsTable)
	{
		return [self getFilteredRepos].count+2;
	}
	else
	{
		return [ApiServer countApiServersInMoc:self.dataManager.managedObjectContext];
	}
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if(tableView==self.projectsTable)
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
	else
	{
		// TODO serverList
	}
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
		if([ApiServer someServersHaveAuthTokensInMoc:self.dataManager.managedObjectContext] && self.preferencesDirty)
		{
			[self startRefresh];
		}
		else
		{
			if(!self.refreshTimer && settings.refreshPeriod>0.0)
			{
				[self startRefreshIfItIsDue];
			}
		}
        [self setUpdateCheckParameters];
	}
}

- (void)setUpdateCheckParameters
{
    SUUpdater *s = [SUUpdater sharedUpdater];
    BOOL autoCheck = settings.checkForUpdatesAutomatically;
	s.automaticallyChecksForUpdates = autoCheck;
    if(autoCheck)
    {
        [s setUpdateCheckInterval:3600.0*settings.checkForUpdatesInterval];
    }
    DLog(@"Check for updates set to %d every %f seconds",s.automaticallyChecksForUpdates,s.updateCheckInterval);
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
		if(howLongAgo>settings.refreshPeriod)
		{
			[self startRefresh];
		}
		else
		{
			NSTimeInterval howLongUntilNextSync = settings.refreshPeriod-howLongAgo;
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
	for(ApiServer *apiServer in [ApiServer allApiServersInMoc:self.dataManager.managedObjectContext])
	{
		if(apiServer.requestsLimit.doubleValue>0)
		{
			if(apiServer.requestsRemaining.doubleValue==0)
			{
				NSAlert *alert = [[NSAlert alloc] init];
				[alert setMessageText:[NSString stringWithFormat:@"Your API request usage for '%@' is over the limit!",apiServer.label]];
				[alert setInformativeText:[NSString stringWithFormat:@"Your request cannot be completed until your hourly API allowance is reset at %@.\n\nIf you get this error often, try to make fewer manual refreshes or reducing the number of repos you are monitoring.\n\nYou can check your API usage at any time from 'Servers' preferences pane at any time.",apiServer.resetDate]];
				[alert addButtonWithTitle:@"OK"];
				[alert runModal];
				return;
			}
			else if((apiServer.requestsRemaining.doubleValue/apiServer.requestsLimit.doubleValue)<LOW_API_WARNING)
			{
				NSAlert *alert = [[NSAlert alloc] init];
				[alert setMessageText:[NSString stringWithFormat:@"Your API request usage for '%@' is close to full",apiServer.label]];
				[alert setInformativeText:[NSString stringWithFormat:@"Try to make fewer manual refreshes, increasing the automatic refresh time, or reducing the number of repos you are monitoring.\n\nYour allowance will be reset by Github on %@.\n\nYou can check your API usage from the 'Servers' preferences pane at any time.",apiServer.resetDate]];
				[alert addButtonWithTitle:@"OK"];
				[alert runModal];
			}
		}
	}
}

- (void)tabView:(NSTabView *)tabView willSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	if([tabView indexOfTabViewItem:tabViewItem]==1)
	{
		if((!self.lastRepoCheck || [Repo countVisibleReposInMoc:self.dataManager.managedObjectContext]==0) &&
		   [ApiServer someServersHaveAuthTokensInMoc:self.dataManager.managedObjectContext])
		{
			[self refreshReposSelected:nil];
		}
	}
}

- (void)prepareForRefresh
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	[self.refreshButton setEnabled:NO];
	[self.projectsTable setEnabled:NO];
	[self.activityDisplay startAnimation:nil];
	self.statusItemView.grayOut = YES;

	[self.api expireOldImageCacheEntries];
	[self.dataManager postMigrationTasks];

	self.isRefreshing = YES;

	for(NSView *v in [self.mainMenu.scrollView.documentView subviews])
		if([v isKindOfClass:[EmptyView class]])
			[self updateMenu];

	self.refreshNow.title = @" Refreshing...";

	DLog(@"Starting refresh");
}

- (void)completeRefresh
{
	self.isRefreshing = NO;
	[self.refreshButton setEnabled:YES];
	[self.projectsTable setEnabled:YES];
	[self.activityDisplay stopAnimation:nil];
	[self.dataManager saveDB];
	[self.projectsTable reloadData];
	[self updateMenu];
	[self checkApiUsage];
	[self.dataManager saveDB];
	[self.dataManager sendNotifications];

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

	[self.api fetchPullRequestsForActiveReposAndCallback:^{
		self.refreshNow.target = oldTarget;
		self.refreshNow.action = oldAction;
		if(![ApiServer shouldReportRefreshFailureInMoc:self.dataManager.managedObjectContext])
		{
			self.lastSuccessfulRefresh = [NSDate date];
			self.preferencesDirty = NO;
		}
		[self completeRefresh];
		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:settings.refreshPeriod
															 target:self
														   selector:@selector(refreshTimerDone)
														   userInfo:nil
															repeats:NO];
	}];
}

- (void)refreshMainWithTarget:(id)oldTarget action:(SEL)oldaction
{

}

- (IBAction)refreshDurationChanged:(NSStepper *)sender
{
	settings.refreshPeriod = self.refreshDurationStepper.floatValue;
	[self.refreshDurationLabel setStringValue:[NSString stringWithFormat:@"Refresh PRs every %ld seconds",(long)self.refreshDurationStepper.integerValue]];
}

- (IBAction)newRepoCheckChanged:(NSStepper *)sender
{
	settings.newRepoCheckPeriod = self.repoCheckStepper.floatValue;
	[self.repoCheckLabel setStringValue:[NSString stringWithFormat:@"Refresh repositories every %ld hours",(long)self.repoCheckStepper.integerValue]];
}

- (void)refreshTimerDone
{
	NSManagedObjectContext *moc = self.dataManager.managedObjectContext;
	if([ApiServer someServersHaveAuthTokensInMoc:moc] && ([Repo countVisibleReposInMoc:moc]>0))
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
	if([ApiServer shouldReportRefreshFailureInMoc:moc])
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

		if(settings.countOnlyListedPrs)
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
							NSForegroundColorAttributeName: [COLOR_CLASS controlTextColor] };
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
	NSInteger mode = settings.statusFilteringMode;
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
	self.statusTermsField.objectValue = settings.statusFilteringTerms;
}

- (IBAction)statusFilterMenuChanged:(NSPopUpButton *)sender
{
	settings.statusFilteringMode = sender.indexOfSelectedItem;
	settings.statusFilteringTerms = self.statusTermsField.objectValue;
	[self updateStatusTermPreferenceControls];
}

- (IBAction)testApiServerSelected:(NSButton *)sender
{
	[sender setEnabled:NO];
	ApiServer *apiServer = [self selectedServer];

	[self.api testApiToServer:apiServer
				  andCallback:^(NSError *error) {
					  NSAlert *alert = [[NSAlert alloc] init];
					  if(error)
					  {
						  [alert setMessageText:[NSString stringWithFormat:@"The test failed for %@", apiServer.apiPath]];
						  [alert setInformativeText:error.localizedDescription];
					  }
					  else
					  {
						  [alert setMessageText:@"This API server seems OK!"];
					  }
					  [alert addButtonWithTitle:@"OK"];
					  [alert runModal];
					  [sender setEnabled:YES];
				  }];
}

- (IBAction)apiRestoreDefaultsSelected:(NSButton *)sender
{
	ApiServer *apiServer = [self selectedServer];
	[apiServer resetToGithub];
	[self fillServerApiFormFromSelectedServer];
	[self storeApiFormToSelectedServer];
}

- (void)fillServerApiFormFromSelectedServer
{
	ApiServer *apiServer = [self selectedServer];
	self.apiServerName.stringValue = [self emptyStringIfNil:apiServer.label];
	self.apiServerWebPath.stringValue = [self emptyStringIfNil:apiServer.webPath];
	self.apiServerApiPath.stringValue = [self emptyStringIfNil:apiServer.apiPath];
	self.apiServerAuthToken.stringValue = [self emptyStringIfNil:apiServer.authToken];
	self.apiServerSelectedBox.title = apiServer.label ? apiServer.label : @"New Server";
	self.apiServerTestButton.enabled = (apiServer.authToken.length>0);
	self.apiServerDeleteButton.enabled = ([ApiServer countApiServersInMoc:self.dataManager.managedObjectContext]>1);
	self.apiServerReportError.integerValue = apiServer.reportRefreshFailures.boolValue;
}

- (void)storeApiFormToSelectedServer
{
	ApiServer *apiServer = [self selectedServer];
	apiServer.label = self.apiServerName.stringValue;
	apiServer.apiPath = self.apiServerApiPath.stringValue;
	apiServer.webPath = self.apiServerWebPath.stringValue;
	apiServer.authToken = self.apiServerAuthToken.stringValue;
	self.apiServerTestButton.enabled = (apiServer.authToken.length>0);
	[self.serverList reloadData];
}

- (NSString *)emptyStringIfNil:(NSString *)string
{
	return string ? string : @"";
}

- (IBAction)addNewApiServerSelected:(NSButton *)sender
{
	ApiServer *a = [ApiServer insertNewServerInMoc:self.dataManager.managedObjectContext];
	a.label = @"New API Server";
	NSUInteger index = [[ApiServer allApiServersInMoc:self.dataManager.managedObjectContext] indexOfObject:a];
	[self.serverList reloadData];
	[self.serverList selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
	[self fillServerApiFormFromSelectedServer];
}

/////////////////////// keyboard shortcuts

- (void)addHotKeySupport
{
	if(AXIsProcessTrustedWithOptions != NULL)
	{
		if(settings.hotkeyEnable)
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
	return v.associatedPullRequest.webUrl;
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

	if(settings.hotkeyCommandModifier)
	{
		if((incomingEvent.modifierFlags & NSCommandKeyMask) == NSCommandKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSCommandKeyMask) == NSCommandKeyMask) check--; else check++;
	}

	if(settings.hotkeyControlModifier)
	{
		if((incomingEvent.modifierFlags & NSControlKeyMask) == NSControlKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSControlKeyMask) == NSControlKeyMask) check--; else check++;
	}

	if(settings.hotkeyOptionModifier)
	{
		if((incomingEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask) check--; else check++;
	}

	if(settings.hotkeyShiftModifier)
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

		NSNumber *n = codeLookup[settings.hotkeyLetter];
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
