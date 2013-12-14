//
//  PRItemView.m
//  Trailer
//
//  Created by Paul Tsochantaris on 01/11/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface PRItemView ()
{
	NSString *_title, *_dates;
	NSInteger _commentsTotal, _commentsNew;
	NSButton *unpin;
	NSTrackingArea *trackingArea;
}
@end

static NSDictionary *_titleAttributes, *_commentCountAttributes, *_commentAlertAttributes, *_createdAttributes;
static NSNumberFormatter *formatter;
static NSDateFormatter *dateFormatter;

@implementation PRItemView

- (id)init
{
    self = [super init];
    if (self)
	{
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			formatter = [[NSNumberFormatter alloc] init];
			formatter.numberStyle = NSNumberFormatterDecimalStyle;

			dateFormatter = [[NSDateFormatter alloc] init];
			dateFormatter.dateStyle = NSDateFormatterLongStyle;
			dateFormatter.timeStyle = NSDateFormatterMediumStyle;
			dateFormatter.doesRelativeDateFormatting = YES;

			NSMutableParagraphStyle *pCenter = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
			pCenter.alignment = NSCenterTextAlignment;

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
			_commentCountAttributes = @{
										NSFontAttributeName:[NSFont menuFontOfSize:9.0],
										NSForegroundColorAttributeName:[NSColor blackColor],
										NSParagraphStyleAttributeName:pCenter,
										};
			_commentAlertAttributes = @{
										NSFontAttributeName:[NSFont menuFontOfSize:9.0],
										NSForegroundColorAttributeName:[NSColor whiteColor],
										NSParagraphStyleAttributeName:pCenter,
										};
		});
		unpin = [[NSButton alloc] initWithFrame:CGRectZero];
		[unpin setTitle:@"Remove"];
		[unpin setTarget:self];
		[unpin setAction:@selector(unPinSelected:)];
		[unpin setHidden:YES];
		[unpin setButtonType:NSMomentaryLightButton];
		[unpin setBezelStyle:NSRoundRectBezelStyle];
		[unpin setFont:[NSFont systemFontOfSize:10.0]];
		[self addSubview:unpin];
    }
    return self;
}

- (void)unPinSelected:(NSButton *)button
{
	[self.delegate unPinSelectedFrom:self];
}

#define REMOVE_BUTTON_WIDTH 80.0
#define LEFTPADDING 50.0
#define DATE_PADDING 22.0

- (void)drawRect:(NSRect)dirtyRect
{
	CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];

	CGFloat badgeSize = 18.0;
	CGFloat W = MENU_WIDTH-LEFTPADDING;
	if(!unpin.isHidden) W -= REMOVE_BUTTON_WIDTH;

	if(_highlighted)
	{
		[[NSColor colorWithWhite:0.95 alpha:1.0] setFill];
		CGContextFillRect(context, dirtyRect);
	}
	[[NSColor blackColor] setFill];

	//////////////////// New count

	if(_commentsNew)
	{
		[[NSColor colorWithRed:1.0 green:0.5 blue:0.5 alpha:1.0] set];

		CGRect countRect = CGRectMake((28.0-badgeSize)*0.5, (self.bounds.size.height-badgeSize)*0.5, badgeSize, badgeSize);
		CGContextFillEllipseInRect(context, countRect);

		countRect = CGRectOffset(countRect, 0, -2.0);
		NSString *countString = [formatter stringFromNumber:@(_commentsNew)];
		[countString drawInRect:countRect withAttributes:_commentAlertAttributes];
	}

	//////////////////// PR count

	if(_commentsTotal)
	{
		[[NSColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0] set];

		CGFloat offset = 24.0;
		if(_commentsNew==0) offset=14.0;
		CGRect countRect = CGRectMake(offset+(25.0-badgeSize)*0.5, (self.bounds.size.height-badgeSize)*0.5, badgeSize, badgeSize);
		CGContextFillEllipseInRect(context, countRect);

		countRect = CGRectOffset(countRect, 0, -2.0);
		NSString *countString = [formatter stringFromNumber:@(_commentsTotal)];
		[countString drawInRect:countRect withAttributes:_commentCountAttributes];
	}

	//////////////////// Title

	CGFloat offset = -3.0;
	[_title drawInRect:CGRectMake(LEFTPADDING, offset+DATE_PADDING, W, self.bounds.size.height-DATE_PADDING) withAttributes:_titleAttributes];

	CGRect dateRect = CGRectMake(LEFTPADDING, offset, W, DATE_PADDING);
	[_dates drawInRect:CGRectInset(dateRect, 0, 1.0) withAttributes:_createdAttributes];
}

- (void)setPullRequest:(PullRequest *)pullRequest
{
	_commentsTotal = [PRComment countCommentsForPullRequestUrl:pullRequest.url inMoc:[AppDelegate shared].managedObjectContext];
	if([AppDelegate shared].api.showCommentsEverywhere || pullRequest.isMine || pullRequest.commentedByMe)
	{
		_commentsNew = [pullRequest unreadCommentCount];
	}
	else
	{
		_commentsNew = 0;
	}
	if([AppDelegate shared].api.showCreatedInsteadOfUpdated)
	{
		_dates = [dateFormatter stringFromDate:pullRequest.createdAt];
	}
	else
	{
		_dates = [dateFormatter stringFromDate:pullRequest.updatedAt];
	}
	_title = pullRequest.title;

	[unpin setHidden:!pullRequest.merged.boolValue];

	CGFloat W = MENU_WIDTH-LEFTPADDING;
	if(!unpin.isHidden) W -= REMOVE_BUTTON_WIDTH;

	CGRect titleSize = [_title boundingRectWithSize:CGSizeMake(W, FLT_MAX)
											options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
										 attributes:_titleAttributes];
	self.frame = CGRectMake(0, 0, MENU_WIDTH, titleSize.size.height+DATE_PADDING);
	unpin.frame = CGRectMake(LEFTPADDING+W, floorf((self.bounds.size.height-24.0)*0.5), REMOVE_BUTTON_WIDTH-10.0, 24.0);
}

- (void)setHighlighted:(BOOL)highlighted
{
	_highlighted = highlighted;
	[self setNeedsDisplay:YES];
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	self.highlighted = YES;
}

- (void)mouseExited:(NSEvent *)theEvent
{
	self.highlighted = NO;
}

- (void)mouseDown:(NSEvent*) event
{
	[self.delegate prItemSelected:self];
}

- (void)updateTrackingAreas
{
	if(trackingArea) [self removeTrackingArea:trackingArea];
	trackingArea = [ [NSTrackingArea alloc] initWithRect:[self bounds]
												 options:NSTrackingMouseEnteredAndExited | NSTrackingActiveInKeyWindow
												   owner:self
												userInfo:nil];
	[self addTrackingArea:trackingArea];

	NSPoint mouseLocation = [[self window] mouseLocationOutsideOfEventStream];
    mouseLocation = [self convertPoint: mouseLocation fromView: nil];

    if (NSPointInRect(mouseLocation, [self bounds]))
		[self mouseEntered: nil];
	else
		[self mouseExited: nil];
}

- (BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	return YES;
}

@end
