
@interface StatusItemView ()
{
	NSDictionary *_attributes;
	NSString *_label;
	__weak id<StatusItemDelegate> _delegate;
}
@end

@implementation StatusItemView

- (id)initWithFrame:(NSRect)frame label:(NSString *)label attributes:(NSDictionary *)attributes delegate:(id<StatusItemDelegate>)delegate
{
	self = [super initWithFrame:frame];
	if (self) {
		_label = label;
		_delegate = delegate;
		_attributes = attributes;
	}
	return self;
}

- (void)setGrayOut:(BOOL)grayOut
{
	_grayOut = grayOut;
	[self setNeedsDisplay:YES];
}

- (BOOL)darkMode
{
	if(NSAppKitVersionNumber>NSAppKitVersionNumber10_9)
	{
		NSAppearance *c = [NSAppearance currentAppearance];
		if([c respondsToSelector:@selector(allowsVibrancy)])
		{
			return ([c.name containsString:NSAppearanceNameVibrantDark]);
		}
	}
	return NO;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[app.statusItem drawStatusBarBackgroundInRect:dirtyRect
									withHighlight:_highlighted];

	NSPoint imagePoint = NSMakePoint(STATUSITEM_PADDING, 1.0);
	NSRect labelRect = CGRectMake(self.bounds.size.height, -5, self.bounds.size.width, self.bounds.size.height);

	NSMutableDictionary *textAttributes = [_attributes mutableCopy];
	NSImage *icon;

	if(_highlighted)
	{
		icon = [NSImage imageNamed:@"menuIconBright"];
		textAttributes[NSForegroundColorAttributeName] = [COLOR_CLASS selectedMenuItemTextColor];
	}
	else
	{
		if([self darkMode])
		{
			icon = [NSImage imageNamed:@"menuIconBright"];
			if([textAttributes[NSForegroundColorAttributeName] isEqual:[COLOR_CLASS controlTextColor]])
			{
				textAttributes[NSForegroundColorAttributeName] = [COLOR_CLASS selectedMenuItemTextColor];
			}
		}
		else
		{
			icon = [NSImage imageNamed:@"menuIcon"];
		}
	}

	if(_grayOut)
	{
		textAttributes[NSForegroundColorAttributeName] = [COLOR_CLASS disabledControlTextColor];
	}

	[icon drawAtPoint:imagePoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
	[_label drawInRect:labelRect withAttributes:textAttributes];
}

- (void)mouseDown:(NSEvent *)theEvent
{
	[_delegate statusItemTapped:self];
}

- (void)setHighlighted:(BOOL)highlighted
{
	_highlighted = highlighted;
	[self setNeedsDisplay:YES];
}

@end
