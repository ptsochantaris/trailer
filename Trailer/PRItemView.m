
@interface PRItemView ()
{
	NSTrackingArea *trackingArea;
	BOOL dragging;
}
@end

static NSDictionary *_titleAttributes, *_createdAttributes, *_statusAttributes;
static NSDateFormatter *dateFormatter;
static CGColorRef _highlightColor;

@implementation PRItemView

#define REMOVE_BUTTON_WIDTH 80.0

+ (void)initialize
{
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{

		dateFormatter = [[NSDateFormatter alloc] init];
		dateFormatter.dateStyle = NSDateFormatterLongStyle;
		dateFormatter.timeStyle = NSDateFormatterMediumStyle;
		dateFormatter.doesRelativeDateFormatting = YES;

		_highlightColor = CGColorCreateCopy(MAKECOLOR(0.95, 0.95, 0.95, 1.0).CGColor);

		_titleAttributes = @{
							 NSFontAttributeName:[NSFont menuFontOfSize:13.0],
							 NSForegroundColorAttributeName:[NSColor blackColor],
							 NSBackgroundColorAttributeName:[NSColor clearColor],
							 };
		_createdAttributes = @{
							   NSFontAttributeName:[NSFont menuFontOfSize:10.0],
							   NSForegroundColorAttributeName:[NSColor grayColor],
							   NSBackgroundColorAttributeName:[NSColor clearColor],
							   };
		NSMutableParagraphStyle *paragraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		paragraphStyle.headIndent = 92.0;
		_statusAttributes = @{
							   NSFontAttributeName:[NSFont fontWithName:@"Monaco" size:9.0],
							   NSBackgroundColorAttributeName:[NSColor clearColor],
							   NSParagraphStyleAttributeName: paragraphStyle
							   };
	});
}

#define AVATAR_PADDING 8.0

- (instancetype)initWithPullRequest:(PullRequest *)pullRequest userInfo:(id)userInfo delegate:(id<PRItemViewDelegate>)delegate
{
    self = [super init];
    if (self)
	{
		self.delegate = delegate;
		_userInfo = userInfo;

		NSInteger _commentsNew = 0;
		NSInteger _commentsTotal = pullRequest.totalComments.integerValue;
		NSInteger sectionIndex = pullRequest.sectionIndex.integerValue;
		if(sectionIndex==kPullRequestSectionMine ||
		   sectionIndex==kPullRequestSectionParticipated ||
		   [Settings shared].showCommentsEverywhere)
		{
			_commentsNew = pullRequest.unreadComments.integerValue;
		}

		NSString *_title = pullRequest.title;
		NSString *_subtitle = pullRequest.subtitle;

		CGFloat W = MENU_WIDTH-LEFTPADDING-[AppDelegate shared].scrollBarWidth;
		BOOL showUnpin = pullRequest.condition.integerValue!=kPullRequestConditionOpen || pullRequest.markUnmergeable;

		if(showUnpin) W -= REMOVE_BUTTON_WIDTH;

		BOOL showAvatar = pullRequest.userAvatarUrl.length && ![Settings shared].hideAvatars;
		if(showAvatar) W -= (AVATAR_SIZE+AVATAR_PADDING);
		else W += 4.0;

		CGFloat titleHeight = [_title boundingRectWithSize:CGSizeMake(W, FLT_MAX)
												   options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
												attributes:_titleAttributes].size.height;

		CGFloat subtitleHeight = [_subtitle boundingRectWithSize:CGSizeMake(W, FLT_MAX)
														 options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
													  attributes:_createdAttributes].size.height+2.0;

		NSMutableArray *statusRects = nil;
		NSArray *statuses = nil;
		CGFloat bottom, CELL_PADDING;
		CGFloat statusBottom = 0;

		if([Settings shared].showStatusItems)
		{
			CELL_PADDING = 10;
			bottom = CELL_PADDING * 0.5;
			statuses = pullRequest.displayedStatuses;
			statusRects = [NSMutableArray arrayWithCapacity:statuses.count];
			for(PRStatus *s in statuses)
			{
				CGFloat H = [s.displayText boundingRectWithSize:CGSizeMake(W, FLT_MAX)
														options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
													 attributes:_statusAttributes].size.height;
				CGRect statusRect = CGRectMake(LEFTPADDING, bottom+statusBottom, W, H);
				statusBottom += H;
				[statusRects addObject:[NSValue valueWithRect:statusRect]];
			}
		}
		else
		{
			CELL_PADDING = 6.0;
			bottom = CELL_PADDING * 0.5;
		}

		self.frame = CGRectMake(0, 0, MENU_WIDTH, titleHeight+subtitleHeight+statusBottom+CELL_PADDING);
		CGRect titleRect = CGRectMake(LEFTPADDING, subtitleHeight+bottom+statusBottom, W, titleHeight);
		CGRect dateRect = CGRectMake(LEFTPADDING, statusBottom+bottom, W, subtitleHeight);
		CGRect pinRect = CGRectMake(LEFTPADDING+W, floorf((self.bounds.size.height-24.0)*0.5), REMOVE_BUTTON_WIDTH-10.0, 24.0);

		CGFloat shift = -4.0;
		if(showAvatar)
		{
			RemoteImageView *userImage = [[RemoteImageView alloc] initWithFrame:CGRectMake(LEFTPADDING, (self.bounds.size.height-AVATAR_SIZE)*0.5, AVATAR_SIZE, AVATAR_SIZE)
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
				CenteredTextField *unmergeableLabel = [[CenteredTextField alloc] initWithFrame:pinRect];
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

		CenteredTextField *title = [[CenteredTextField alloc] initWithFrame:titleRect];
		title.attributedStringValue = [[NSAttributedString alloc] initWithString:_title attributes:_titleAttributes];
		[self addSubview:title];

		CenteredTextField *subtitle = [[CenteredTextField alloc] initWithFrame:dateRect];
		subtitle.attributedStringValue = [[NSAttributedString alloc] initWithString:_subtitle attributes:_createdAttributes];
		[self addSubview:subtitle];

		for(NSInteger count=0;count<statusRects.count;count++)
		{
			CGRect frame = [statusRects[statusRects.count-count-1] rectValue];
			LinkTextField *statusLabel = [[LinkTextField alloc] initWithFrame:frame];

			PRStatus *status = statuses[count];
			statusLabel.targetUrl = status.targetUrl;
			statusLabel.needsCommand = ![Settings shared].makeStatusItemsSelectable;
			statusLabel.attributedStringValue = [[NSAttributedString alloc] initWithString:status.displayText
																				attributes:_statusAttributes];
			statusLabel.textColor = status.colorForDisplay;
			[self addSubview:statusLabel];
		}

		CommentCounts *commentCounts = [[CommentCounts alloc] initWithFrame:CGRectMake(0, 0, LEFTPADDING, self.bounds.size.height)
																unreadCount:_commentsNew
																 totalCount:_commentsTotal];
		[self addSubview:commentCounts];
    }
    return self;
}

- (void)unPinSelected:(NSButton *)button
{
	[self.delegate unPinSelectedFrom:self];
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	if(_focused)
	{
		CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
		CGContextSetFillColorWithColor(context, _highlightColor);
		CGContextFillRect(context, CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height));
	}
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	if(![AppDelegate shared].isManuallyScrolling) self.focused = YES;
}

- (void)mouseExited:(NSEvent *)theEvent
{
	self.focused = NO;
}

- (void)setFocused:(BOOL)focused
{
	if(_focused!=focused)
	{
		_focused = focused;
		[self setNeedsDisplay:YES];
		[[NSNotificationCenter defaultCenter] postNotificationName:PR_ITEM_FOCUSED_NOTIFICATION_KEY
															object:self
														  userInfo:@{ PR_ITEM_FOCUSED_STATE_KEY: @(focused) }];
	}
}

- (void)mouseUp:(NSEvent *)theEvent
{
	if(dragging)
	{
		dragging = NO;
	}
	else
	{
		BOOL isAlternative = ((theEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask);
		[self.delegate prItemSelected:self alternativeSelect:isAlternative];
	}
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
    mouseLocation = [self convertPoint: mouseLocation fromView: nil];

    if (NSPointInRect(mouseLocation, [self bounds]))
		[self mouseEntered: nil];
	else
		if(!_focused) [self mouseExited: nil];
}

/////////////// dragging url off this item

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag
{
	return NSDragOperationCopy;
}

- (BOOL)ignoreModifierKeysWhileDragging { return YES; }

- (void)mouseDragged:(NSEvent *)theEvent
{
	dragging = YES;

    NSPasteboard *pboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    [pboard declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];

	PullRequest *r = [PullRequest itemOfType:@"PullRequest" serverId:self.userInfo moc:[AppDelegate shared].dataManager.managedObjectContext];
    [pboard setString:r.webUrl forType:NSStringPboardType];

	NSPoint globalLocation = [ NSEvent mouseLocation ];
	NSPoint windowLocation = [ [ self window ] convertScreenToBase: globalLocation ];
	NSPoint viewLocation = [ self convertPoint: windowLocation fromView: nil ];
	viewLocation = NSMakePoint(viewLocation.x-28, viewLocation.y-4);

	NSImage *dragIcon = [self scaleImage:[NSApp applicationIconImage]
							  toFillSize:CGSizeMake(32, 32)];

    [self dragImage:dragIcon
				 at:viewLocation
			 offset:CGSizeZero
			  event:theEvent
		 pasteboard:pboard
			 source:self
		  slideBack:YES];
}

- (NSImage *)scaleImage:(NSImage *)image toFillSize:(CGSize)toSize
{
    NSRect targetFrame = NSMakeRect(0, 0, toSize.width, toSize.height);
    NSImageRep *sourceImageRep = [image bestRepresentationForRect:targetFrame
														  context:nil
															hints:nil];

    NSImage *targetImage = [[NSImage alloc] initWithSize:toSize];
    [targetImage lockFocus];
    [sourceImageRep drawInRect: targetFrame];
    [targetImage unlockFocus];

	return targetImage;
}

@end
