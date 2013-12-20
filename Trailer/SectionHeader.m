//
//  SectionHeader.m
//  Trailer
//
//  Created by Paul Tsochantaris on 06/12/2013.
//  Copyright (c) 2013 HouseTrip. All rights reserved.
//

@interface SectionHeader ()
{
	NSButton *_unpin;
	NSString *_title;
}
@end

@implementation SectionHeader

static NSDictionary *_titleAttributes;

- (id)initWithRemoveAllDelegate:(id<SectionHeaderDelegate>)delegate title:(NSString *)title
{
    self = [super initWithFrame:CGRectMake(0, 0, MENU_WIDTH, 42)];
    if (self) {
		self.delegate = delegate;
		_title = title;

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
			_unpin = [[NSButton alloc] initWithFrame:CGRectMake(MENU_WIDTH-100, -4.0, 90, self.bounds.size.height)];
			[_unpin setTitle:@"Remove All"];
			[_unpin setTarget:self];
			[_unpin setAction:@selector(unPinSelected:)];
			[_unpin setButtonType:NSMomentaryLightButton];
			[_unpin setBezelStyle:NSRoundRectBezelStyle];
			[_unpin setFont:[NSFont systemFontOfSize:10.0]];
			[self addSubview:_unpin];
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
	if([AppDelegate shared].api.hideAvatars)
	{
		[_title drawInRect:CGRectMake(50, -16.0, MENU_WIDTH-170, self.bounds.size.height) withAttributes:_titleAttributes];
	}
	else
	{
		[_title drawInRect:CGRectMake(50+AVATAR_SIZE, -16.0, MENU_WIDTH-170-AVATAR_SIZE, self.bounds.size.height) withAttributes:_titleAttributes];
	}
}

- (void)unPinSelected:(NSButton *)button
{
	[self.delegate sectionHeaderRemoveSelectedFrom:self];
}

@end
