
@interface MenuWindow ()
{
	NSTrackingArea *topArea, *bottomArea;
	NSImageView *topArrow, *bottomArrow;
	NSBox *topBox, *bottomBox;
	BOOL scrollUp;
	CGFloat scrollDistance;
	NSTimer *scrollTimer;
	HTPopTimer *mouseIgnoreTimer;
}
@end

@implementation MenuWindow

- (void)awakeFromNib
{
	[super awakeFromNib];

	topArrow = [[NSImageView alloc] initWithFrame:CGRectZero];
	topArrow.image = [NSImage imageNamed:@"upArrow"];
	[topArrow setImageAlignment:NSImageAlignTop];

	topBox = [[NSBox alloc] initWithFrame:CGRectZero];
	topBox.boxType = NSBoxCustom;
	topBox.borderType = NSNoBorder;
	topBox.fillColor = [COLOR_CLASS whiteColor];

	bottomArrow = [[NSImageView alloc] initWithFrame:CGRectZero];
	bottomArrow.image = [NSImage imageNamed:@"downArrow"];
	[bottomArrow setImageAlignment:NSImageAlignBottom];

	bottomBox = [[NSBox alloc] initWithFrame:CGRectZero];
	bottomBox.boxType = NSBoxCustom;
	bottomBox.borderType = NSNoBorder;
	bottomBox.fillColor = [COLOR_CLASS whiteColor];

	mouseIgnoreTimer = [[HTPopTimer alloc] initWithTimeInterval:0.4 target:self selector:@selector(mouseIngoreItemPopped:)];

	[self.scrollView.contentView setPostsBoundsChangedNotifications:YES];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(boundsDidChange:)
												 name:NSViewBoundsDidChangeNotification
											   object:self.scrollView.contentView];
}

- (void)boundsDidChange:(NSNotification *)notification
{
	[self testLayout];
}

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

#define SCROLL_ZONE_HEIGHT 22.0
#define TOP_CONTROLS_HEIGHT 28.0

- (void)layout
{
	[topArrow removeFromSuperview];
	[bottomArrow removeFromSuperview];
	[topBox removeFromSuperview];
	[bottomBox removeFromSuperview];
	if(topArea)
	{
		[self.contentView removeTrackingArea:topArea];
		topArea = nil;
	}
	if(bottomArea)
	{
		[self.contentView removeTrackingArea:bottomArea];
		bottomArea = nil;
	}

	CGSize size = [self.contentView bounds].size;
	self.scrollView.frame = CGRectMake(0, 0, size.width, size.height-TOP_CONTROLS_HEIGHT);

	if([self shouldShowTop])
	{
		CGRect rect = CGRectMake(0, size.height-SCROLL_ZONE_HEIGHT-TOP_CONTROLS_HEIGHT, size.width-app.scrollBarWidth, SCROLL_ZONE_HEIGHT);
		topBox.frame = rect;
		topArrow.frame = rect;
		[self.contentView addSubview:topBox];
		[self.contentView addSubview:topArrow];
		topArea = [self addTrackingAreaInRect:rect];
	}

	if([self shouldShowBottom])
	{
		CGRect rect = CGRectMake(0, 0, size.width-app.scrollBarWidth, SCROLL_ZONE_HEIGHT);
		bottomBox.frame = rect;
		bottomArrow.frame = rect;
		[self.contentView addSubview:bottomBox];
		[self.contentView addSubview:bottomArrow];
		bottomArea = [self addTrackingAreaInRect:rect];
	}
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
	return (base+line<0);
}

- (BOOL)shouldShowBottom
{
	return (self.scrollView.contentView.documentVisibleRect.origin.y>0);
}

- (void)testLayout
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

@end
