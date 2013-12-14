//
//  Menu.m
//  Trailer
//
//  Created by Paul Tsochantaris on 13/12/13.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface MenuWindow ()
{
	NSTrackingArea *topArea, *bottomArea;
	BOOL scrollUp;
	CGFloat scrollDistance;
	NSTimer *scrollTimer;
}
@end

@implementation MenuWindow

- (BOOL)canBecomeKeyWindow
{
    return YES;
}

#define TOP_SCROLL_ZONE_HEIGHT 44.0
#define BOTTOM_SCROLL_ZONE_HEIGHT 44.0

- (void)layout
{
	if(topArea) [self.contentView removeTrackingArea:topArea];
	if(bottomArea) [self.contentView removeTrackingArea:bottomArea];

	CGSize size = [self.contentView bounds].size;
	topArea = [ [NSTrackingArea alloc] initWithRect:CGRectMake(0, self.scrollView.frame.size.height-TOP_SCROLL_ZONE_HEIGHT, size.width, TOP_SCROLL_ZONE_HEIGHT)
												 options:NSTrackingMouseEnteredAndExited  | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
												   owner:self
												userInfo:nil];
	[self.contentView addTrackingArea:topArea];

	bottomArea = [ [NSTrackingArea alloc] initWithRect:CGRectMake(0, 0, size.width, BOTTOM_SCROLL_ZONE_HEIGHT)
												 options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
												   owner:self
												userInfo:nil];
	[self.contentView addTrackingArea:bottomArea];
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	self.scrollView.ignoreWheel = YES;
	scrollUp =(theEvent.trackingArea==topArea);
	scrollDistance = 0.0;
	scrollTimer = [NSTimer scheduledTimerWithTimeInterval:0.02 target:self selector:@selector(scrollStep) userInfo:nil repeats:YES];
}

- (void)mouseExited:(NSEvent *)theEvent
{
	self.scrollView.ignoreWheel = NO;
	[scrollTimer invalidate];
	scrollTimer = nil;
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	CGPoint mouseLocation = [NSEvent mouseLocation];
	NSRect topRectangle = [self convertRectToScreen:topArea.rect];
	NSRect bottomRectangle = [self convertRectToScreen:bottomArea.rect];
	if(CGRectContainsPoint(topRectangle, mouseLocation))
	{
		scrollDistance = -(topRectangle.origin.y-mouseLocation.y);
	}
	else
	{
		scrollDistance = (bottomRectangle.size.height-(mouseLocation.y-bottomRectangle.origin.y));
	}
	scrollDistance *= 0.1;
	scrollDistance = MAX(1.0,scrollDistance*scrollDistance);
}

- (void)scrollStep
{
	CGPoint lastPos = self.scrollView.contentView.documentVisibleRect.origin;
	if(scrollUp)
		lastPos = CGPointMake(lastPos.x, lastPos.y+scrollDistance);
	else
		lastPos = CGPointMake(lastPos.x, lastPos.y-scrollDistance);
	[self.scrollView.documentView scrollPoint:lastPos];
}

@end
