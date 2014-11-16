
@interface MenuWindow ()
{
	NSTrackingArea *topArea, *bottomArea;
	NSImageView *topBox, *bottomBox;
	BOOL scrollUp;
	CGFloat scrollDistance;
	NSTimer *scrollTimer;
	HTPopTimer *mouseIgnoreTimer;

	NSArray *vibrancyLayers;
}
@end

@implementation MenuWindow

#define ARROW_BAND_HEIGHT 22.0

- (void)awakeFromNib
{
	[super awakeFromNib];

	topBox = [[NSImageView alloc] initWithFrame:CGRectZero];
	topBox.wantsLayer = YES;
	topBox.image = [NSImage imageNamed:@"upArrow"];
	[topBox setImageAlignment:NSImageAlignCenter];

	bottomBox = [[NSImageView alloc] initWithFrame:CGRectZero];
	bottomBox.wantsLayer = YES;
	bottomBox.image = [NSImage imageNamed:@"downArrow"];
	[bottomBox setImageAlignment:NSImageAlignCenter];

	mouseIgnoreTimer = [[HTPopTimer alloc] initWithTimeInterval:0.4 target:self selector:@selector(mouseIngoreItemPopped:)];

	if([self.scrollView respondsToSelector:@selector(setAutomaticallyAdjustsContentInsets:)])
	{
		[self.scrollView setAutomaticallyAdjustsContentInsets:NO];
	}

	[self.scrollView.contentView setPostsBoundsChangedNotifications:YES];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(boundsDidChange:)
												 name:NSViewBoundsDidChangeNotification
											   object:self.scrollView.contentView];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateVibrancy)
												 name:UPDATE_VIBRANCY_NOTIFICATION
											   object:nil];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(updateVibrancy)
												 name:DARK_MODE_CHANGED
											   object:nil];
}

+ (BOOL)usingVibrancy
{
	return settings.useVibrancy && (NSClassFromString(@"NSVisualEffectView")!=nil);
}

- (void)updateVibrancy
{
	BOOL usingVibrancy = [MenuWindow usingVibrancy];

	[self.header setWantsLayer:usingVibrancy];
	[self.contentView setWantsLayer:usingVibrancy];
	for(NSView *v in vibrancyLayers) [v removeFromSuperview];
	vibrancyLayers = nil;

	// ensure temp[lates are updated
	[topBox.image setTemplate:YES];
	[bottomBox.image setTemplate:YES];

	CGColorRef bgColor;

	if(usingVibrancy)
	{
		// we're on 10.10+ here
		self.scrollView.frame = [self.contentView bounds];
		self.scrollView.contentInsets = NSEdgeInsetsMake(TOP_HEADER_HEIGHT, 0, 0, 0);

		bgColor = [COLOR_CLASS clearColor].CGColor;

		self.appearance = [NSAppearance appearanceNamed:app.statusItemView.darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight];

		NSVisualEffectView *headerVibrant=[[NSVisualEffectView alloc] initWithFrame:self.header.bounds];
		headerVibrant.material = NSVisualEffectMaterialTitlebar;
		headerVibrant.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
		[headerVibrant setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
		[self.header addSubview:headerVibrant positioned:NSWindowBelow relativeTo:nil];

		NSVisualEffectView *topBoxVibrant=[[NSVisualEffectView alloc] initWithFrame:topBox.bounds];
		topBoxVibrant.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
		[topBoxVibrant setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
		[topBox addSubview:topBoxVibrant positioned:NSWindowBelow relativeTo:nil];

		NSVisualEffectView *bottomBoxVibrant=[[NSVisualEffectView alloc] initWithFrame:bottomBox.bounds];
		bottomBoxVibrant.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
		[bottomBoxVibrant setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
		[bottomBox addSubview:bottomBoxVibrant positioned:NSWindowBelow relativeTo:nil];

		NSVisualEffectView *windowVibrant=[[NSVisualEffectView alloc] initWithFrame:[self.contentView bounds]];
		windowVibrant.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
		[windowVibrant setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
		[self.contentView addSubview:windowVibrant positioned:NSWindowBelow relativeTo:nil];

		vibrancyLayers = @[windowVibrant,topBoxVibrant,bottomBoxVibrant,headerVibrant];
	}
	else
	{
		if([self respondsToSelector:@selector(setAppearance:)])
			[self setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];

		bgColor = [COLOR_CLASS controlBackgroundColor].CGColor;

		CGSize windowSize = [self.contentView bounds].size;
		self.scrollView.frame = CGRectMake(0, 0, windowSize.width, windowSize.height-TOP_HEADER_HEIGHT);

		if([self.scrollView respondsToSelector:@selector(setContentInsets:)])
			self.scrollView.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0);
	}

	topBox.layer.backgroundColor = bgColor;
	bottomBox.layer.backgroundColor = bgColor;
	self.header.layer.backgroundColor = bgColor;

	if([self.scrollView respondsToSelector:@selector(setScrollerInsets:)])
		self.scrollView.scrollerInsets = NSEdgeInsetsMake(4.0, 0, 0.0, 0);
}

- (void)boundsDidChange:(NSNotification *)notification
{
	BOOL needLayout = NO;

	if([self shouldShowTop])
	{
		if(!topArea) needLayout = YES;
	}
	else
	{
		if(topArea)
		{
			needLayout = YES;
			[self disableScrollTimer];
		}
	}

	if([self shouldShowBottom])
	{
		if(!bottomArea) needLayout = YES;
	}
	else
	{
		if(bottomArea)
		{
			needLayout = YES;
			[self disableScrollTimer];
		}
	}

	if(needLayout)
	{
		[self layout];
	}
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (void)layout
{
	BOOL needVibrancyUpdate = NO;
	BOOL startedWithTopArea = NO;
	BOOL startedWithBottomArea = NO;

	[topBox removeFromSuperview];
	[bottomBox removeFromSuperview];
	if(topArea)
	{
		startedWithTopArea = YES;
		[self.contentView removeTrackingArea:topArea];
		topArea = nil;
	}
	if(bottomArea)
	{
		startedWithBottomArea = YES;
		[self.contentView removeTrackingArea:bottomArea];
		bottomArea = nil;
	}

	CGSize size = [self.contentView bounds].size;
	if([self shouldShowTop])
	{
		CGFloat offset = TOP_HEADER_HEIGHT;
		if([MenuWindow usingVibrancy]) offset += 4.0;
		CGRect rect = CGRectMake(0, size.height-ARROW_BAND_HEIGHT-offset, size.width-app.scrollBarWidth, ARROW_BAND_HEIGHT);
		topBox.frame = rect;
		[self.contentView addSubview:topBox];
		topArea = [self addTrackingAreaInRect:rect];
		needVibrancyUpdate = !startedWithTopArea;
	}
	else
	{
		needVibrancyUpdate = startedWithTopArea;
	}

	if([self shouldShowBottom])
	{
		CGRect rect = CGRectMake(0, 0, size.width-app.scrollBarWidth, ARROW_BAND_HEIGHT);
		bottomBox.frame = rect;
		[self.contentView addSubview:bottomBox];
		bottomArea = [self addTrackingAreaInRect:rect];
		needVibrancyUpdate = needVibrancyUpdate || !startedWithBottomArea;
	}
	else
	{
		needVibrancyUpdate = needVibrancyUpdate || startedWithBottomArea;
	}

	if(needVibrancyUpdate) [self updateVibrancy];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)scrollToView:(NSView *)view
{
	CGFloat itemBottom = view.frame.origin.y-50;
	CGFloat itemHeight = view.frame.size.height;
	CGFloat itemTop = view.frame.origin.y+itemHeight+30;

	CGFloat containerBottom = self.scrollView.contentView.documentVisibleRect.origin.y;
	CGFloat containerHeight = self.scrollView.contentView.documentVisibleRect.size.height;
	CGFloat containerTop = containerBottom + containerHeight;

	app.isManuallyScrolling = YES;
	[mouseIgnoreTimer push];

	if(itemTop>containerTop)
	{
		[self.scrollView.contentView.documentView scrollPoint:CGPointMake(0, itemTop+itemHeight-containerHeight)];
	}
	else if(itemBottom<containerBottom)
	{
		[self.scrollView.contentView.documentView scrollPoint:CGPointMake(0, itemBottom)];
	}
}

- (void)mouseIngoreItemPopped:(HTPopTimer *)popTimer
{
	app.isManuallyScrolling = NO;
}

- (NSTrackingArea *)addTrackingAreaInRect:(CGRect)trackingRect
{
	NSTrackingArea *newArea = [[NSTrackingArea alloc] initWithRect:trackingRect
											  options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
												owner:self
											 userInfo:nil];

	[self.contentView addTrackingArea:newArea];

    if (NSPointInRect([self mouseLocationOutsideOfEventStream], trackingRect)) [self mouseEntered: nil];

	return newArea;
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	if(!scrollTimer)
	{
		//DLog(@"scroll timer on");
		self.scrollView.ignoreWheel = YES;
		scrollUp =(theEvent.trackingArea==topArea);
		scrollDistance = 0.0;
		scrollTimer = [NSTimer scheduledTimerWithTimeInterval:0.01
													   target:self
													 selector:@selector(scrollStep)
													 userInfo:nil
													  repeats:YES];
	}
}

- (void)mouseExited:(NSEvent *)theEvent
{
	[self disableScrollTimer];
}

- (void)disableScrollTimer
{
	if(scrollTimer)
	{
		//DLog(@"scroll timer off");
		self.scrollView.ignoreWheel = NO;
		[scrollTimer invalidate];
		scrollTimer = nil;
	}
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	CGPoint mouseLocation = [NSEvent mouseLocation];
	NSRect topRectangle = [self convertRectToScreen:topArea.rect];
	NSRect bottomRectangle = [self convertRectToScreen:bottomArea.rect];
	if(CGRectContainsPoint(topRectangle, mouseLocation))
	{
		scrollDistance = - (topRectangle.origin.y-mouseLocation.y);
	}
	else
	{
		scrollDistance = (bottomRectangle.size.height- (mouseLocation.y-bottomRectangle.origin.y));
	}
	scrollDistance *= 0.33;
	scrollDistance = MAX(1.0,scrollDistance*scrollDistance);
}

- (void)scrollStep
{
	CGPoint pos = self.scrollView.contentView.documentVisibleRect.origin;

	if(scrollUp)
		pos = CGPointMake(pos.x, pos.y+scrollDistance);
	else
		pos = CGPointMake(pos.x, pos.y-scrollDistance);

	[self.scrollView.documentView scrollPoint:pos];
}

- (BOOL)shouldShowTop
{
	CGFloat base = self.scrollView.documentVisibleRect.origin.y;
	CGFloat line = self.scrollView.frame.size.height-[self.scrollView.documentView frame].size.height;
	if([self.scrollView respondsToSelector:@selector(contentInsets)])
		line -= self.scrollView.contentInsets.top;
	return (base+line<0);
}

- (BOOL)shouldShowBottom
{
	return (self.scrollView.contentView.documentVisibleRect.origin.y>0);
}

@end
