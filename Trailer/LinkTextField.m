
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
															options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading];

	NSTrackingArea *newArea = [[NSTrackingArea alloc] initWithRect:check
														   options:NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow
															 owner:self
														  userInfo:nil];
	[self addTrackingArea:newArea];

    if (NSPointInRect([self.window mouseLocationOutsideOfEventStream], check))
		[self mouseEntered: nil];

	normalColor = self.textColor;
}

- (void)mouseEntered:(NSEvent *)theEvent
{
	if(self.targetUrl)
	{
		if(self.needsAlt)
		{
			if([theEvent modifierFlags] & NSAlternateKeyMask)
			{
				self.textColor = [NSColor blueColor];
				highlighted = YES;
			}
		}
		else
		{
			self.textColor = [NSColor blueColor];
			highlighted = YES;
		}
	}
}

- (void)mouseExited:(NSEvent *)theEvent
{
	if(self.targetUrl)
		self.textColor = normalColor;
	highlighted = NO;
}

- (void)mouseMoved:(NSEvent *)theEvent
{
	if(!highlighted && self.needsAlt)
	{
		if([theEvent modifierFlags] & NSAlternateKeyMask)
		{
			self.textColor = [NSColor blueColor];
			highlighted = YES;
		}
	}
	else if(highlighted)
	{
		if(!([theEvent modifierFlags] & NSAlternateKeyMask))
		{
			if(self.targetUrl)
				self.textColor = normalColor;
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
			if([theEvent modifierFlags] & NSAlternateKeyMask)
			{
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
