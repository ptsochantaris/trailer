#import "CommentCounts.h"

@interface PRItemView ()
{
	NSTrackingArea *trackingArea;
	NSManagedObjectID *pullRequestId;
	CenterTextField *title;
	COLOR_CLASS *unselectedTitleColor;
	FONT_CLASS *detailFont, *titleFont;
}
@end

static NSDictionary *_statusAttributes;

@implementation PRItemView

#define REMOVE_BUTTON_WIDTH 80.0

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		paragraphStyle.headIndent = 92.0;
		_statusAttributes = @{ NSFontAttributeName:[NSFont fontWithName:@"Monaco" size:9.0],
							   NSParagraphStyleAttributeName: paragraphStyle,
							   };
	});
}

#define AVATAR_PADDING 8.0

- (instancetype)initWithPullRequest:(PullRequest *)pullRequest
{
	self = [super init];
	if (self)
	{
		pullRequestId = pullRequest.objectID;

		NSInteger _commentsNew = 0;
		NSInteger _commentsTotal = pullRequest.totalComments.integerValue;
		NSInteger sectionIndex = pullRequest.sectionIndex.integerValue;
		if(sectionIndex==kPullRequestSectionMine ||
		   sectionIndex==kPullRequestSectionParticipated ||
		   Settings.showCommentsEverywhere)
		{
			_commentsNew = pullRequest.unreadComments.integerValue;
		}

		detailFont = [NSFont menuFontOfSize:10.0];
		titleFont = [NSFont menuFontOfSize:13.0];

		StatusItemView *v = (StatusItemView*)app.statusItem.view;
		BOOL goneDark = [MenuWindow usingVibrancy] && v.darkMode;

		NSMutableAttributedString *_title = [pullRequest titleWithFont:titleFont
															 labelFont:detailFont
															titleColor:goneDark ? [COLOR_CLASS controlHighlightColor] : [COLOR_CLASS controlTextColor]];

		NSMutableAttributedString *_subtitle = [pullRequest subtitleWithFont:detailFont
																  lightColor:goneDark ? [COLOR_CLASS lightGrayColor] : [COLOR_CLASS grayColor]
																   darkColor:goneDark ? [COLOR_CLASS grayColor] : [COLOR_CLASS darkGrayColor]];

		CGFloat W = MENU_WIDTH-LEFTPADDING-app.scrollBarWidth;
		BOOL showUnpin = pullRequest.condition.integerValue!=kPullRequestConditionOpen || pullRequest.markUnmergeable;

		if(showUnpin) W -= REMOVE_BUTTON_WIDTH;

		BOOL showAvatar = pullRequest.userAvatarUrl.length && !Settings.hideAvatars;
		if(showAvatar) W -= (AVATAR_SIZE+AVATAR_PADDING); else W += 4.0;

		CGFloat titleHeight = [_title boundingRectWithSize:CGSizeMake(W, FLT_MAX)
												   options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading].size.height;
		titleHeight = ceilf(titleHeight);

		CGFloat subtitleHeight = [_subtitle boundingRectWithSize:CGSizeMake(W, FLT_MAX)
														 options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading].size.height+4.0;
		subtitleHeight = ceilf(subtitleHeight);

		NSMutableArray *statusRects = nil;
		NSArray *statuses = nil;
		CGFloat bottom, CELL_PADDING;
		CGFloat statusBottom = 0;

		if(Settings.showStatusItems)
		{
			CELL_PADDING = 10;
			bottom = ceilf(CELL_PADDING * 0.5);
			statuses = pullRequest.displayedStatuses;
			statusRects = [NSMutableArray arrayWithCapacity:statuses.count];
			for(PRStatus *s in statuses)
			{
				CGFloat H = [s.displayText boundingRectWithSize:CGSizeMake(W, FLT_MAX)
														options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
													 attributes:_statusAttributes].size.height;
				H = ceilf(H);
				CGRect statusRect = CGRectMake(LEFTPADDING, bottom+statusBottom, W, H);
				statusBottom += H;
				[statusRects addObject:[NSValue valueWithRect:statusRect]];
			}
		}
		else
		{
			CELL_PADDING = 6.0;
			bottom = ceilf(CELL_PADDING * 0.5);
		}

		self.frame = CGRectMake(0, 0, MENU_WIDTH, titleHeight+subtitleHeight+statusBottom+CELL_PADDING);
		CGRect titleRect = CGRectMake(LEFTPADDING, subtitleHeight+bottom+statusBottom, W, titleHeight);
		CGRect dateRect = CGRectMake(LEFTPADDING, statusBottom+bottom, W, subtitleHeight);
		CGRect pinRect = CGRectMake(LEFTPADDING+W, floorf((self.bounds.size.height-24.0)*0.5), REMOVE_BUTTON_WIDTH-10.0, 24.0);

		CGFloat shift = -4.0;
		if(showAvatar)
		{
			AvatarView *userImage = [[AvatarView alloc] initWithFrame:CGRectMake(LEFTPADDING, (self.bounds.size.height-AVATAR_SIZE)*0.5, AVATAR_SIZE, AVATAR_SIZE)
																  url:pullRequest.userAvatarUrl];
			[self addSubview:userImage];
			shift = AVATAR_PADDING+AVATAR_SIZE;
		}
		pinRect = CGRectOffset(pinRect, shift, 0);
		dateRect = CGRectOffset(dateRect, shift, 0);
		titleRect = CGRectOffset(titleRect, shift, 0);
		NSMutableArray *replacementRects = [NSMutableArray arrayWithCapacity:statusRects.count];
		for(NSValue *rv in statusRects)
		{
			CGRect r = rv.rectValue;
			r = CGRectOffset(r, shift, 0);
			[replacementRects addObject:[NSValue valueWithRect:r]];
		}
		statusRects = replacementRects;
		replacementRects = nil;

		if(showUnpin)
		{
			if(pullRequest.condition.integerValue==kPullRequestConditionOpen)
			{
				CenterTextField *unmergeableLabel = [[CenterTextField alloc] initWithFrame:pinRect];
				unmergeableLabel.textColor = [COLOR_CLASS redColor];
				unmergeableLabel.font = [NSFont fontWithName:@"Monaco" size:8.0];
				unmergeableLabel.alignment = NSCenterTextAlignment;
				[unmergeableLabel setStringValue:@"Cannot be merged"];
				[self addSubview:unmergeableLabel];
			}
			else
			{
				NSButton *unpin = [[NSButton alloc] initWithFrame:pinRect];
				[unpin setTitle:@"Remove"];
				[unpin setTarget:self];
				[unpin setAction:@selector(unPinSelected:)];
				[unpin setButtonType:NSMomentaryLightButton];
				[unpin setBezelStyle:NSRoundRectBezelStyle];
				[unpin setFont:[NSFont systemFontOfSize:10.0]];
				[self addSubview:unpin];
			}
		}

		title = [[CenterTextField alloc] initWithFrame:titleRect];
		title.attributedStringValue = _title;
		[self addSubview:title];

		CenterTextField *subtitle = [[CenterTextField alloc] initWithFrame:dateRect];
		subtitle.attributedStringValue = _subtitle;
		[self addSubview:subtitle];

		for(NSInteger count=0;count<statusRects.count;count++)
		{
			CGRect frame = [statusRects[statusRects.count-count-1] rectValue];
			LinkField *statusLabel = [[LinkField alloc] initWithFrame:frame];

			PRStatus *status = statuses[count];
			statusLabel.targetUrl = status.targetUrl;
			statusLabel.needsCommand = !Settings.makeStatusItemsSelectable;
			statusLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:status.displayText
																				attributes:_statusAttributes];
			statusLabel.textColor = goneDark ? status.colorForDarkDisplay : status.colorForDisplay;
			[self addSubview:statusLabel];
		}

		CommentCounts *commentCounts = [[CommentCounts alloc] initWithFrame:CGRectMake(0, 0, LEFTPADDING, self.bounds.size.height)
																unreadCount:_commentsNew
																 totalCount:_commentsTotal];
		[self addSubview:commentCounts];

		unselectedTitleColor = [title.attributedStringValue attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:nil];

		NSMenu *theMenu = [[NSMenu alloc] initWithTitle:@"PR Options"];
		NSMenuItem *i = [theMenu insertItemWithTitle:@"Copy URL" action:@selector(copyThisPr) keyEquivalent:@"c" atIndex:0];
		i.keyEquivalentModifierMask = NSCommandKeyMask;
		[self setMenu:theMenu];
	}
	return self;
}

- (void)unPinSelected:(NSButton *)button
{
	[app unPinSelectedFor:[self associatedPullRequest]];
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	if(!app.isManuallyScrolling) { self.selected = YES; }
}

- (void)mouseExited:(NSEvent *)theEvent
{
	self.selected = NO;
}

- (void)setSelected:(BOOL)selected
{
	_selected = selected;
	COLOR_CLASS *finalColor = unselectedTitleColor;
	if(_selected)
	{
		[app.mainMenu.prTable selectRowIndexes:[NSIndexSet indexSetWithIndex:[app.mainMenu.prTable rowForView:self]] byExtendingSelection:NO];
		BOOL darkMode = ((StatusItemView *)app.statusItem.view).darkMode;
		if(darkMode) finalColor = [COLOR_CLASS darkGrayColor];
	}
	else
	{
		[app.mainMenu.prTable deselectRow:[app.mainMenu.prTable rowForView:self]];
	}

	title.attributedStringValue = [[self associatedPullRequest] titleWithFont:titleFont
																	labelFont:detailFont
																   titleColor:finalColor];
}

- (void)copyThisPr
{
	NSPasteboard *p = [NSPasteboard generalPasteboard];
	[p clearContents];
	[p declareTypes:@[NSStringPboardType] owner:self];
	[p setString:[self stringForCopy] forType:NSStringPboardType];
}

- (PullRequest *)associatedPullRequest
{
	return (PullRequest*)[DataManager.managedObjectContext existingObjectWithID:pullRequestId error:nil];
}

- (NSString *)stringForCopy
{
	return [self associatedPullRequest].webUrl;
}

- (void)updateTrackingAreas
{
	if(trackingArea) [self removeTrackingArea:trackingArea];
	trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
												options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow
												  owner:self
											   userInfo:nil];
	[self addTrackingArea:trackingArea];

	NSPoint mouseLocation = [[self window] mouseLocationOutsideOfEventStream];
	mouseLocation = [self convertPoint:mouseLocation fromView:nil];

	if (NSPointInRect(mouseLocation, [self bounds]))
		[self mouseEntered: nil];
	else
		if(!self.selected) [self mouseExited: nil];
}

@end
