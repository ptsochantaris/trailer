
@implementation AppDelegate

static AppDelegate *_static_shared_ref;
+(AppDelegate *)shared { return _static_shared_ref; }

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Useful snippet for resetting prefs when testing
	// NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
	// [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:appDomain];

	self.mainMenu.backgroundColor = [NSColor whiteColor];

	self.filterTimer = [[HTPopTimer alloc] initWithTimeInterval:0.2 target:self selector:@selector(filterTimerPopped)];

	SUUpdater *s = [SUUpdater sharedUpdater];
	if(!s.updateInProgress)
	{
		[s checkForUpdatesInBackground];
	}
	[s setUpdateCheckInterval:28800.0]; // 8 hours
	s.automaticallyChecksForUpdates = YES;

	[NSThread setThreadPriority:0.0];

	_static_shared_ref = self;

	self.dataManager = [[DataManager alloc] init];
	self.api = [[API alloc] init];

	[self setupSortMethodMenu];

    // DEBUG
    //NSArray *allPRs = [PullRequest allItemsOfType:@"PullRequest" inMoc:self.dataManager.managedObjectContext];
    //if(allPRs.count) [allPRs[0] setTitle:nil];

	[self.dataManager postProcessAllPrs];
	[self updateMenu];

	[self startRateLimitHandling];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(defaultsUpdated)
												 name:NSUserDefaultsDidChangeNotification
											   object:nil];

	[[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

	NSString *currentAppVersion = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
	currentAppVersion = [@"Version " stringByAppendingString:currentAppVersion];
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
}

- (void)setupSortMethodMenu
{
	NSMenu *m = [[NSMenu alloc] initWithTitle:@"Sorting"];
	if([Settings shared].sortDescending)
	{
		[m addItemWithTitle:@"Newest First" action:@selector(sortMethodChanged:) keyEquivalent:@""];
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
	[Settings shared].dontKeepMyPrs = dontKeep;
}

- (IBAction)keepClosedPrsSelected:(NSButton *)sender
{
	BOOL keep = (sender.integerValue==1);
	[Settings shared].alsoKeepClosedPrs = keep;
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

- (IBAction)sortMethodChanged:(id)sender
{
	[Settings shared].sortMethod = self.sortModeSelect.indexOfSelectedItem;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
}

- (IBAction)showCreationSelected:(NSButton *)sender
{
	BOOL show = (sender.integerValue==1);
	[Settings shared].showCreatedInsteadOfUpdated = show;
	[self.dataManager postProcessAllPrs]; // apply any view option changes
	[self updateMenu];
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


-(BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
	return YES;
}

-(void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
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

-(void)postNotificationOfType:(PRNotificationType)type forItem:(id)item
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
	}

    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (void)prItemSelected:(PRItemView *)item
{
	PullRequest *r = [PullRequest itemOfType:@"PullRequest" serverId:item.userInfo moc:self.dataManager.managedObjectContext];
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:r.webUrl]];
	[r catchUpWithComments];
	[self updateMenu];
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

-(void)menuWillOpen:(NSMenu *)menu
{
    if([[menu title] isEqualToString:@"Options"])
	{
		if(!self.isRefreshing)
		{
			NSString *prefix;
			if([Settings shared].localUser)
			{
				prefix = [NSString stringWithFormat:@" Refresh %@",[Settings shared].localUser];
			}
			else
			{
				prefix = @" Refresh";
			}
			if(self.lastUpdateFailed)
			{
				self.refreshNow.title = [prefix stringByAppendingString:@" (last update failed!)"];
			}
			else
			{
				long ago = (long)[[NSDate date] timeIntervalSinceDate:self.lastSuccessfulRefresh];
				if(ago<10)
				{
					self.refreshNow.title = [prefix stringByAppendingString:@" (just updated)"];
				}
				else
				{
					self.refreshNow.title = [NSString stringWithFormat:@"%@ (updated %ld seconds ago)",prefix,(long)ago];
				}
			}
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
		self.opening = YES;
		[self.mainMenu setLevel:NSFloatingWindowLevel];
		[self.mainMenu makeKeyAndOrderFront:self];
		[NSApp activateIgnoringOtherApps:YES];
		self.opening = NO;
	}
}

- (void)closeMenu
{
	self.statusItemView.highlighted = NO;
	[self.mainMenu orderOut:nil];
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
    [self statusItemTapped:nil];
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

- (NSInteger)buildPrMenuItemsFromList:(NSArray *)pullRequests
{
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

	NSInteger unreadCommentCount=0;
	for(PullRequest *r in pullRequests)
	{
		NSNumber *sectionIndex = r.sectionIndex;
		if([Settings shared].showCommentsEverywhere ||
		   sectionIndex.integerValue==kPullRequestSectionMine ||
		   sectionIndex.integerValue==kPullRequestSectionParticipated)
			unreadCommentCount += r.unreadComments.integerValue;

		PRItemView *view = [[PRItemView alloc] initWithPullRequest:r userInfo:r.serverId delegate:self];
		[sections[sectionIndex] addObject:view];
	}

	CGFloat top = 10.0;
	NSView *menuContents = [[NSView alloc] initWithFrame:CGRectZero];
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

	menuContents.frame = CGRectMake(0, 0, MENU_WIDTH, top);

	CGPoint lastPos = self.mainMenu.scrollView.contentView.documentVisibleRect.origin;
	self.mainMenu.scrollView.documentView = menuContents;
	[self.mainMenu.scrollView.documentView scrollPoint:lastPos];

	return unreadCommentCount;
}

- (void)defaultsUpdated
{
	if([Settings shared].localUser)
		self.githubDetailsBox.title = [NSString stringWithFormat:@"Repositories for %@",[Settings shared].localUser];
	else
		self.githubDetailsBox.title = @"Your Repositories";
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
	}];
}

-(void)controlTextDidChange:(NSNotification *)obj
{
	if(obj.object==self.githubTokenHolder)
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
	else if(obj.object==self.repoFilter)
	{
		[self.projectsTable reloadData];
	}
	else if(obj.object==self.mainMenuFilter)
	{
		[self.filterTimer push];
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
	self.lastSuccessfulRefresh = nil;
	[DataItem deleteAllObjectsInContext:self.dataManager.managedObjectContext
							 usingModel:self.dataManager.managedObjectModel];
	[self.projectsTable reloadData];
	[self updateMenu];
}

- (IBAction)markAllReadSelected:(NSMenuItem *)sender
{
	for(PullRequest *r in [self pullRequestList])
		[r catchUpWithComments];
	[self updateMenu];
}

- (IBAction)preferencesSelected:(NSMenuItem *)sender
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	[self.api updateLimitFromServer];

	[self.sortModeSelect selectItemAtIndex:[Settings shared].sortMethod];

	if([self isAppLoginItem])
		[self.launchAtStartup setIntegerValue:1];
	else
		[self.launchAtStartup setIntegerValue:0];

    if([Settings shared].dontAskBeforeWipingClosed)
        [self.dontConfirmRemoveAllClosed setIntegerValue:1];
    else
        [self.dontConfirmRemoveAllClosed setIntegerValue:0];

    if([Settings shared].dontAskBeforeWipingMerged)
        [self.dontConfirmRemoveAllMerged setIntegerValue:1];
    else
        [self.dontConfirmRemoveAllMerged setIntegerValue:0];

	if([Settings shared].shouldHideUncommentedRequests)
		[self.hideUncommentedPrs setIntegerValue:1];
	else
		[self.hideUncommentedPrs setIntegerValue:0];

	if([Settings shared].autoParticipateInMentions)
		[self.autoParticipateWhenMentioned setIntegerValue:1];
	else
		[self.autoParticipateWhenMentioned setIntegerValue:0];

	if([Settings shared].hideAvatars)
		[self.hideAvatars setIntegerValue:1];
	else
		[self.hideAvatars setIntegerValue:0];

	if([Settings shared].alsoKeepClosedPrs)
		[self.keepClosedPrs setIntegerValue:1];
	else
		[self.keepClosedPrs setIntegerValue:0];

	if([Settings shared].dontKeepMyPrs)
		[self.dontKeepMyPrs setIntegerValue:1];
	else
		[self.dontKeepMyPrs setIntegerValue:0];

	if([Settings shared].showCommentsEverywhere)
		[self.showAllComments setIntegerValue:1];
	else
		[self.showAllComments setIntegerValue:0];

	if([Settings shared].sortDescending)
		[self.sortingOrder setIntegerValue:1];
	else
		[self.sortingOrder setIntegerValue:0];

	if([Settings shared].showCreatedInsteadOfUpdated)
		[self.showCreationDates setIntegerValue:1];
	else
		[self.showCreationDates setIntegerValue:0];

	[self.refreshDurationStepper setFloatValue:[Settings shared].refreshPeriod];
	[self refreshDurationChanged:nil];

	[self.preferencesWindow setLevel:NSFloatingWindowLevel];
	[self.preferencesWindow makeKeyAndOrderFront:self];
}

- (IBAction)createTokenSelected:(NSButton *)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/settings/tokens/new"]];
}

- (IBAction)viewExistingTokensSelected:(NSButton *)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/settings/applications"]];
}

/////////////////////////////////// Repo table

- (NSArray *)getFileterdRepos
{
	NSArray *allRepos = [Repo allReposSortedByField:@"fullName"
									withTitleFilter:self.repoFilter.stringValue
											  inMoc:self.dataManager.managedObjectContext];
	return allRepos;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *allRepos = [self getFileterdRepos];
	Repo *r = allRepos[row];

	NSButtonCell *cell = [tableColumn dataCellForRow:row];
	cell.title = r.fullName;
	if(r.active.boolValue)
	{
		cell.state = NSOnState;
	}
	else
	{
		cell.state = NSOffState;
	}
	return cell;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [self getFileterdRepos].count;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	NSArray *allRepos = [self getFileterdRepos];
	Repo *r = allRepos[row];
	r.active = @([object boolValue]);
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
		[self scrollToTop];
		[self.mainMenuFilter becomeFirstResponder];
	}
}

- (void)windowDidResignKey:(NSNotification *)notification
{
	if(!self.opening)
	{
		if([notification object]==self.mainMenu)
		{
			[self closeMenu];
		}
	}
}

-(void)windowWillClose:(NSNotification *)notification
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
	}
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
	NSArray *activeRepos = [Repo activeReposInMoc:self.dataManager.managedObjectContext];
	if(activeRepos.count==0)
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

-(void)prepareForRefresh
{
	[self.refreshTimer invalidate];
	self.refreshTimer = nil;

	[self.refreshButton setEnabled:NO];
	[self.projectsTable setEnabled:NO];
	[self.selectAll setEnabled:NO];
	[self.clearAll setEnabled:NO];
	[self.githubTokenHolder setEnabled:NO];
	[self.activityDisplay startAnimation:nil];
	self.statusItemView.grayOut = YES;

	[self.api expireOldImageCacheEntries];
	[self.dataManager postMigrationTasks];
}

-(void)completeRefresh
{
	[self.refreshButton setEnabled:YES];
	[self.projectsTable setEnabled:YES];
	[self.selectAll setEnabled:YES];
	[self.githubTokenHolder setEnabled:YES];
	[self.clearAll setEnabled:YES];
	[self.activityDisplay stopAnimation:nil];
	[self.dataManager saveDB];
	[self.projectsTable reloadData];
	[self updateMenu];
	[self checkApiUsage];
	[self.dataManager sendNotifications];
	[self.dataManager saveDB];
}

-(BOOL)isRefreshing
{
	return self.refreshNow.target==nil;
}

-(void)startRefresh
{
	if(self.isRefreshing) return;
	DLog(@"Starting refresh");
	[self prepareForRefresh];
	id oldTarget = self.refreshNow.target;
	SEL oldAction = self.refreshNow.action;

	if([Settings shared].localUser)
		self.refreshNow.title = [NSString stringWithFormat:@" Refreshing %@...",[Settings shared].localUser];
	else
		self.refreshNow.title = @" Refreshing...";

	[self.refreshNow setAction:nil];
	[self.refreshNow setTarget:nil];

	[self.api fetchPullRequestsForActiveReposAndCallback:^(BOOL success) {
		self.refreshNow.target = oldTarget;
		self.refreshNow.action = oldAction;
		self.lastUpdateFailed = !success;
		[self completeRefresh];
		if(success)
		{
			self.lastSuccessfulRefresh = [NSDate date];
			self.preferencesDirty = NO;
		}
		self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:[Settings shared].refreshPeriod
															 target:self
														   selector:@selector(refreshTimerDone)
														   userInfo:nil
															repeats:NO];
		DLog(@"Refresh done");
	}];
}


- (IBAction)refreshDurationChanged:(NSStepper *)sender
{
	[Settings shared].refreshPeriod = self.refreshDurationStepper.floatValue;
	[self.refreshDurationLabel setStringValue:[NSString stringWithFormat:@"Automatically refresh every %ld seconds",(long)self.refreshDurationStepper.integerValue]];
}

-(void)refreshTimerDone
{
	if([Settings shared].localUserId && [Settings shared].authToken.length)
	{
		[self startRefresh];
	}
}

- (NSArray *)pullRequestList
{
	NSFetchRequest *f = [PullRequest requestForPullRequestsWithFilter:self.mainMenuFilter.stringValue];
	return [self.dataManager.managedObjectContext executeFetchRequest:f error:nil];
}

- (void)updateMenu
{
	NSArray *pullRequests = [self pullRequestList];
	NSString *countString = [NSString stringWithFormat:@"%ld",[PullRequest countOpenRequestsInMoc:self.dataManager.managedObjectContext]];
	NSInteger newCommentCount = [self buildPrMenuItemsFromList:pullRequests];

	DLog(@"Updating menu, %@ total PRs",countString);

	NSDictionary *attributes;
	if(self.lastUpdateFailed)
	{
		countString = @"X";
		attributes = @{
					   NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0],
					   NSForegroundColorAttributeName: [NSColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0],
					   };
	}
	else if(newCommentCount)
	{
		attributes = @{
					   NSFontAttributeName: [NSFont systemFontOfSize:11.0],
					   NSForegroundColorAttributeName: [NSColor colorWithRed:0.8 green:0.0 blue:0.0 alpha:1.0],
					   };
	}
	else
	{
		attributes = @{
					   NSFontAttributeName: [NSFont systemFontOfSize:11.0],
					   NSForegroundColorAttributeName: [NSColor blackColor],
					   };
	}

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

- (IBAction)selectAllSelected:(NSButton *)sender
{
	NSArray *allRepos = [self getFileterdRepos];
	for(Repo *r in allRepos)
	{
		r.active = @YES;
	}
	[self.dataManager saveDB];
	[self.projectsTable reloadData];
	self.preferencesDirty = YES;
}

- (IBAction)clearallSelected:(NSButton *)sender
{
	NSArray *allRepos = [self getFileterdRepos];
	for(Repo *r in allRepos)
	{
		r.active = @NO;
	}
	[self.dataManager saveDB];
	[self.projectsTable reloadData];
	self.preferencesDirty = YES;
}

//////////////// launch at startup from: http://cocoatutorial.grapewave.com/tag/lssharedfilelistitemresolve/

-(void) addAppAsLoginItem
{
	NSString * appPath = [[NSBundle mainBundle] bundlePath];

	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];

	// Create a reference to the shared file list.
	// We are adding it to the current user only.
	// If we want to add it all users, use
	// kLSSharedFileListGlobalLoginItems instead of
	//kLSSharedFileListSessionLoginItems
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
	if (loginItems) {
		//Insert an item to the list.
		LSSharedFileListItemRef item = LSSharedFileListInsertItemURL(loginItems,
																	 kLSSharedFileListItemLast, NULL, NULL,
																	 url, NULL, NULL);
		if (item){
			CFRelease(item);
		}
		CFRelease(loginItems);
	}
}

-(BOOL)isAppLoginItem
{
	NSString * appPath = [[NSBundle mainBundle] bundlePath];

	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];

	// Create a reference to the shared file list.
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);

	if (loginItems) {
		UInt32 seedValue;
		//Retrieve the list of Login Items and cast them to
		// a NSArray so that it will be easier to iterate.
		NSArray  *loginItemsArray = (__bridge_transfer NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
		for(int i = 0 ; i< [loginItemsArray count]; i++){
			LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
			//Resolve the item with URL
			if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr) {
				NSURL *uu = (__bridge NSURL*)url;
				if ([[uu path] compare:appPath] == NSOrderedSame){
					return YES;
				}
			}
		}
	}
	return NO;
}

-(void) deleteAppFromLoginItem
{
	NSString * appPath = [[NSBundle mainBundle] bundlePath];

	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];

	// Create a reference to the shared file list.
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);

	if (loginItems) {
		UInt32 seedValue;
		//Retrieve the list of Login Items and cast them to
		// a NSArray so that it will be easier to iterate.
		NSArray  *loginItemsArray = (__bridge_transfer NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
		for(int i = 0 ; i< [loginItemsArray count]; i++){
			LSSharedFileListItemRef itemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray objectAtIndex:i];
			//Resolve the item with URL
			if (LSSharedFileListItemResolve(itemRef, 0, (CFURLRef*) &url, NULL) == noErr) {
				NSURL *uu = (__bridge NSURL*)url;
				if ([[uu path] compare:appPath] == NSOrderedSame){
					LSSharedFileListItemRemove(loginItems,itemRef);
				}
			}
		}
	}
}

@end
