#import "OSX_AppDelegate.h"
#import <Sparkle/Sparkle.h>

OSX_AppDelegate *app;

@implementation OSX_AppDelegate
{
	id globalKeyMonitor, localKeyMonitor;
	PopTimer *mouseIgnoreTimer, *filterTimer;
	NSView *messageView;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	app = self;

	self.mainMenu.backgroundColor = [COLOR_CLASS whiteColor];

	filterTimer = [[PopTimer alloc] initWithTimeInterval:0.2
												callback:^{
													[app updateMenu];
													[app scrollToTop];
												}];

	mouseIgnoreTimer = [[PopTimer alloc] initWithTimeInterval:0.4
													 callback:^{
														 app.isManuallyScrolling = NO;
													 }];

	[self setupSortMethodMenu];

	[DataManager postProcessAllPrs];

	self.pullRequestDelegate = [[PullRequestDelegate alloc] init];
	self.mainMenu.prTable.dataSource = self.pullRequestDelegate;
	self.mainMenu.prTable.delegate = self.pullRequestDelegate;

	[self updateScrollBarWidth]; // also updates menu

	[self scrollToTop];

	[self.mainMenu updateVibrancy];

	[self startRateLimitHandling];

	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

	NSString *cav = [@"Version " stringByAppendingString:currentAppVersion];
	[self.versionNumber setStringValue:cav];
	[self.aboutVersion setStringValue:cav];

	if([ApiServer someServersHaveAuthTokensInMoc:DataManager.managedObjectContext])
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
											 selector:@selector(updateScrollBarWidth)
												 name:NSPreferredScrollerStyleDidChangeNotification
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateMenu)
												 name:DARK_MODE_CHANGED
											   object:nil];

	[self addHotKeySupport];

	SUUpdater *s = [SUUpdater sharedUpdater];
	[self setUpdateCheckParameters];
	if(!s.updateInProgress && Settings.checkForUpdatesAutomatically)
	{
		[s checkForUpdatesInBackground];
	}
}

- (void)setupSortMethodMenu
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Sorting"];
	if(Settings.sortDescending)
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
	[self.sortModeSelect selectItemAtIndex:Settings.sortMethod];
}

- (IBAction)showLabelsSelected:(NSButton *)sender
{
	Settings.showLabels = (sender.integerValue==1);
	[self updateMenu];

	[self updateLabelOptions];

	api.successfulRefreshesSinceLastLabelCheck = 0;
	if(Settings.showLabels)
	{
		for(Repo *r in [Repo allItemsOfType:@"Repo" inMoc:DataManager.managedObjectContext])
		{
			r.dirty = @YES;
			r.lastDirtied = [NSDate distantPast];
		}
		self.preferencesDirty = YES;
	}
}

- (IBAction)dontConfirmRemoveAllMergedSelected:(NSButton *)sender
{
	Settings.dontAskBeforeWipingMerged = (sender.integerValue==1);
}

- (IBAction)hideAllPrsSection:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	Settings.hideAllPrsSection = setting;
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)markUnmergeableOnUserSectionsOnlySelected:(NSButton *)sender
{
	Settings.markUnmergeableOnUserSectionsOnly = (sender.integerValue==1);
	[self updateMenu];
}

- (IBAction)displayRepositoryNameSelected:(NSButton *)sender
{
	Settings.showReposInName = (sender.integerValue==1);
	[self updateMenu];
}

- (IBAction)useVibrancySelected:(NSButton *)sender
{
	Settings.useVibrancy = (sender.integerValue==1);
	[[NSNotificationCenter defaultCenter] postNotificationName:UPDATE_VIBRANCY_NOTIFICATION object:nil];
}

- (IBAction)logActivityToConsoleSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	Settings.logActivityToConsole = setting;

	if(Settings.logActivityToConsole)
	{
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"Warning"];
		[alert setInformativeText:@"Logging is a feature meant for error reporting, having it constantly enabled will cause this app to be less responsive and use more power"];
		[alert addButtonWithTitle:@"OK"];
		[alert runModal];
	}
}

- (IBAction)includeLabelsInFilteringSelected:(NSButton *)sender
{
	Settings.includeLabelsInFilter = (sender.integerValue==1);
}

- (IBAction)includeRepositoriesInfilterSelected:(NSButton *)sender
{
	Settings.includeReposInFilter = (sender.integerValue==1);
}

- (IBAction)dontConfirmRemoveAllClosedSelected:(NSButton *)sender
{
	BOOL dontConfirm = (sender.integerValue==1);
	Settings.dontAskBeforeWipingClosed = dontConfirm;
}

- (IBAction)autoParticipateOnMentionSelected:(NSButton *)sender
{
	BOOL autoParticipate = (sender.integerValue==1);
	Settings.autoParticipateInMentions = autoParticipate;
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)dontKeepMyPrsSelected:(NSButton *)sender
{
	BOOL dontKeep = (sender.integerValue==1);
	Settings.dontKeepPrsMergedByMe = dontKeep;
}

- (IBAction)hideAvatarsSelected:(NSButton *)sender
{
	BOOL hide = (sender.integerValue==1);
	Settings.hideAvatars = hide;
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)hidePrsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	Settings.shouldHideUncommentedRequests = show;
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)showAllCommentsSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	Settings.showCommentsEverywhere = show;
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)sortOrderSelected:(NSButton *)sender
{
	BOOL descending = (sender.integerValue==1);
	Settings.sortDescending = descending;
	[self setupSortMethodMenu];
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)countOnlyListedPrsSelected:(NSButton *)sender
{
	Settings.countOnlyListedPrs = (sender.integerValue==1);
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)hideNewRespositoriesSelected:(NSButton *)sender
{
	Settings.hideNewRepositories = (sender.integerValue==1);
}

- (IBAction)openPrAtFirstUnreadCommentSelected:(NSButton *)sender
{
	Settings.openPrAtFirstUnreadComment = (sender.integerValue==1);
}

- (IBAction)sortMethodChanged:(id)sender
{
	Settings.sortMethod = self.sortModeSelect.indexOfSelectedItem;
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)showStatusItemsSelected:(NSButton *)sender
{
	Settings.showStatusItems = (sender.integerValue==1);
	[self updateMenu];

	[self updateStatusItemsOptions];

	api.successfulRefreshesSinceLastStatusCheck = 0;
	if(Settings.showStatusItems)
	{
		for(Repo *r in [Repo allItemsOfType:@"Repo" inMoc:DataManager.managedObjectContext])
		{
			r.dirty = @YES;
			r.lastDirtied = [NSDate distantPast];
		}
		self.preferencesDirty = YES;
	}
}

- (void)updateStatusItemsOptions
{
	BOOL enable = Settings.showStatusItems;
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

	NSInteger count = Settings.statusItemRefreshInterval;
	self.statusItemRefreshCounter.integerValue = count;
	if(count>1)
		self.statusItemRescanLabel.stringValue = [NSString stringWithFormat:@"...and re-scan once every %ld refreshes",(long)count];
	else
		self.statusItemRescanLabel.stringValue = [NSString stringWithFormat:@"...and re-scan on every refresh"];
}

- (void)updateLabelOptions
{
	BOOL enable = Settings.showLabels;
	[self.labelRefreshCounter setEnabled:enable];

	if(enable)
	{
		[self.labelRescanLabel setAlphaValue:1.0];
		[self.labelRefreshNote setAlphaValue:1.0];
	}
	else
	{
		[self.labelRescanLabel setAlphaValue:0.5];
		[self.labelRefreshNote setAlphaValue:0.5];
	}

	NSInteger count = Settings.labelRefreshInterval;
	self.labelRefreshCounter.integerValue = count;
	if(count>1)
		self.labelRescanLabel.stringValue = [NSString stringWithFormat:@"...and re-scan once every %ld refreshes",(long)count];
	else
		self.labelRescanLabel.stringValue = [NSString stringWithFormat:@"...and re-scan on every refresh"];
}

- (IBAction)labelRefreshCounterChanged:(NSStepper *)sender
{
	Settings.labelRefreshInterval = self.labelRefreshCounter.integerValue;
	[self updateLabelOptions];
}

- (IBAction)statusItemRefreshCountChanged:(NSStepper *)sender
{
	Settings.statusItemRefreshInterval = self.statusItemRefreshCounter.integerValue;
	[self updateStatusItemsOptions];
}

- (IBAction)makeStatusItemsSelectableSelected:(NSButton *)sender
{
	BOOL yes = (sender.integerValue==1);
	Settings.makeStatusItemsSelectable = yes;
	[self updateMenu];
}

- (IBAction)showCreationSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	Settings.showCreatedInsteadOfUpdated = show;
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)groupbyRepoSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	Settings.groupByRepo = setting;
	[self updateMenu];
}

- (IBAction)moveAssignedPrsToMySectionSelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	Settings.moveAssignedPrsToMySection = setting;
	[DataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)checkForUpdatesAutomaticallySelected:(NSButton *)sender
{
	BOOL setting = (sender.integerValue==1);
	Settings.checkForUpdatesAutomatically = setting;
	[self refreshUpdatePreferences];
}

- (void)refreshUpdatePreferences
{
	BOOL setting = Settings.checkForUpdatesAutomatically;
	NSInteger interval = Settings.checkForUpdatesInterval;

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
	Settings.checkForUpdatesInterval = sender.integerValue;
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
	NSString *urlToOpen = @"https://github.com/ptsochantaris/trailer";
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
				NSManagedObjectID *itemId = [DataManager idForUriPath:notification.userInfo[PULL_REQUEST_ID_KEY]];

				PullRequest *pullRequest = nil;
				if(itemId) // it's a pull request
				{
					pullRequest = (PullRequest *)[DataManager.managedObjectContext existingObjectWithID:itemId error:nil];
					urlToOpen = pullRequest.webUrl;
				}
				else // it's a comment
				{
					itemId = [DataManager idForUriPath:notification.userInfo[COMMENT_ID_KEY]];
					PRComment *c = (PRComment *)[DataManager.managedObjectContext existingObjectWithID:itemId error:nil];
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
	notification.userInfo = [DataManager infoForType:type item:item];

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
	   !Settings.hideAvatars &&
	   [notification respondsToSelector:@selector(setContentImage:)]) // let's add an avatar on this!
	{
		PRComment *c = (PRComment *)item;
		[api haveCachedAvatar:c.avatarUrl
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

- (void)prItemSelected:(PullRequest *)pullRequest alternativeSelect:(BOOL)isAlternative
{
	[self.mainMenu.filter becomeFirstResponder];

	self.ignoreNextFocusLoss = isAlternative;

	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:pullRequest.urlForOpening]];
	[pullRequest catchUpWithComments];

	NSInteger reSelectIndex = isAlternative ? self.mainMenu.prTable.selectedRow : -1;

	[self updateMenu];

	if(reSelectIndex>-1 && reSelectIndex<self.mainMenu.prTable.numberOfRows)
	{
		[self.mainMenu.prTable selectRowIndexes:[NSIndexSet indexSetWithIndex:reSelectIndex] byExtendingSelection:NO];
	}
}

- (void)statusItemTapped
{
	StatusItemView *v = (StatusItemView*)self.statusItem.view;
	if(v.highlighted)
	{
		[self closeMenu];
	}
	else
	{
		v.highlighted = YES;
		[self sizeMenuAndShow:YES];
	}
}

- (void)menuWillOpen:(NSMenu *)menu
{
	if([[menu title] isEqualToString:@"Options"])
	{
		if(!self.isRefreshing)
		{
			self.refreshNow.title = [@" Refresh" stringByAppendingFormat:@" - %@",[api lastUpdateDescription]];
		}
	}
}

- (void)sizeMenuAndShow:(BOOL)show
{
	NSScreen *screen = [NSScreen mainScreen];
	CGFloat rightSide = screen.visibleFrame.origin.x+screen.visibleFrame.size.width;
	StatusItemView *siv = (StatusItemView*)self.statusItem.view;
	CGFloat menuLeft = siv.window.frame.origin.x;
	CGFloat overflow = (menuLeft+MENU_WIDTH)-rightSide;
	if(overflow>0) menuLeft -= overflow;

	CGFloat menuHeight = TOP_HEADER_HEIGHT;
	NSInteger rowCount = self.mainMenu.prTable.numberOfRows;
	CGFloat screenHeight = screen.visibleFrame.size.height;
	if(rowCount==0)
	{
		menuHeight += 95;
	}
	else
	{
		menuHeight += 30;
		for(NSInteger f=0;f<rowCount;f++)
		{
			NSView *rowView = [self.mainMenu.prTable viewAtColumn:0 row:f makeIfNecessary:YES];
			menuHeight += rowView.frame.size.height;
			if(menuHeight>=screenHeight) break;
		}
	}

	CGFloat bottom = screen.visibleFrame.origin.y;
	if(menuHeight<screenHeight)
	{
		bottom += screenHeight-menuHeight;
	}
	else
	{
		menuHeight = screenHeight;
	}

	[self.mainMenu setFrame:CGRectMake(menuLeft, bottom, MENU_WIDTH, menuHeight)
					display:NO
					animate:NO];

	if(show)
	{
		[self.mainMenu.prTable deselectAll:nil];
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
	StatusItemView *siv = (StatusItemView*)self.statusItem.view;
	siv.highlighted = NO;
	[self.mainMenu orderOut:nil];
	[self.mainMenu.prTable deselectAll:nil];
}

- (void)sectionHeaderRemoveSelected:(NSString *)headerTitle
{
	if([headerTitle isEqualToString:kPullRequestSectionNames[kPullRequestSectionMerged]])
	{
		if(Settings.dontAskBeforeWipingMerged)
		{
			[self removeAllMergedRequests];
		}
		else
		{
			NSArray *mergedRequests = [PullRequest allMergedRequestsInMoc:DataManager.managedObjectContext];

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
					Settings.dontAskBeforeWipingMerged = YES;
				}
			}
		}
	}
	else if([headerTitle isEqualToString:kPullRequestSectionNames[kPullRequestSectionClosed]])
	{
		if(Settings.dontAskBeforeWipingClosed)
		{
			[self removeAllClosedRequests];
		}
		else
		{
			NSArray *closedRequests = [PullRequest allClosedRequestsInMoc:DataManager.managedObjectContext];

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
					Settings.dontAskBeforeWipingClosed = YES;
				}
			}
		}
	}
	if(!self.mainMenu.isVisible) [self statusItemTapped];
}

- (void)removeAllMergedRequests
{
	NSArray *mergedRequests = [PullRequest allMergedRequestsInMoc:DataManager.managedObjectContext];
	for(PullRequest *r in mergedRequests)
		[DataManager.managedObjectContext deleteObject:r];
	[DataManager saveDB];
	[self updateMenu];
}

- (void)removeAllClosedRequests
{
	NSArray *closedRequests = [PullRequest allClosedRequestsInMoc:DataManager.managedObjectContext];
	for(PullRequest *r in closedRequests)
		[DataManager.managedObjectContext deleteObject:r];
	[DataManager saveDB];
	[self updateMenu];
}

- (void)unPinSelectedFor:(PullRequest *)pullRequest
{
	[DataManager.managedObjectContext deleteObject:pullRequest];
	[DataManager saveDB];
	[self updateMenu];
}

/*- (void)buildPrMenuItemsFromList:(NSArray *)pullRequests
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
		MessageView *empty = [[MessageView alloc] initWithFrame:CGRectMake(0, 0, MENU_WIDTH, top)
														message:[DataManager reasonForEmptyWithFilter:self.mainMenuFilter.stringValue]];
		[menuContents addSubview:empty];
	}

	menuContents.frame = CGRectMake(0, 0, MENU_WIDTH, top);

	CGPoint lastPos = self.mainMenu.scrollView.contentView.documentVisibleRect.origin;
	self.mainMenu.scrollView.documentView = menuContents;
	[self.mainMenu.scrollView.documentView scrollPoint:lastPos];
}*/

- (void)startRateLimitHandling
{
	[[NSNotificationCenter defaultCenter] addObserver:self.serverList selector:@selector(reloadData) name:API_USAGE_UPDATE object:nil];
	[api updateLimitsFromServer];
}

- (IBAction)refreshReposSelected:(NSButton *)sender
{
	[self prepareForRefresh];
	[self controlTextDidChange:nil];

	NSManagedObjectContext *tempContext = [DataManager tempContext];
	[api fetchRepositoriesToMoc:tempContext andCallback:^{
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
		NSArray *allApiServers = [ApiServer allApiServersInMoc:DataManager.managedObjectContext];
		return allApiServers[selected];
	}
	return nil;
}

- (IBAction)deleteSelectedServerSelected:(NSButton *)sender
{
	ApiServer *selectedServer = [self selectedServer];
	NSInteger index = [[ApiServer allApiServersInMoc:DataManager.managedObjectContext] indexOfObject:selectedServer];
	[DataManager.managedObjectContext deleteObject:selectedServer];
	[self.serverList reloadData];
	[self.serverList selectRowIndexes:[NSIndexSet indexSetWithIndex:MIN(index,self.serverList.numberOfRows-1)] byExtendingSelection:NO];
	[self fillServerApiFormFromSelectedServer];
	[self updateMenu];
	[DataManager saveDB];
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
	else if(obj.object==self.mainMenu.filter)
	{
		[filterTimer push];
	}
	else if(obj.object==self.statusTermsField)
	{
		NSArray *existingTokens = Settings.statusFilteringTerms;
		NSArray *newTokens = self.statusTermsField.objectValue;
		if(![existingTokens isEqualToArray:newTokens])
		{
			Settings.statusFilteringTerms = newTokens;
			[self updateMenu];
		}
	}
	else if(obj.object==self.commentAuthorBlacklist)
	{
		NSArray *existingTokens = Settings.commentAuthorBlacklist;
		NSArray *newTokens = self.commentAuthorBlacklist.objectValue;
		if(![existingTokens isEqualToArray:newTokens])
		{
			Settings.commentAuthorBlacklist = newTokens;
		}
	}
}

- (void)reset
{
	self.preferencesDirty = YES;
	api.successfulRefreshesSinceLastStatusCheck = 0;
	api.successfulRefreshesSinceLastLabelCheck = 0;
	self.lastSuccessfulRefresh = nil;
	self.lastRepoCheck = nil;
	[self.projectsTable reloadData];
	self.refreshButton.enabled = [ApiServer someServersHaveAuthTokensInMoc:DataManager.managedObjectContext];
	[self updateMenu];
}

- (IBAction)markAllReadSelected:(NSMenuItem *)sender
{
	NSFetchRequest *f = [PullRequest requestForPullRequestsWithFilter:self.mainMenu.filter.stringValue];

	for(PullRequest *r in [DataManager.managedObjectContext executeFetchRequest:f error:nil])
		[r catchUpWithComments];
	[self updateMenu];
}

- (IBAction)preferencesSelected:(NSMenuItem *)sender
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	[self.serverList selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

	[api updateLimitsFromServer];
	[self updateStatusTermPreferenceControls];
	self.commentAuthorBlacklist.objectValue = Settings.commentAuthorBlacklist;

	[self.sortModeSelect selectItemAtIndex:Settings.sortMethod];
	[self.prMergedPolicy selectItemAtIndex:Settings.mergeHandlingPolicy];
	[self.prClosedPolicy selectItemAtIndex:Settings.closeHandlingPolicy];

	self.launchAtStartup.integerValue = [self isAppLoginItem];
	self.hideAllPrsSection.integerValue = Settings.hideAllPrsSection;
	self.dontConfirmRemoveAllClosed.integerValue = Settings.dontAskBeforeWipingClosed;
	self.displayRepositoryNames.integerValue = Settings.showReposInName;
	self.includeRepositoriesInFiltering.integerValue = Settings.includeReposInFilter;
	self.includeLabelsInFiltering.integerValue = Settings.includeLabelsInFilter;
	self.dontConfirmRemoveAllMerged.integerValue = Settings.dontAskBeforeWipingMerged;
	self.hideUncommentedPrs.integerValue = Settings.shouldHideUncommentedRequests;
	self.autoParticipateWhenMentioned.integerValue = Settings.autoParticipateInMentions;
	self.hideAvatars.integerValue = Settings.hideAvatars;
	self.dontKeepPrsMergedByMe.integerValue = Settings.dontKeepPrsMergedByMe;
	self.showAllComments.integerValue = Settings.showCommentsEverywhere;
	self.sortingOrder.integerValue = Settings.sortDescending;
	self.showCreationDates.integerValue = Settings.showCreatedInsteadOfUpdated;
	self.groupByRepo.integerValue = Settings.groupByRepo;
	self.moveAssignedPrsToMySection.integerValue = Settings.moveAssignedPrsToMySection;
	self.showStatusItems.integerValue = Settings.showStatusItems;
	self.makeStatusItemsSelectable.integerValue = Settings.makeStatusItemsSelectable;
	self.markUnmergeableOnUserSectionsOnly.integerValue = Settings.markUnmergeableOnUserSectionsOnly;
	self.countOnlyListedPrs.integerValue = Settings.countOnlyListedPrs;
	self.hideNewRepositories.integerValue = Settings.hideNewRepositories;
	self.openPrAtFirstUnreadComment.integerValue = Settings.openPrAtFirstUnreadComment;
	self.logActivityToConsole.integerValue = Settings.logActivityToConsole;
	self.showLabels.integerValue = Settings.showLabels;
	self.useVibrancy.integerValue = Settings.useVibrancy;

	self.hotkeyEnable.integerValue = Settings.hotkeyEnable;
	self.hotkeyControlModifier.integerValue = Settings.hotkeyControlModifier;
	self.hotkeyCommandModifier.integerValue = Settings.hotkeyCommandModifier;
	self.hotkeyOptionModifier.integerValue = Settings.hotkeyOptionModifier;
	self.hotkeyShiftModifier.integerValue = Settings.hotkeyShiftModifier;
	[self enableHotkeySegments];
	[self populateHotkeyLetterMenu];

	[self refreshUpdatePreferences];

	[self updateStatusItemsOptions];
	[self updateLabelOptions];

	[self.hotkeyEnable setEnabled:(AXIsProcessTrustedWithOptions != NULL)];

	[self.repoCheckStepper setFloatValue:Settings.newRepoCheckPeriod];
	[self newRepoCheckChanged:nil];

	[self.refreshDurationStepper setFloatValue:MIN(Settings.refreshPeriod,3600)];
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
	if(Settings.hotkeyEnable)
	{
		if(Settings.hotkeyCommandModifier)
			[self colorButton:self.hotkeyCommandModifier withColor:[NSColor controlTextColor]];
		else
			[self colorButton:self.hotkeyCommandModifier withColor:[NSColor disabledControlTextColor]];

		if(Settings.hotkeyControlModifier)
			[self colorButton:self.hotkeyControlModifier withColor:[NSColor controlTextColor]];
		else
			[self colorButton:self.hotkeyControlModifier withColor:[NSColor disabledControlTextColor]];

		if(Settings.hotkeyOptionModifier)
			[self colorButton:self.hotkeyOptionModifier withColor:[NSColor controlTextColor]];
		else
			[self colorButton:self.hotkeyOptionModifier withColor:[NSColor disabledControlTextColor]];

		if(Settings.hotkeyShiftModifier)
			[self colorButton:self.hotkeyShiftModifier withColor:[NSColor controlTextColor]];
		else
			[self colorButton:self.hotkeyShiftModifier withColor:[NSColor disabledControlTextColor]];
	}
	[self.hotKeyContainer setHidden:!Settings.hotkeyEnable];
	[self.hotKeyHelp setHidden:Settings.hotkeyEnable];
}

- (void)populateHotkeyLetterMenu
{
	NSMutableArray *titles = [NSMutableArray array];
	for(char l='A';l<='Z';l++)
		[titles addObject:[NSString stringWithFormat:@"%c",l]];
	[self.hotkeyLetter addItemsWithTitles:titles];
	[self.hotkeyLetter selectItemWithTitle:Settings.hotkeyLetter];
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
	Settings.hotkeyEnable = self.hotkeyEnable.integerValue;
	Settings.hotkeyLetter = self.hotkeyLetter.titleOfSelectedItem;
	Settings.hotkeyControlModifier = self.hotkeyControlModifier.integerValue;
	Settings.hotkeyCommandModifier = self.hotkeyCommandModifier.integerValue;
	Settings.hotkeyOptionModifier = self.hotkeyOptionModifier.integerValue;
	Settings.hotkeyShiftModifier = self.hotkeyShiftModifier.integerValue;
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
	Settings.mergeHandlingPolicy = sender.indexOfSelectedItem;
}

- (IBAction)prClosePolicySelected:(NSPopUpButton *)sender
{
	Settings.closeHandlingPolicy = sender.indexOfSelectedItem;
}

/////////////////////////////////// Repo table

- (NSArray *)getFilteredRepos
{
	return [Repo reposForFilter:self.repoFilter.stringValue];
}

- (Repo *)repoForRow:(NSUInteger)row
{
	NSInteger parentCount = [DataManager countParentRepos:self.repoFilter.stringValue];
	if(row>parentCount) row--;
	NSArray *filteredRepos = [self getFilteredRepos];
	return filteredRepos[row-1];
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
		NSArray *allServers = [ApiServer allApiServersInMoc:DataManager.managedObjectContext];
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
		return (row == 0 || row == [DataManager countParentRepos:self.repoFilter.stringValue]+1);
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
	else if(tableView==self.mainMenu.prTable)
	{
		NSFetchRequest *f = [PullRequest requestForPullRequestsWithFilter:self.mainMenu.filter.stringValue];
		return [DataManager.managedObjectContext countForFetchRequest:f error:nil];
	}
	else
	{
		return [ApiServer countApiServersInMoc:DataManager.managedObjectContext];
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
		[DataManager saveDB];
		self.preferencesDirty = YES;
	}
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	[DataManager saveDB];
	return NSTerminateNow;
}

- (void)scrollToTop
{
	[self.mainMenu.prTable scrollToBeginningOfDocument:nil];
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
			[self.mainMenu.prTable deselectAll:nil];
		}
		[self.mainMenu.filter becomeFirstResponder];
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
		if([ApiServer someServersHaveAuthTokensInMoc:DataManager.managedObjectContext] && self.preferencesDirty)
		{
			[self startRefresh];
		}
		else
		{
			if(!self.refreshTimer && Settings.refreshPeriod>0.0)
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
	BOOL autoCheck = Settings.checkForUpdatesAutomatically;
	s.automaticallyChecksForUpdates = autoCheck;
	if(autoCheck)
	{
		[s setUpdateCheckInterval:3600.0*Settings.checkForUpdatesInterval];
	}
	DLog(@"Check for updates set to %d every %f seconds",s.automaticallyChecksForUpdates,s.updateCheckInterval);
}

- (void)networkStateChanged
{
	if([api.reachability currentReachabilityStatus]!=NotReachable)
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
		if(howLongAgo>Settings.refreshPeriod)
		{
			[self startRefresh];
		}
		else
		{
			NSTimeInterval howLongUntilNextSync = Settings.refreshPeriod-howLongAgo;
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
	if([Repo countVisibleReposInMoc:DataManager.managedObjectContext]==0)
	{
		[self preferencesSelected:nil];
		return;
	}
	[self startRefresh];
}

- (void)checkApiUsage
{
	for(ApiServer *apiServer in [ApiServer allApiServersInMoc:DataManager.managedObjectContext])
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
		if((!self.lastRepoCheck || [Repo countVisibleReposInMoc:DataManager.managedObjectContext]==0) &&
		   [ApiServer someServersHaveAuthTokensInMoc:DataManager.managedObjectContext])
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
	StatusItemView *siv = (StatusItemView *)self.statusItem.view;
	siv.grayOut = YES;

	[api expireOldImageCacheEntries];
	[DataManager postMigrationTasks];

	self.isRefreshing = YES;

	if(messageView)
	{
		[self updateMenu];
	}

	self.refreshNow.title = @" Refreshing...";

	DLog(@"Starting refresh");
}

- (void)completeRefresh
{
	self.isRefreshing = NO;
	[self.refreshButton setEnabled:YES];
	[self.projectsTable setEnabled:YES];
	[self.activityDisplay stopAnimation:nil];
	[DataManager saveDB];
	[self.projectsTable reloadData];
	[self updateMenu];
	[self checkApiUsage];
	[DataManager saveDB];
	[DataManager sendNotifications];

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

	[api fetchPullRequestsForActiveReposAndCallback:^{
		self.refreshNow.target = oldTarget;
		self.refreshNow.action = oldAction;
		if(![ApiServer shouldReportRefreshFailureInMoc:DataManager.managedObjectContext])
		{
			self.lastSuccessfulRefresh = [NSDate date];
			self.preferencesDirty = NO;
		}
		[self completeRefresh];
		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:Settings.refreshPeriod
															 target:self
														   selector:@selector(refreshTimerDone)
														   userInfo:nil
															repeats:NO];
	}];
}

- (IBAction)refreshDurationChanged:(NSStepper *)sender
{
	Settings.refreshPeriod = self.refreshDurationStepper.floatValue;
	[self.refreshDurationLabel setStringValue:[NSString stringWithFormat:@"Refresh PRs every %ld seconds",(long)self.refreshDurationStepper.integerValue]];
}

- (IBAction)newRepoCheckChanged:(NSStepper *)sender
{
	Settings.newRepoCheckPeriod = self.repoCheckStepper.floatValue;
	[self.repoCheckLabel setStringValue:[NSString stringWithFormat:@"Refresh repositories every %ld hours",(long)self.repoCheckStepper.integerValue]];
}

- (void)refreshTimerDone
{
	NSManagedObjectContext *moc = DataManager.managedObjectContext;
	if([ApiServer someServersHaveAuthTokensInMoc:moc] && ([Repo countVisibleReposInMoc:moc]>0))
	{
		[self startRefresh];
	}
}

- (void)updateMenu
{
	NSString *countString;
	NSDictionary *attributes;
	NSManagedObjectContext *moc = DataManager.managedObjectContext;
	if([ApiServer shouldReportRefreshFailureInMoc:moc])
	{
		countString = @"X";
		attributes = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:10.0],
					    NSForegroundColorAttributeName: MAKECOLOR(0.8, 0.0, 0.0, 1.0) };
	}
	else
	{
		NSUInteger count;
		if(Settings.countOnlyListedPrs)
		{
			NSFetchRequest *f = [PullRequest requestForPullRequestsWithFilter:self.mainMenu.filter.stringValue];
			count = [moc countForFetchRequest:f error:nil];
		}
		else
		{
			count = [PullRequest countOpenRequestsInMoc:moc];
		}

		countString = [NSString stringWithFormat:@"%ld", count];

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

	StatusItemView *siv = [[StatusItemView alloc] initWithFrame:CGRectMake(0, 0, length, H)
														  label:countString
													 attributes:attributes];
	siv.highlighted = [self.mainMenu isVisible];
	siv.grayOut = self.isRefreshing;

	__weak OSX_AppDelegate *weakSelf = self;
	siv.tappedCallback = ^{
		[weakSelf statusItemTapped];
	};

	self.statusItem.view = siv;

	[self.pullRequestDelegate reloadData:self.mainMenu.filter.stringValue];
	[self.mainMenu.prTable reloadData];

	[messageView removeFromSuperview];

	if(self.mainMenu.prTable.numberOfRows == 0)
	{
		messageView = [[MessageView alloc] initWithFrame:CGRectMake(0, 0, MENU_WIDTH, 100)
												 message:[DataManager reasonForEmptyWithFilter:self.mainMenu.filter.stringValue]];
		[self.mainMenu.contentView addSubview:messageView];
	}

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
	NSInteger mode = Settings.statusFilteringMode;
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
	self.statusTermsField.objectValue = Settings.statusFilteringTerms;
}

- (IBAction)statusFilterMenuChanged:(NSPopUpButton *)sender
{
	Settings.statusFilteringMode = sender.indexOfSelectedItem;
	Settings.statusFilteringTerms = self.statusTermsField.objectValue;
	[self updateStatusTermPreferenceControls];
}

- (IBAction)testApiServerSelected:(NSButton *)sender
{
	[sender setEnabled:NO];
	ApiServer *apiServer = [self selectedServer];

	[api testApiToServer:apiServer
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
	self.apiServerDeleteButton.enabled = ([ApiServer countApiServersInMoc:DataManager.managedObjectContext]>1);
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
	ApiServer *a = [ApiServer insertNewServerInMoc:DataManager.managedObjectContext];
	a.label = @"New API Server";
	NSUInteger index = [[ApiServer allApiServersInMoc:DataManager.managedObjectContext] indexOfObject:a];
	[self.serverList reloadData];
	[self.serverList selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
	[self fillServerApiFormFromSelectedServer];
}

/////////////////////// keyboard shortcuts

- (void)addHotKeySupport
{
	if(AXIsProcessTrustedWithOptions != NULL)
	{
		if(Settings.hotkeyEnable)
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

		if([incomingEvent window]!=self.mainMenu) return incomingEvent;

		switch(incomingEvent.keyCode)
		{
			case 125: // down
			{
				if(app.isManuallyScrolling && self.mainMenu.prTable.selectedRow==-1) return nil;
				NSInteger i = self.mainMenu.prTable.selectedRow+1;
				if(i<self.mainMenu.prTable.numberOfRows)
				{
					while(![self.pullRequestDelegate pullRequestAtRow:i]) i++;
					[self scrollToIndex:i];
				}
				return nil;
			}
			case 126: // up
			{
				if(app.isManuallyScrolling && self.mainMenu.prTable.selectedRow==-1) return nil;
				NSInteger i = self.mainMenu.prTable.selectedRow-1;
				if(i>0)
				{
					while(![self.pullRequestDelegate pullRequestAtRow:i]) i--;
					[self scrollToIndex:i];
				}
				return nil;
			}
			case 36: // enter
			{
				NSInteger i = self.mainMenu.prTable.selectedRow;
				if(i>=0)
				{
					PRItemView *v = [self.mainMenu.prTable rowViewAtRow:i makeIfNecessary:NO];
					BOOL isAlternative = ((incomingEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask);
					if(v) [self prItemSelected:[v associatedPullRequest] alternativeSelect:isAlternative];
				}
				return nil;
			}
		}

		return incomingEvent;
	}];
}

- (void)scrollToIndex:(NSInteger)i
{
	app.isManuallyScrolling = YES;
	[mouseIgnoreTimer push];
	[self.mainMenu.prTable scrollRowToVisible:i];
	dispatch_async(dispatch_get_main_queue(), ^{
		[self.mainMenu.prTable selectRowIndexes:[NSIndexSet indexSetWithIndex:i] byExtendingSelection:NO];
	});
}

- (NSString *)focusedItemUrl
{
	NSInteger row = self.mainMenu.prTable.selectedRow;
	PullRequest *pr = nil;
	if(row>=0)
	{
		[self.mainMenu.prTable deselectAll:nil];
		pr = [self.pullRequestDelegate pullRequestAtRow:row];
	}
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		[self.mainMenu.prTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	});
	return pr.webUrl;
}

- (BOOL)checkForHotkey:(NSEvent *)incomingEvent
{
	if(AXIsProcessTrustedWithOptions == NULL) return NO;

	NSInteger check = 0;

	if(Settings.hotkeyCommandModifier)
	{
		if((incomingEvent.modifierFlags & NSCommandKeyMask) == NSCommandKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSCommandKeyMask) == NSCommandKeyMask) check--; else check++;
	}

	if(Settings.hotkeyControlModifier)
	{
		if((incomingEvent.modifierFlags & NSControlKeyMask) == NSControlKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSControlKeyMask) == NSControlKeyMask) check--; else check++;
	}

	if(Settings.hotkeyOptionModifier)
	{
		if((incomingEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask) check++; else check--;
	}
	else
	{
		if((incomingEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask) check--; else check++;
	}

	if(Settings.hotkeyShiftModifier)
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

		NSNumber *n = codeLookup[Settings.hotkeyLetter];
		if(incomingEvent.keyCode==n.integerValue)
		{
			[self statusItemTapped];
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
