
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

- (void)mouseEntered:(NSEvent *)theEvent
{
	if(self.targetUrl)
	{
		if(self.needsAlt)
		{
			if([theEvent modifierFlags] & NSCommandKeyMask)
			{
				self.textColor = [COLOR_CLASS blueColor];
				highlighted = YES;
				[self.window invalidateCursorRectsForView:self];
			}
		}
		else
		{
			self.textColor = [COLOR_CLASS blueColor];
			highlighted = YES;
			[self.window invalidateCursorRectsForView:self];
		}
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
	if(!highlighted && self.needsAlt)
	{
		if([theEvent modifierFlags] & NSCommandKeyMask)
		{
			self.textColor = [COLOR_CLASS blueColor];
			highlighted = YES;
			[self.window invalidateCursorRectsForView:self];
		}
	}
	else if(highlighted)
	{
		if(!([theEvent modifierFlags] & NSCommandKeyMask))
		{
			if(self.targetUrl)
			{
				[self.window invalidateCursorRectsForView:self];
				self.textColor = normalColor;
			}
			highlighted = NO;
		}
	}
}

- (void)mouseDown:(NSEvent *)theEvent
{
	if(self.targetUrl)
	{
		if(self.needsAlt)
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
