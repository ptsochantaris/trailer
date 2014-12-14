#import "SectionHeader.h"

@implementation SectionHeader
{
	CenterTextField *titleView;
}

- (id)initWithTitle:(NSString *)title showRemoveAllButton:(BOOL)show
{
    self = [super initWithFrame:CGRectMake(0, 0, MENU_WIDTH, TITLE_HEIGHT)];
    if (self) {

		self.canDrawSubviewsIntoLayer = YES;

		CGFloat W = MENU_WIDTH-app.scrollBarWidth;
		if(show)
		{
			NSButton *_unpin = [[NSButton alloc] initWithFrame:CGRectMake(W-100, 5.0, 90, TITLE_HEIGHT)];
			[_unpin setTitle:@"Remove All"];
			[_unpin setTarget:self];
			[_unpin setAction:@selector(unPinSelected:)];
			[_unpin setButtonType:NSMomentaryLightButton];
			[_unpin setBezelStyle:NSRoundRectBezelStyle];
			[_unpin setFont:[NSFont systemFontOfSize:10.0]];
			[self addSubview:_unpin];
		}

		NSMutableParagraphStyle *pCenter = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
		pCenter.alignment = NSCenterTextAlignment;

		NSDictionary *titleAttributes = @{ NSFontAttributeName:[NSFont boldSystemFontOfSize:14.0],
										   NSForegroundColorAttributeName:[COLOR_CLASS controlShadowColor],
										   };
		
		CGRect titleRect = CGRectMake(12, 4.0, W-120-AVATAR_SIZE-LEFTPADDING, TITLE_HEIGHT);
		titleView = [[CenterTextField alloc] initWithFrame:titleRect];
		titleView.attributedStringValue = [[NSAttributedString alloc] initWithString:title
																		  attributes:titleAttributes];
		[self addSubview:titleView];
    }
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
	CGContextRef context = (CGContextRef) [[NSGraphicsContext currentContext] graphicsPort];
	CGContextSetFillColorWithColor(context, [COLOR_CLASS controlShadowColor].CGColor);
	CGFloat offset = [MenuWindow usingVibrancy] ? 2.5 : 3.5;
	CGContextFillRect(context, CGRectMake(1.0, offset, MENU_WIDTH-2.0, 0.5));
}

- (void)unPinSelected:(NSButton *)button
{
	[app sectionHeaderRemoveSelected:titleView.attributedStringValue.string];
}

@end
