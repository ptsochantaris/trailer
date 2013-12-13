//
//  StatusItem.m
//  Trailer
//
//  Created by Paul Tsochantaris on 13/12/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface StatusItem ()
{
	NSDictionary *_attributes;
	NSString *_label;
	__weak id<StatusItemDelegate> _delegate;
}
@end

@implementation StatusItem

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

- (void)drawRect:(NSRect)dirtyRect
{
	NSImage *newImage = [[NSImage alloc] initWithSize:CGSizeMake(self.bounds.size.width, self.bounds.size.height)];

    [newImage lockFocus];
	NSImage *oldImage = [NSImage imageNamed:NSImageNameApplicationIcon];
	[oldImage drawInRect:CGRectMake(STATUSITEM_PADDING, 0, self.bounds.size.height, self.bounds.size.height)
				fromRect:NSZeroRect
			   operation:NSCompositeSourceOver
				fraction:1.0];
	[_label drawInRect:CGRectMake(self.bounds.size.height+STATUSITEM_PADDING, -5, self.bounds.size.width, self.bounds.size.height) withAttributes:_attributes];
    [newImage unlockFocus];

	[newImage setTemplate:_highlighted];

	[newImage drawInRect:self.bounds];
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
