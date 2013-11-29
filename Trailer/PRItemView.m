//
//  PRItemView.m
//  Trailer
//
//  Created by Paul Tsochantaris on 01/11/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#import "PRItemView.h"

@interface PRItemView ()
{
	NSString *_title, *_dates;
	NSInteger _commentsTotal, _commentsNew;
	NSButton *unpin;
}
@end

static NSDictionary *_titleAttributes, *_titleBoldAttributes, *_commentCountAttributes, *_commentAlertAttributes, *_createdAttributes;
static NSNumberFormatter *formatter;
static NSDateFormatter *dateFormatter;

@implementation PRItemView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
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
								 NSFontAttributeName:[NSFont systemFontOfSize:13.0],
								 NSForegroundColorAttributeName:[NSColor blackColor],
								 NSBackgroundColorAttributeName:[NSColor clearColor],
								 };
			_createdAttributes = @{
								 NSFontAttributeName:[NSFont systemFontOfSize:10.0],
								 NSForegroundColorAttributeName:[NSColor grayColor],
								 NSBackgroundColorAttributeName:[NSColor clearColor],
								 };
			_titleBoldAttributes = @{
									 NSFontAttributeName:[NSFont systemFontOfSize:13.0],
									 NSForegroundColorAttributeName:[NSColor blueColor],
									 NSUnderlineStyleAttributeName: @(NSUnderlineStyleSingle),
									 NSBackgroundColorAttributeName:[NSColor clearColor],
									 };
			_commentCountAttributes = @{
										NSFontAttributeName:[NSFont boldSystemFontOfSize:9.0],
										NSForegroundColorAttributeName:[NSColor blackColor],
										NSParagraphStyleAttributeName:pCenter,
										};
			_commentAlertAttributes = @{
										NSFontAttributeName:[NSFont boldSystemFontOfSize:9.0],
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
	[self.delegate unPinSelectedFrom:[self enclosingMenuItem]];
}

#define REMOVE_BUTTON_WIDTH 80.0
#define LEFTPADDING 50.0
#define ORIGINAL_WIDTH 500.0
#define DATE_PADDING 22.0

- (void)drawRect:(NSRect)dirtyRect
{
	CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];

	[[NSColor blackColor] setFill];

	CGFloat badgeSize = 18.0;
	CGFloat W = ORIGINAL_WIDTH-LEFTPADDING;
	if(!unpin.isHidden) W -= REMOVE_BUTTON_WIDTH;

	//////////////////// New count

	if(_commentsNew)
	{
		[[NSColor redColor] set];

		CGRect countRect = CGRectMake((26.0-badgeSize)*0.5, (self.bounds.size.height-badgeSize)*0.5, badgeSize, badgeSize);
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
		if(_commentsNew==0) offset=15.0;
		CGRect countRect = CGRectMake(offset+(25.0-badgeSize)*0.5, (self.bounds.size.height-badgeSize)*0.5, badgeSize, badgeSize);
		CGContextFillEllipseInRect(context, countRect);

		countRect = CGRectOffset(countRect, 0, -2.0);
		NSString *countString = [formatter stringFromNumber:@(_commentsTotal)];
		[countString drawInRect:countRect withAttributes:_commentCountAttributes];
	}

	//////////////////// Title

	CGFloat offset = -3.0;
	if([[self enclosingMenuItem] isHighlighted])
	{
		[_title drawInRect:CGRectMake(LEFTPADDING, offset+DATE_PADDING, W, self.bounds.size.height-DATE_PADDING) withAttributes:_titleBoldAttributes];
	}
	else
	{
		[_title drawInRect:CGRectMake(LEFTPADDING, offset+DATE_PADDING, W, self.bounds.size.height-DATE_PADDING) withAttributes:_titleAttributes];
	}

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

	CGFloat W = ORIGINAL_WIDTH-LEFTPADDING;
	if(!unpin.isHidden) W -= REMOVE_BUTTON_WIDTH;

	CGRect titleSize = [_title boundingRectWithSize:CGSizeMake(W, FLT_MAX)
											options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
										 attributes:_titleAttributes];
	self.frame = CGRectMake(0, 0, ORIGINAL_WIDTH, titleSize.size.height+DATE_PADDING);
	unpin.frame = CGRectMake(LEFTPADDING+W, (self.bounds.size.height-24.0)*0.5, REMOVE_BUTTON_WIDTH-10.0, 24.0);
}

- (void)mouseDown:(NSEvent*) event
{
    NSMenu *menu = self.enclosingMenuItem.menu;
    [menu cancelTracking];
    [menu performActionForItemAtIndex:[menu indexOfItem:self.enclosingMenuItem]];
}

-(BOOL)acceptsFirstMouse:(NSEvent *)theEvent
{
	return YES;
}

@end
