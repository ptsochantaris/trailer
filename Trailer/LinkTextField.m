
@interface LinkTextField ()
{
	NSColor *normalColor;
	BOOL highlighted;
}
@end

@implementation LinkTextField

- (void)viewDidMoveToWindow
{
	[super viewDidMoveToWindow];

	CGRect check = [self.attributedStringValue boundingRectWithSize:self.bounds.size
															options:NSStringDrawingUsesLineFragmentOrigin |
																	NSStringDrawingUsesFontLeading];

	NSTrackingArea *newArea = [[NSTrackingArea alloc] initWithRect:check
														   options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
															 owner:self
														  userInfo:nil];
	[self addTrackingArea:newArea];

    if (NSPointInRect([self.window mouseLocationOutsideOfEventStream], check))
		[self mouseEntered: nil];

	normalColor = self.textColor;
}

- (void)resetCursorRects
{
	[super resetCursorRects];

	if(highlighted)
	{
		CGRect check = [self.attributedStringValue boundingRectWithSize:self.bounds.size
																options:NSStringDrawingUsesLineFragmentOrigin |
																		NSStringDrawingUsesFontLeading];

		[self addCursorRect:check cursor:[NSCursor pointingHandCursor]];
	}
}

- (void)mouseExited:(NSEvent *)theEvent
{
	highlighted = NO;
	if(self.targetUrl)
	{
		self.textColor = normalColor;
		[self.window invalidateCursorRectsForView:self];
	}
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	if(self.targetUrl)
	{
		if(highlighted)
		{
			if(self.needsCommand && (!([theEvent modifierFlags] & NSCommandKeyMask)))
			{
				highlighted = NO;
				self.textColor = normalColor;
				[self.window invalidateCursorRectsForView:self];
			}
		}
		else
		{
			if((!self.needsCommand) || ([theEvent modifierFlags] & NSCommandKeyMask))
			{
				highlighted = YES;
				self.textColor = [COLOR_CLASS blueColor];
				[self.window invalidateCursorRectsForView:self];
			}
		}
	}
}

- (void)mouseDown:(NSEvent *)theEvent
{
	if(self.targetUrl)
	{
		if(self.needsCommand)
		{
			if([theEvent modifierFlags] & NSCommandKeyMask)
			{
				if((theEvent.modifierFlags & NSAlternateKeyMask) == NSAlternateKeyMask)
					[AppDelegate shared].ignoreNextFocusLoss = YES;
				[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:self.targetUrl]];
				[self mouseExited:nil];
			}
			else
			{
				[[self nextResponder] mouseDown:theEvent];
			}
		}
		else
		{
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:self.targetUrl]];
			[self mouseExited:nil];
		}
	}
	else
	{
		[[self nextResponder] mouseDown:theEvent];
	}
}

@end
