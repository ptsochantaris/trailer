
@interface MenuWindow ()
{
	PopTimer *mouseIgnoreTimer;
	NSArray *vibrancyLayers;
}
@end

@implementation MenuWindow

#define ARROW_BAND_HEIGHT 22.0

- (void)awakeFromNib
{
	[super awakeFromNib];

	[self.contentView setWantsLayer:YES];

	mouseIgnoreTimer = [[PopTimer alloc] initWithTimeInterval:0.4
													 callback:^{
														 [self mouseIngoreItemPopped];
													 }];

	if([self.scrollView respondsToSelector:@selector(setAutomaticallyAdjustsContentInsets:)])
	{
		[self.scrollView setAutomaticallyAdjustsContentInsets:NO];
	}

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
	return NSAppKitVersionNumber>NSAppKitVersionNumber10_9 && settings.useVibrancy && (NSClassFromString(@"NSVisualEffectView")!=nil);
}

- (void)updateVibrancy
{
	BOOL usingVibrancy = [MenuWindow usingVibrancy];

	for(NSView *v in vibrancyLayers) [v removeFromSuperview];
	vibrancyLayers = nil;

	CGColorRef bgColor;

	if(usingVibrancy)
	{
		// we're on 10.10+ here
		self.scrollView.frame = [self.contentView bounds];
		self.scrollView.contentInsets = NSEdgeInsetsMake(TOP_HEADER_HEIGHT, 0, 0, 0);

		bgColor = [COLOR_CLASS clearColor].CGColor;

		self.appearance = [NSAppearance appearanceNamed:app.statusItemView.darkMode ? NSAppearanceNameVibrantDark : NSAppearanceNameVibrantLight];

		NSVisualEffectView *headerVibrant=[[NSVisualEffectView alloc] initWithFrame:self.header.bounds];
		headerVibrant.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
		[headerVibrant setBlendingMode:NSVisualEffectBlendingModeWithinWindow];
		[self.header addSubview:headerVibrant positioned:NSWindowBelow relativeTo:nil];

		NSVisualEffectView *windowVibrant=[[NSVisualEffectView alloc] initWithFrame:[self.contentView bounds]];
		windowVibrant.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
		[windowVibrant setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
		[self.contentView addSubview:windowVibrant positioned:NSWindowBelow relativeTo:nil];

		vibrancyLayers = @[windowVibrant,headerVibrant];
	}
	else
	{
		if(NSAppKitVersionNumber>NSAppKitVersionNumber10_9)
		{
			[self setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameAqua]];
		}

		bgColor = [COLOR_CLASS controlBackgroundColor].CGColor;

		CGSize windowSize = [self.contentView bounds].size;
		self.scrollView.frame = CGRectMake(0, 0, windowSize.width, windowSize.height-TOP_HEADER_HEIGHT);

		if([self.scrollView respondsToSelector:@selector(setContentInsets:)])
			self.scrollView.contentInsets = NSEdgeInsetsMake(0, 0, 0, 0);
	}

	self.header.layer.backgroundColor = bgColor;

	if([self.scrollView respondsToSelector:@selector(setScrollerInsets:)])
		self.scrollView.scrollerInsets = NSEdgeInsetsMake(4.0, 0, 0.0, 0);
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
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

- (void)mouseIngoreItemPopped
{
	app.isManuallyScrolling = NO;
}

@end
