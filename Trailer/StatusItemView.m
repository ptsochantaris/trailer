//
//  StatusItem.m
//  Trailer
//
//  Created by Paul Tsochantaris on 13/12/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

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
		_templateAttributes[NSForegroundColorAttributeName] = [NSColor whiteColor];
		_grayAttributes = [attributes mutableCopy];
		_grayAttributes[NSForegroundColorAttributeName] = [NSColor lightGrayColor];
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
	NSImage *oldImage = [NSImage imageNamed:NSImageNameApplicationIcon];
	if(_highlighted)
	{
		CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
		[[NSColor blueColor] setFill];
		CGContextFillRect(context, dirtyRect);

		[oldImage drawInRect:CGRectMake(STATUSITEM_PADDING, 0, self.bounds.size.height, self.bounds.size.height)
					fromRect:NSZeroRect
				   operation:NSCompositeXOR
					fraction:1.0];

		[_label drawInRect:CGRectMake(self.bounds.size.height+STATUSITEM_PADDING, -5, self.bounds.size.width, self.bounds.size.height)
			withAttributes:_templateAttributes];
	}
	else
	{
		[oldImage drawInRect:CGRectMake(STATUSITEM_PADDING, 0, self.bounds.size.height, self.bounds.size.height)
					fromRect:NSZeroRect
				   operation:NSCompositeSourceOver
					fraction:1.0];

		if(_grayOut)
		{
			[_label drawInRect:CGRectMake(self.bounds.size.height+STATUSITEM_PADDING, -5, self.bounds.size.width, self.bounds.size.height)
				withAttributes:_grayAttributes];
		}
		else
		{
			[_label drawInRect:CGRectMake(self.bounds.size.height+STATUSITEM_PADDING, -5, self.bounds.size.width, self.bounds.size.height)
				withAttributes:_attributes];
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
