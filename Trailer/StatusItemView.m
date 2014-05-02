
@interface StatusItemView ()
{
	NSDictionary *_attributes;
	NSMutableDictionary *_templateAttributes, *_grayAttributes;
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
		_templateAttributes = [attributes mutableCopy];
		_templateAttributes[NSForegroundColorAttributeName] = [COLOR_CLASS whiteColor];
		_grayAttributes = [attributes mutableCopy];
		_grayAttributes[NSForegroundColorAttributeName] = [COLOR_CLASS lightGrayColor];
    }
    return self;
}

- (void)setGrayOut:(BOOL)grayOut
{
	_grayOut = grayOut;
	[self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
	NSImage *oldImage = [NSImage imageNamed:@"menuIcon"];

	NSPoint imagePoint = NSMakePoint(STATUSITEM_PADDING, 1.0);
	NSRect labelRect = CGRectMake(self.bounds.size.height, -5, self.bounds.size.width, self.bounds.size.height);

	if(_highlighted)
	{
		CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
		[[NSColor blueColor] setFill];
		CGContextFillRect(context, dirtyRect);

		[oldImage drawAtPoint:imagePoint fromRect:NSZeroRect operation:NSCompositeXOR fraction:1.0];

		[_label drawInRect:labelRect withAttributes:_templateAttributes];
	}
	else
	{
		[oldImage drawAtPoint:imagePoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];

		if(_grayOut)
		{
			[_label drawInRect:labelRect withAttributes:_grayAttributes];
		}
		else
		{
			[_label drawInRect:labelRect withAttributes:_attributes];
		}
	}
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
