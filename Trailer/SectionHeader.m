//
//  SectionHeader.m
//  Trailer
//
//  Created by Paul Tsochantaris on 06/12/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

#import "SectionHeader.h"

@interface SectionHeader ()
{
	NSButton *unpin;
}
@end

@implementation SectionHeader

static NSDictionary *_titleAttributes;

- (id)initWithRemoveAllDelegate:(id<SectionHeaderDelegate>)delegate
{
    self = [super initWithFrame:CGRectMake(0, 0, MENU_WIDTH, 42)];
    if (self) {
		self.delegate = delegate;

		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{

			NSMutableParagraphStyle *pCenter = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
			pCenter.alignment = NSCenterTextAlignment;

			_titleAttributes = @{
									 NSFontAttributeName:[NSFont boldSystemFontOfSize:14.0],
									 NSForegroundColorAttributeName:[NSColor lightGrayColor],
									 NSBackgroundColorAttributeName:[NSColor clearColor],
									 };
		});
		if(delegate)
		{
			unpin = [[NSButton alloc] initWithFrame:CGRectMake(MENU_WIDTH-110, -4.0, 100, self.bounds.size.height)];
			[unpin setTitle:@"Remove All..."];
			[unpin setTarget:self];
			[unpin setAction:@selector(unPinSelected:)];
			[unpin setButtonType:NSMomentaryLightButton];
			[unpin setBezelStyle:NSRoundRectBezelStyle];
			[unpin setFont:[NSFont systemFontOfSize:10.0]];
			[self addSubview:unpin];
		}
    }
    return self;
}

-(void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	[[NSColor colorWithWhite:0.92 alpha:1.0] setFill];
	CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
	CGContextFillRect(context, CGRectMake(1.0, self.bounds.size.height-5.0, MENU_WIDTH-2.0, 1.0));
	[self.enclosingMenuItem.title drawInRect:CGRectMake(50, -16.0, MENU_WIDTH-170, self.bounds.size.height) withAttributes:_titleAttributes];
}

- (void)unPinSelected:(NSButton *)button
{
	[self.delegate sectionHeaderRemoveSelected:self.enclosingMenuItem];
}

@end
